ARG DRUPAL_VERSION=${DRUPAL_VERSION:-11.2.4-php8.3-fpm-bookworm}

FROM drupal:${DRUPAL_VERSION}

# Redeclare build arguments for use in build stage
ARG MODE=production

# Metadata
LABEL org.opencontainers.image.source=https://github.com/soda-collections-objects-data-literacy/wisski-base-image.git
LABEL org.opencontainers.image.description="Plain Drupal with preinstalled Site and basic WissKI environment with only core components with connection to triplestore provided by env variables."

# Install apts

RUN apt-get update; \
    apt-get install -y --no-install-recommends \
    apt-utils \
    autoconf \
    automake \
    default-mysql-client \
    git \
    iipimage-doc \
    iipimage-server \
    imagemagick \
    libaom3 \
    libavif-dev \
    libavif15 \
    libbrotli-dev \
    libdav1d6 \
    libfreetype6-dev \
    libgmp-dev \
    libjpeg-dev \
    libjpeg62-turbo \
    libonig-dev \
    libpng-dev \
    libpng16-16 \
    libpq-dev \
    libtiff-dev \
    libtiff5-dev \
    libtool \
    libvips-dev \
    libvips-tools \
    libzip-dev \
    netcat-openbsd \
    openjdk-17-jdk \
    nginx \
    redis-server \
    sendmail \
    unzip \
    vim \
    wget;

# Install apcu
RUN set -eux; \
    pecl install apcu;

# Configure and install GD extension with AVIF support
RUN docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
    --with-webp \
    --with-avif \
    && docker-php-ext-install -j$(nproc) gd

# Install intl
RUN set -eux; \
    docker-php-ext-configure intl \
    && docker-php-ext-install intl;

# Upload progress
RUN	set -eux; \
    git clone https://github.com/php/pecl-php-uploadprogress/ /usr/src/php/ext/uploadprogress/; \
    docker-php-ext-configure uploadprogress; \
    docker-php-ext-install uploadprogress; \
    rm -rf /usr/src/php/ext/uploadprogress;

# Redis
RUN set -eux; \
    pecl install redis-6.1.0; \
    docker-php-ext-enable redis;

# Install iipsrv
RUN set -eux; \
    git clone https://github.com/ruven/iipsrv.git; \
    cd iipsrv; \
    ./autogen.sh; \
    ./configure; \
    make; \
    mkdir /fcgi-bin; \
    cp src/iipsrv.fcgi /fcgi-bin/iipsrv.fcgi; \
    cd /; \
    rm -rf /iipsrv

# Add php configs
# Cron + Drush tasks should NOT use APCu → causes stale caches during deployments.
COPY config/apcu/zz-apcu-custom.ini /usr/local/etc/php/conf.d/zz-apcu-custom.ini

# Redis configuration
# Note: extension is already enabled by docker-php-ext-enable above
# Wait 5 seconds before retrying to acquire the lock (wait forever can freeze ajax)
COPY config/redis/zz-redis-custom.ini /usr/local/etc/php/conf.d/zz-redis-custom.ini

# set memory settings for WissKI
COPY config/wisski/zz-wisski-recommended.ini /usr/local/etc/php/conf.d/zz-wisski-recommended.ini

# Disable deprecated assert.* directives (PHP 8.4+).
COPY config/assert/zz-assert-disable.ini /usr/local/etc/php/conf.d/zz-assert-disable.ini

# Enable output buffering
COPY config/drupal/zz-drupal-recommended.ini /usr/local/etc/php/conf.d/zz-drupal-recommended.ini

# Copy config files to temp location for conditional copying
COPY config/ /tmp/config/

# Configure opcache
# see https://secure.php.net/manual/en/opcache.installation.php
RUN set -eux; \
    if [ "$MODE" = "development" ]; then \
    cp /tmp/config/opcache/zz-opcache-recommended-dev.ini /usr/local/etc/php/conf.d/zz-opcache-recommended.ini; \
    else \
    cp /tmp/config/opcache/zz-opcache-recommended-prod.ini /usr/local/etc/php/conf.d/zz-opcache-recommended.ini; \
    fi

# Configure mysqli
# see https://secure.php.net/manual/en/opcache.installation.php
COPY config/mysqli/zz-mysqli-recommended.ini /usr/local/etc/php/conf.d/zz-mysqli-recommended.ini

# Configure session
COPY config/session/zz-session-recommended.ini /usr/local/etc/php/conf.d/zz-session-recommended.ini

# Configure xdebug
RUN mkdir -p /var/log/xdebug && chown www-data:www-data /var/log/xdebug
RUN set -eux; \
    (([ "$MODE" = "development" ] && pecl install xdebug-3.4.3 && \
    cp /tmp/config/xdebug/zz-xdebug.ini /usr/local/etc/php/conf.d/zz-xdebug.ini && \
    docker-php-ext-enable xdebug) || true)

# Prepare IIPImage log file
RUN touch /var/log/iipsrv.log && chown www-data:www-data /var/log/iipsrv.log

# Isolated /tmp directory for temporary files
RUN mkdir -p /var/tmp/drupal \
    && chown www-data:www-data /var/tmp/drupal
ENV TMPDIR=/var/tmp/drupal

# Configure PHP-FPM to listen on a UNIX socket
RUN mkdir -p /run/php && \
    sed -i 's|listen = 9000|listen = /run/php/php-fpm.sock|' /usr/local/etc/php-fpm.d/zz-docker.conf && \
    echo 'listen.owner = www-data' >> /usr/local/etc/php-fpm.d/zz-docker.conf && \
    echo 'listen.group = www-data' >> /usr/local/etc/php-fpm.d/zz-docker.conf && \
    echo 'listen.mode = 0660' >> /usr/local/etc/php-fpm.d/zz-docker.conf

# Create configs directory
RUN mkdir -p /var/configs

# Create private files directory
RUN mkdir -p /var/private-files

# Create composer home directory for www-data user
RUN mkdir -p /var/composer-home

# Copy Redis settings configuration
COPY config/redis/redis.settings.php /var/configs/redis.settings.php

# Install drush
RUN composer require 'drush/drush:^13.7'

# add composer bin to PATH
RUN ln -s /opt/drupal/vendor/bin/drush /usr/local/bin/drush

# Set Composer home directory
ENV COMPOSER_HOME=/var/composer-home

# Set www-data user to use bash
RUN usermod -s /bin/bash www-data

# Configure Nginx
COPY config/nginx/nginx.conf /etc/nginx/nginx.conf
COPY config/nginx/drupal.conf /etc/nginx/conf.d/drupal.conf
RUN mkdir -p /etc/nginx/snippets
COPY config/iipsrv/iipsrv.nginx.conf /etc/nginx/snippets/iipsrv.conf
RUN rm -f /etc/nginx/conf.d/default.conf && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log && \
    mkdir -p /run/nginx

RUN if [ "$MODE" = "production" ]; then \
    sed -i 's|access_log /var/log/nginx/access.log main;|access_log off;|' /etc/nginx/nginx.conf && \
    sed -i 's|error_log /var/log/nginx/error.log warn;|error_log off;|' /etc/nginx/nginx.conf; \
    fi

# Add permission scripts and set initial ownerships and permissions
COPY config/drupal/set-permissions.sh /usr/local/bin/set-permissions.sh
RUN chmod +x /usr/local/bin/set-permissions.sh
RUN /usr/local/bin/set-permissions.sh


# Add entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx","-g","daemon off;"]

