FROM checkmk/check-mk-raw:2.0.0p1

# Install additional packages
RUN apt-get update && apt-get install libsasl2-modules

# Copy modified docker-entrypoint
COPY ./docker-entrypoint.sh /docker-entrypoint.sh

# Make it executeable
RUN chmod +x /docker-entrypoint.sh