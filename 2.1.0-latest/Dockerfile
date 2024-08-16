FROM checkmk/check-mk-raw:2.1.0-latest

# Install additional packages
RUN apt-get update && apt-get install libsasl2-modules

# Copy modified docker-entrypoint
COPY ./docker-entrypoint.sh /docker-entrypoint.sh

# Make it executeable
RUN chmod +x /docker-entrypoint.sh