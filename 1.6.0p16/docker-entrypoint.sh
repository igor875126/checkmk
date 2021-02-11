#!/bin/bash
# Copyright (C) 2019 tribe29 GmbH - License: GNU General Public License v2
# This file is part of Checkmk (https://checkmk.com). It is subject to the terms and
# conditions defined in the file COPYING, which is part of this source code package.

set -e -o pipefail

HOOKROOT=/docker-entrypoint.d

function exec_hook() {
    HOOKDIR="$HOOKROOT/$1"
    if [ -d "$HOOKDIR" ]; then
        pushd "$HOOKDIR" >/dev/null
        for hook in *; do
            if [ ! -d "$hook" ] && [ -x "$hook" ]; then
                echo "### Running $HOOKDIR/$hook"
                ./"$hook" || true
            fi
        done
        popd >/dev/null
    fi
}

function create_system_apache_config() {
    # We have the special situation that the site apache is directly accessed from
    # external without a system apache reverse proxy. We need to disable the canonical
    # name redirect here to make redirects work as expected.
    #
    # In a reverse proxy setup the proxy would rewrite the host to the host requested by the user.
    # See omd/packages/apache-omd/skel/etc/apache/apache.conf for further information.
    APACHE_DOCKER_CFG="/omd/sites/$CMK_SITE_ID/etc/apache/conf.d/cmk_docker.conf"
    echo -e "# Created for Checkmk docker container\\n\\nUseCanonicalName Off\\n" >"$APACHE_DOCKER_CFG"
    chown "$CMK_SITE_ID:$CMK_SITE_ID" "$APACHE_DOCKER_CFG"
    # Redirect top level requests to the sites base url
    echo -e "# Redirect top level requests to the sites base url\\nRedirectMatch 302 ^/$ /$CMK_SITE_ID/\\n" >>"$APACHE_DOCKER_CFG"
}

if [ -z "$CMK_SITE_ID" ]; then
    echo "ERROR: No site ID given"
    exit 1
fi

trap 'omd stop '"$CMK_SITE_ID"'; exit 0' SIGTERM SIGHUP SIGINT

# Configure timezone
if [ ! -z "$TIMEZONE" ]; then
    echo "### Setting timezone $TIMEZONE"
    rm /etc/localtime
    ln -s /usr/share/zoneinfo/$TIMEZONE /etc/localtime
fi

# Prepare local MTA for sending to smart host
if [ ! -z "$MAIL_RELAY_HOST" ]; then
    echo "### PREPARE POSTFIX (Hostname: $HOSTNAME, Relay host: $MAIL_RELAY_HOST)"
    echo "$HOSTNAME" > /etc/mailname
    echo "[$MAIL_RELAY_HOST]:$MAIL_RELAY_PORT $MAIL_RELAY_USERNAME:$MAIL_RELAY_PASSWORD" > /etc/postfix/sasl/sasl_passwd
    postmap /etc/postfix/sasl/sasl_passwd
    #chown root:root /etc/postfix/sasl/sasl_passwd /etc/postfix/sasl/sasl_passwd.db
    #chmod 0600 /etc/postfix/sasl/sasl_passwd /etc/postfix/sasl sasl_passwd.db
    postconf -e relayhost=[$MAIL_RELAY_HOST]:$MAIL_RELAY_PORT
    postconf -e smtp_sasl_auth_enable=yes
    postconf -e smtp_sasl_security_options=noanonymous
    postconf -e smtp_sasl_password_maps=hash:/etc/postfix/sasl/sasl_passwd
    postconf -e smtp_tls_security_level=encrypt
    postconf -e smtp_tls_security_level=verify
    postconf -e smtp_tls_CAfile=/etc/ssl/certs/ca-certificates.crt
    postconf -e myorigin="$MAIL_RELAY_USERNAME"
    postconf -e mydestination="$MAIL_RELAY_USERNAME"
    postconf -e myhostname="$HOSTNAME"
    postconf -e mynetworks="127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128"
    postconf -e mailbox_size_limit=0
    postconf -e recipient_delimiter=+
    postconf -e inet_interfaces=all
    postconf -e inet_protocols=all
    echo "root:       $MAIL_RELAY_USERNAME" >> /etc/aliases
    echo "devnull:     /dev/null" >> /etc/aliases
    

    echo "### STARTING MAIL SERVICES"
    syslogd
    /etc/init.d/postfix start
fi

# Create the site in case it does not exist
#
# Check for a file in the directory because the directory itself might have
# been pre-created by docker when the --tmpfs option is used to create a
# site tmpfs below tmp.
if [ ! -d "/opt/omd/sites/$CMK_SITE_ID/etc" ]; then
    echo "### CREATING SITE '$CMK_SITE_ID'"
    exec_hook pre-create
    omd create --no-tmpfs -u 1000 -g 1000 --admin-password "$CMK_PASSWORD" "$CMK_SITE_ID"
    omd config "$CMK_SITE_ID" set APACHE_TCP_ADDR 0.0.0.0
    omd config "$CMK_SITE_ID" set APACHE_TCP_PORT 5000

    create_system_apache_config

    if [ "$CMK_LIVESTATUS_TCP" = "on" ]; then
        omd config "$CMK_SITE_ID" set LIVESTATUS_TCP on
    fi
    exec_hook post-create
fi

# In case of an update (see update procedure docs) the container is started
# with the data volume mounted (the site is not re-created). In this
# situation only the site data directory is available and the "system level"
# parts are missing. Check for them here and create them.
## TODO: This should be supported by a omd command (omd init or similar)
if ! getent group "$CMK_SITE_ID" >/dev/null; then
    groupadd -g 1000 "$CMK_SITE_ID"
fi
if ! getent passwd "$CMK_SITE_ID" >/dev/null; then
    useradd -u 1000 -d "/omd/sites/$CMK_SITE_ID" -c "OMD site $CMK_SITE_ID" -g "$CMK_SITE_ID" -G omd -s /bin/bash "$CMK_SITE_ID"
fi
if [ ! -f "/omd/apache/$CMK_SITE_ID.conf" ]; then
    echo "Include /omd/sites/$CMK_SITE_ID/etc/apache/mode.conf" >"/omd/apache/$CMK_SITE_ID.conf"
fi

# In case the version symlink is dangling we are in an update situation: The
# volume was previously attached to a container with another Check_MK version.
# We now have to perform the "omd update" to be able to bring the site back
# to life.
if [ ! -e "/omd/sites/$CMK_SITE_ID/version" ]; then
    echo "### UPDATING SITE"
    exec_hook pre-update
    create_system_apache_config
    omd -f update --conflict=install "$CMK_SITE_ID"
    exec_hook post-update
fi

# When a command is given via "docker run" use it instead of this script
if [ -n "$1" ]; then
    exec "$@"
fi

echo "### STARTING XINETD"
service xinetd start

echo "### STARTING SITE"
exec_hook pre-start

# Make web interface be accessable even we are behind proxy
sed -i "s|ServerName 0.0.0.0:5000||g" /omd/sites/cmk/etc/apache/listen-port.conf
cp /custom/config.php /opt/omd/sites/cmk/etc/pnp4nagios/config.php

omd start "$CMK_SITE_ID"
exec_hook post-start

echo "### STARTING CRON"
cron -f &

echo "### CONTAINER STARTED"
wait