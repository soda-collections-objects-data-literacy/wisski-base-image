# Pin the Drupal base image tag deliberately when upgrading core.
ARG DRUPAL_BASE_IMAGE_TAG=11.3-php8.3-fpm-bookworm

# -----------------------------------------------------------------------------
# Builder: compile PHP extensions and iipsrv; toolchain stays in this stage.
# -----------------------------------------------------------------------------
FROM drupal:${DRUPAL_BASE_IMAGE_TAG} AS builder

ARG MODE=production
ARG IIPSRV_VERSION=iipsrv-1.3

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    git \
    libaom3 \
    libavif-dev \
    libavif15 \
    libbrotli-dev \
    libdav1d6 \
    libfreetype6-dev \
    libgmp-dev \
    libjpeg-dev \
    libjpeg62-turbo \
    libmemcached-dev \
    libonig-dev \
    libpng-dev \
    libpng16-16 \
    libpq-dev \
    libtiff-dev \
    libtool \
    libvips-dev \
    libwebp-dev \
    libzip-dev \
    unzip \
    wget; \
    rm -rf /var/lib/apt/lists/*

# Install apcu (enabled at runtime via zz-apcu-custom.ini).
RUN set -eux; \
    pecl install apcu

# Configure and install GD extension with AVIF support.
RUN docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
    --with-webp \
    --with-avif \
    && docker-php-ext-install -j"$(nproc)" gd

# Install intl.
RUN set -eux; \
    docker-php-ext-configure intl \
    && docker-php-ext-install intl

# Upload progress.
RUN set -eux; \
    git clone https://github.com/php/pecl-php-uploadprogress/ /usr/src/php/ext/uploadprogress/; \
    docker-php-ext-configure uploadprogress; \
    docker-php-ext-install uploadprogress; \
    rm -rf /usr/src/php/ext/uploadprogress

# Redis.
RUN set -eux; \
    pecl install redis-6.1.0; \
    docker-php-ext-enable redis

# xdebug (development mode only).
RUN set -eux; \
    if [ "$MODE" = "development" ]; then \
    pecl install xdebug-3.4.3; \
    docker-php-ext-enable xdebug; \
    fi

# iipsrv 1.3: AVIF, WebP, and memcached support are detected at configure time.
# See https://iipimage.sourceforge.io/2025/05/iipsrv-1-3.
RUN set -eux; \
    git clone --depth 1 --branch "${IIPSRV_VERSION}" https://github.com/ruven/iipsrv.git; \
    cd iipsrv; \
    ./autogen.sh; \
    ./configure; \
    make; \
    make check; \
    install -d /fcgi-bin; \
    install -m 755 src/iipsrv.fcgi /fcgi-bin/iipsrv.fcgi; \
    cd /; \
    rm -rf /iipsrv

# -----------------------------------------------------------------------------
# Runtime: lean image with runtime libraries and compiled artifacts only.
# -----------------------------------------------------------------------------
FROM drupal:${DRUPAL_BASE_IMAGE_TAG}

ARG MODE=production
# Production: semver manifest path (wisski_base/production/<version>) with lock file.
ARG WISSKI_PACKAGES_VERSION=3.3.2
# Development: major-line manifest path (wisski_base/development/<line>), no lock file.
ARG WISSKI_PACKAGES_LINE=3.x

# Runtime packages only (no autoconf, lib*-dev, or other build toolchain).
# iipsrv, Redis, and the triplestore run in separate processes/containers.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    curl \
    default-mysql-client \
    fuse3 \
    git \
    imagemagick \
    libaom3 \
    libavif15 \
    libdav1d6 \
    libfreetype6 \
    libgmp10 \
    libjpeg62-turbo \
    libmemcached11 \
    libonig5 \
    libpng16-16 \
    libpq5 \
    libtiff6 \
    libvips-tools \
    libwebp7 \
    libwebpmux3 \
    libzip4 \
    memcached \
    netcat-openbsd \
    nginx \
    rclone \
    rsync \
    sendmail \
    tini \
    unzip \
    vim \
    wget; \
    rm -rf /var/lib/apt/lists/*

# Copy compiled PHP extensions and enablement snippets from the builder.
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-*.ini /usr/local/etc/php/conf.d/

# Copy the iipsrv binary.
COPY --from=builder /fcgi-bin/iipsrv.fcgi /fcgi-bin/iipsrv.fcgi
RUN chown www-data:www-data /fcgi-bin/iipsrv.fcgi

# Add php configs.
# Cron + Drush tasks should NOT use APCu → causes stale caches during deployments.
COPY config/apcu/zz-apcu-custom.ini /usr/local/etc/php/conf.d/zz-apcu-custom.ini

# Redis configuration.
# Note: extension is already enabled by docker-php-ext-enable above.
# Wait 5 seconds before retrying to acquire the lock (wait forever can freeze ajax).
COPY config/redis/zz-redis-custom.ini /usr/local/etc/php/conf.d/zz-redis-custom.ini

# set memory settings for WissKI.
COPY config/wisski/zz-wisski-recommended.ini /usr/local/etc/php/conf.d/zz-wisski-recommended.ini

# Disable deprecated assert.* directives (PHP 8.4+).
COPY config/assert/zz-assert-disable.ini /usr/local/etc/php/conf.d/zz-assert-disable.ini

# Enable output buffering.
COPY config/drupal/zz-drupal-recommended.ini /usr/local/etc/php/conf.d/zz-drupal-recommended.ini

# Copy config files to temp location for conditional copying.
COPY config/ /tmp/config/

# Configure opcache.
# see https://secure.php.net/manual/en/opcache.installation.php
RUN set -eux; \
    if [ "$MODE" = "development" ]; then \
    cp /tmp/config/opcache/zz-opcache-recommended-dev.ini /usr/local/etc/php/conf.d/zz-opcache-recommended.ini; \
    cp /tmp/config/xdebug/zz-xdebug.ini /usr/local/etc/php/conf.d/zz-xdebug.ini; \
    else \
    cp /tmp/config/opcache/zz-opcache-recommended-prod.ini /usr/local/etc/php/conf.d/zz-opcache-recommended.ini; \
    fi; \
    rm -rf /tmp/config

# Configure mysqli.
# see https://secure.php.net/manual/en/opcache.installation.php
COPY config/mysqli/zz-mysqli-recommended.ini /usr/local/etc/php/conf.d/zz-mysqli-recommended.ini

# Configure session.
COPY config/session/zz-session-recommended.ini /usr/local/etc/php/conf.d/zz-session-recommended.ini

# Prepare IIPImage and xdebug log files.
RUN set -eux; \
    touch /var/log/iipsrv.log; \
    chown www-data:www-data /var/log/iipsrv.log; \
    mkdir -p /var/log/xdebug; \
    chown www-data:www-data /var/log/xdebug

# Isolated /tmp directory for temporary files.
RUN mkdir -p /var/tmp/drupal \
    && chown www-data:www-data /var/tmp/drupal
ENV TMPDIR=/var/tmp/drupal

# Configure PHP-FPM to listen on a UNIX socket.
RUN mkdir -p /run/php && \
    sed -i 's|listen = 9000|listen = /run/php/php-fpm.sock|' /usr/local/etc/php-fpm.d/zz-docker.conf && \
    echo 'listen.owner = www-data' >> /usr/local/etc/php-fpm.d/zz-docker.conf && \
    echo 'listen.group = www-data' >> /usr/local/etc/php-fpm.d/zz-docker.conf && \
    echo 'listen.mode = 0660' >> /usr/local/etc/php-fpm.d/zz-docker.conf

# Create configs and Composer home directories,
# writable by the runtime user (single layer to avoid image bloat).
RUN set -eux; \
    mkdir -p /var/configs /var/composer-home /fcgi-bin; \
    chown -R www-data:www-data /var/configs /var/composer-home; \
    chmod -R 775 /var/configs /var/composer-home

# Disable Git "dubious ownership" checks inside the container.
RUN git config --system --add safe.directory '*'

# Copy Redis settings configuration.
COPY config/redis/redis.settings.php /var/configs/redis.settings.php

# Bake the whole Drupal codebase (core, modules, recipes, drush) from the
# composer manifest in the drupal_packages repo. Production uses a pinned
# lock file; development resolves the latest compatible packages at build time.
# The codebase is immutable at runtime; no composer calls happen in the entrypoint.
RUN set -eux; \
    rm -rf /opt/drupal; \
    mkdir -p /opt/drupal; \
    cd /opt/drupal; \
    packagesRepoBaseUrl="https://raw.githubusercontent.com/soda-collections-objects-data-literacy/drupal_packages/main/wisski_base"; \
    if [ "$MODE" = "development" ]; then \
    manifestBaseUrl="${packagesRepoBaseUrl}/development/${WISSKI_PACKAGES_LINE}"; \
    curl -fsSL "${manifestBaseUrl}/composer.json" -o composer.json; \
    composer update --no-dev --no-interaction --no-progress --optimize-autoloader; \
    packagesVersion="${WISSKI_PACKAGES_LINE}-$(md5sum vendor/composer/installed.json | cut -d' ' -f1)"; \
    else \
    manifestBaseUrl="${packagesRepoBaseUrl}/production/${WISSKI_PACKAGES_VERSION}"; \
    curl -fsSL "${manifestBaseUrl}/composer.json" -o composer.json; \
    curl -fsSL "${manifestBaseUrl}/composer.lock" -o composer.lock; \
    composer install --no-dev --no-interaction --no-progress --optimize-autoloader; \
    packagesVersion="${WISSKI_PACKAGES_VERSION}"; \
    fi; \
    composer clear-cache; \
    ln -sf /opt/drupal/vendor/bin/drush /usr/local/bin/drush; \
    ln -sfn /opt/drupal/web /var/www/html; \
    echo "${packagesVersion}" > /opt/drupal/.wisski-packages-version; \
    chown -R www-data:www-data /opt/drupal

# JS libraries for WissKI and DLF AIM 3D Viewer (mirrors drush download commands).
RUN set -eux; \
    curl -fsSL "https://github.com/rnsrk/wisski-mirador-integration/archive/main.zip" -o /tmp/wisski-mirador-integration.zip; \
    mkdir -p /opt/drupal/web/libraries/wisski-mirador-integration; \
    unzip -qo /tmp/wisski-mirador-integration.zip -d /tmp; \
    cp -a /tmp/wisski-mirador-integration-main/. /opt/drupal/web/libraries/wisski-mirador-integration/; \
    rm -rf /tmp/wisski-mirador-integration.zip /tmp/wisski-mirador-integration-main; \
    curl -fsSL "https://github.com/jackmoore/colorbox/archive/master.zip" -o /tmp/colorbox.zip; \
    mkdir -p /opt/drupal/web/libraries/colorbox; \
    unzip -qo /tmp/colorbox.zip -d /tmp; \
    cp -a /tmp/colorbox-master/. /opt/drupal/web/libraries/colorbox/; \
    rm -rf /tmp/colorbox.zip /tmp/colorbox-master; \
    curl -fsSL "https://github.com/cure53/DOMPurify/archive/main.zip" -o /tmp/dompurify.zip; \
    mkdir -p /opt/drupal/web/libraries/dompurify; \
    unzip -qo /tmp/dompurify.zip -d /tmp; \
    cp -a /tmp/DOMPurify-main/dist /opt/drupal/web/libraries/dompurify/; \
    rm -rf /tmp/dompurify.zip /tmp/DOMPurify-main; \
    curl -fsSL "https://github.com/thedworak/dfg_3dviewer/archive/standalone.zip" -o /tmp/dlf_aim_3d_viewer.zip; \
    mkdir -p /opt/drupal/web/libraries/dlf_aim_3d_viewer; \
    unzip -qo /tmp/dlf_aim_3d_viewer.zip -d /tmp; \
    cp -a /tmp/dfg_3dviewer-standalone/. /opt/drupal/web/libraries/dlf_aim_3d_viewer/; \
    rm -rf /tmp/dlf_aim_3d_viewer.zip /tmp/dfg_3dviewer-standalone; \
    chown -R www-data:www-data /opt/drupal/web/libraries

# Bake static file permissions for the immutable codebase, following Drupal
# security guidelines (directories 755, files 644). The codebase never changes
# at runtime, so doing this once at build time avoids a slow recursive walk over
# vendor/ on first boot. Runtime only adjusts the writable state directories and
# locks down the generated settings files (see set-permissions.sh).
RUN set -eux; \
    find /opt/drupal -type d -exec chmod 755 {} +; \
    find /opt/drupal -type f -exec chmod 644 {} +; \
    if [ -d /opt/drupal/vendor/bin ]; then \
    find /opt/drupal/vendor/bin -type f -exec chmod 755 {} +; \
    fi; \
    find /opt/drupal/vendor -type f -print0 | xargs -0 grep -l -m1 '^#!' 2>/dev/null | xargs -r chmod 755; \
    find /opt/drupal/web -name .htaccess -exec chmod 444 {} +; \
    if [ -f /opt/drupal/web/robots.txt ]; then chmod 444 /opt/drupal/web/robots.txt; fi

# Persistent private files live outside the web root (mounted as a volume).
RUN set -eux; \
    mkdir -p /opt/drupal/private-files; \
    chown www-data:www-data /opt/drupal/private-files; \
    chmod 775 /opt/drupal/private-files

LABEL org.wisski.packages.version="${WISSKI_PACKAGES_VERSION}" \
    org.wisski.packages.line="${WISSKI_PACKAGES_LINE}"

# Set Composer home directory.
ENV COMPOSER_HOME=/var/composer-home

# Pre-create Composer cache dirs for www-data. Runtime exec (e.g. composer show
# --latest via docker exec as www-data) needs a writable cache; root-owned cache
# appears if anything runs Composer as root with COMPOSER_HOME set.
RUN set -eux; \
    mkdir -p /var/composer-home/cache/vcs /var/composer-home/cache/repo; \
    chown -R www-data:www-data /var/composer-home; \
    chmod -R 775 /var/composer-home

# Set www-data user to use bash.
RUN usermod -s /bin/bash www-data

# Configure Nginx.
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

# Add permission scripts and set initial ownerships and permissions.
COPY config/drupal/set-permissions.sh /usr/local/bin/set-permissions.sh
COPY config/drupal/sync-reverse-proxy.sh /usr/local/bin/sync-reverse-proxy.sh
COPY config/drupal/lib/reverse-proxy.py /usr/local/lib/wisski/reverse-proxy.py
RUN chmod +x /usr/local/bin/set-permissions.sh /usr/local/bin/sync-reverse-proxy.sh /usr/local/lib/wisski/reverse-proxy.py

# Add entrypoint.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

STOPSIGNAL SIGTERM

# Health check via the health_check module endpoint.
# Long start period: the first boot installs and configures the whole site.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30m --retries=3 \
    CMD curl -fsS http://localhost/health || exit 1

# Use tini as PID 1 for signal forwarding and zombie reaping.
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["nginx","-g","daemon off;"]
