FROM checkmk/check-mk-raw:1.6.0p11

# Install additional packages
RUN apt-get update && apt-get install libsasl2-modules

# Copy modified docker-entrypoint
COPY ./docker-entrypoint.sh /docker-entrypoint.sh

# Copy custom config
COPY ./config.php /custom/config.php

# Make it executeable
RUN chmod +x /docker-entrypoint.sh