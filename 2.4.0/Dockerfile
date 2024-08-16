FROM checkmk/check-mk-raw:2.4.0-2024.08.14

# Copy modified docker-entrypoint
COPY ./docker-entrypoint.sh /docker-entrypoint.sh

# Make it executeable
RUN echo "SELINUX=disabled" > /etc/selinux/config && chmod +x /docker-entrypoint.sh