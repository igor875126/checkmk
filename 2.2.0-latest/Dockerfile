FROM checkmk/check-mk-raw:2.2.0-latest

# Copy modified docker-entrypoint
COPY ./docker-entrypoint.sh /docker-entrypoint.sh

# Make it executeable
RUN echo "SELINUX=disabled" > /etc/selinux/config && chmod +x /docker-entrypoint.sh