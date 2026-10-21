# Pin the PHP base image tag deliberately when upgrading PHP.
# The Drupal codebase itself is baked from the drupal_packages composer
# manifest below, so no drupal:* base image is needed.
ARG PHP_BASE_IMAGE_TAG=8.5-fpm-bookworm

# Single defaults for every stage. An ARG is scoped to the stage that declares
# it, so each stage below repeats the name without a value and inherits this
# default (or a --build-arg). A value on the stage declaration would shadow it.
ARG MODE=production
# Production: semver manifest path (wisski_base/production/<version>) with lock file.
ARG WISSKI_PACKAGES_VERSION=4.5.0
# Development: major-line manifest path (wisski_base/development/<line>), no lock file.
ARG WISSKI_PACKAGES_LINE=4.x

# Versions
ARG IIPSRV_VERSION=iipsrv-1.3
ARG REDIS_VERSION=6.3.0
ARG UPLOADPROGRESS_VERSION=2.0.5
ARG XDEBUG_VERSION=3.5.3

# -----------------------------------------------------------------------------
# ext-builder: compile PHP extensions; toolchain stays in this stage.
# -----------------------------------------------------------------------------
FROM php:${PHP_BASE_IMAGE_TAG} AS ext-builder

ARG MODE
ARG REDIS_VERSION
ARG UPLOADPROGRESS_VERSION
ARG XDEBUG_VERSION

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
    libicu-dev \
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

# Drupal database drivers and zip (shipped by the drupal base image before;
# must be built explicitly on the plain php base).
RUN set -eux; \
    docker-php-ext-install -j"$(nproc)" pdo_mysql pdo_pgsql zip

# Opcache: enabled by default in current official php images; guard for older tags.
RUN docker-php-ext-enable opcache || true

# Upload progress.
RUN set -eux; \
    git clone https://github.com/php/pecl-php-uploadprogress/ /usr/src/php/ext/uploadprogress/; \
    docker-php-ext-configure uploadprogress; \
    docker-php-ext-install uploadprogress; \
    rm -rf /usr/src/php/ext/uploadprogress

# Redis.
RUN set -eux; \
    pecl install redis-${REDIS_VERSION}; \
    docker-php-ext-enable redis

# xdebug (development mode only).
RUN set -eux; \
    if [ "$MODE" = "development" ]; then \
    pecl install xdebug-${XDEBUG_VERSION}; \
    docker-php-ext-enable xdebug; \
    fi

# -----------------------------------------------------------------------------
# iipsrv-builder: compile iipsrv; independent of PHP so BuildKit runs it in
# parallel with the extension builds. Same apt list as ext-builder so the
# configure-time feature detection (AVIF, WebP, memcached) stays identical.
# -----------------------------------------------------------------------------
FROM php:${PHP_BASE_IMAGE_TAG} AS iipsrv-builder

ARG IIPSRV_VERSION

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
    libjpeg-dev \
    libjpeg62-turbo \
    libmemcached-dev \
    libpng-dev \
    libpng16-16 \
    libtiff-dev \
    libtool \
    libwebp-dev; \
    rm -rf /var/lib/apt/lists/*

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
# codebase: bake the whole Drupal codebase as www-data. Because composer and
# the library downloads run as the runtime user with umask 022, every file is
# born www-data:www-data with dirs 755 / files 644 — no recursive chown/chmod
# walk over vendor/ is needed anywhere.
# -----------------------------------------------------------------------------
FROM ext-builder AS codebase

ARG MODE
ARG WISSKI_PACKAGES_VERSION
ARG WISSKI_PACKAGES_LINE

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

ENV COMPOSER_HOME=/tmp/composer-home \
    COMPOSER_CACHE_DIR=/composer-cache

RUN set -eux; \
    mkdir -p /opt/drupal; \
    chown www-data:www-data /opt/drupal

USER www-data

# Bake the whole Drupal codebase (core, modules, recipes, drush) from the
# composer manifest in the drupal_packages repo. Production uses a pinned
# lock file; development resolves the latest compatible packages at build time.
# The codebase is immutable at runtime; no composer calls happen in the entrypoint.
# The composer cache lives in a BuildKit cache mount (uid 33 = www-data) and
# never enters the image layer.
RUN --mount=type=cache,target=/composer-cache,uid=33,gid=33 \
    set -eux; \
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
    echo "${packagesVersion}" > /opt/drupal/.wisski-packages-version

# JS libraries for WissKI and DLF AIM 3D Viewer (mirrors drush download commands).
# wisski-mirador-integration is already built in the rnsrk repo
# (mirador-integration.js / .css, Mirador 4). This image only downloads that
# release; it does not run npm. The pin and checksum live in MiradorLibrary.php.
# Older WissKI builds have no pin and keep the main-branch archive. Copies drop
# archive ownership, and the perms fixup is scoped to web/libraries only.
# dfg_3dviewer keeps only dist/drupal; the module loads dist/drupal/main.
# Heredoc, not a continued RUN: a shell function at the start of a
# continued line is parsed as a Dockerfile instruction ("Unknown instruction: FETCH").
RUN <<'EOS'
set -eux
fetch() { curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors "$1" -o "$2"; }
libs=/opt/drupal/web/libraries
miradorLibrary="/opt/drupal/web/modules/contrib/wisski/wisski_mirador/src/MiradorLibrary.php"
if [ -f "${miradorLibrary}" ]; then
  miradorVersion="$(grep -E "const VERSION = '" "${miradorLibrary}" | head -n1 | cut -d "'" -f2)"
  miradorSha="$(grep -E "const ARCHIVE_SHA256 = '" "${miradorLibrary}" | head -n1 | cut -d "'" -f2)"
  test -n "${miradorVersion}"
  test -n "${miradorSha}"
  fetch "https://github.com/rnsrk/wisski-mirador-integration/archive/refs/tags/v${miradorVersion}.zip" /tmp/wisski-mirador-integration.zip
  echo "${miradorSha}  /tmp/wisski-mirador-integration.zip" | sha256sum -c -
  unzip -qo /tmp/wisski-mirador-integration.zip -d /tmp
  mkdir -p "${libs}/wisski-mirador-integration"
  cp -a --no-preserve=ownership "/tmp/wisski-mirador-integration-${miradorVersion}/." "${libs}/wisski-mirador-integration/"
  rm -f "${libs}/wisski-mirador-integration/"*.map
  rm -rf /tmp/wisski-mirador-integration.zip "/tmp/wisski-mirador-integration-${miradorVersion}"
else
  fetch "https://github.com/rnsrk/wisski-mirador-integration/archive/main.zip" /tmp/wisski-mirador-integration.zip
  mkdir -p "${libs}/wisski-mirador-integration"
  unzip -qo /tmp/wisski-mirador-integration.zip -d /tmp
  cp -a --no-preserve=ownership /tmp/wisski-mirador-integration-main/. "${libs}/wisski-mirador-integration/"
  rm -rf /tmp/wisski-mirador-integration.zip /tmp/wisski-mirador-integration-main
fi
fetch "https://github.com/TurbojetTechnologies/colorbox/archive/1.7.0.zip" /tmp/colorbox.zip
mkdir -p "${libs}/colorbox"
unzip -qo /tmp/colorbox.zip -d /tmp
cp -a --no-preserve=ownership /tmp/colorbox-1.7.0/. "${libs}/colorbox/"
rm -rf /tmp/colorbox.zip /tmp/colorbox-1.7.0
fetch "https://github.com/cure53/DOMPurify/archive/main.zip" /tmp/dompurify.zip
mkdir -p "${libs}/dompurify"
unzip -qo /tmp/dompurify.zip -d /tmp
cp -a --no-preserve=ownership /tmp/DOMPurify-main/dist "${libs}/dompurify/"
rm -rf /tmp/dompurify.zip /tmp/DOMPurify-main
fetch "https://github.com/thedworak/dfg_3dviewer/archive/main.zip" /tmp/dlf_aim_3d_viewer.zip
mkdir -p "${libs}/dlf_aim_3d_viewer"
unzip -qo /tmp/dlf_aim_3d_viewer.zip -d /tmp
cp -a --no-preserve=ownership /tmp/dfg_3dviewer-main/. "${libs}/dlf_aim_3d_viewer/"
rm -rf "${libs}/dlf_aim_3d_viewer/dist/dev" "${libs}/dlf_aim_3d_viewer/dist/prod" "${libs}/dlf_aim_3d_viewer/dist/test"
rm -rf /tmp/dlf_aim_3d_viewer.zip /tmp/dfg_3dviewer-main
find "${libs}" -type d -exec chmod 755 {} +
find "${libs}" -type f -exec chmod 644 {} +
EOS

# Targeted read-only bits, following Drupal security guidelines. The rest of
# the tree already has dirs 755 / files 644 by construction (umask 022), and
# composer preserves the executable bits on vendor/bin.
RUN set -eux; \
    find /opt/drupal/web -name .htaccess -exec chmod 444 {} +; \
    if [ -f /opt/drupal/web/robots.txt ]; then chmod 444 /opt/drupal/web/robots.txt; fi

# Persistent private files live outside the web root (mounted as a volume).
RUN set -eux; \
    mkdir -p /opt/drupal/private-files; \
    chmod 775 /opt/drupal/private-files

# -----------------------------------------------------------------------------
# Runtime: lean image with runtime libraries and compiled artifacts only.
# -----------------------------------------------------------------------------
FROM php:${PHP_BASE_IMAGE_TAG}

ARG MODE
ARG WISSKI_PACKAGES_VERSION
ARG WISSKI_PACKAGES_LINE

# Runtime packages only (no autoconf, lib*-dev, or other build toolchain).
# iipsrv, Redis, and the triplestore run in separate processes/containers.
# iproute2 (ip) and python3 are required by sync-reverse-proxy.sh;
# libicu72 is required by the intl extension.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    curl \
    default-mysql-client \
    git \
    imagemagick \
    iproute2 \
    libaom3 \
    libavif15 \
    libdav1d6 \
    libfreetype6 \
    libgmp10 \
    libicu72 \
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
    python3 \
    rclone \
    rsync \
    sendmail \
    tini \
    unzip \
    vim \
    wget; \
    rm -rf /var/lib/apt/lists/*

# Copy compiled PHP extensions and enablement snippets from the builder.
COPY --from=ext-builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=ext-builder /usr/local/etc/php/conf.d/docker-php-ext-*.ini /usr/local/etc/php/conf.d/

# Composer binary (entrypoint composer calls and docker-exec package checks).
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
ENV COMPOSER_ALLOW_SUPERUSER=1

# Copy the iipsrv binary.
COPY --from=iipsrv-builder /fcgi-bin/iipsrv.fcgi /fcgi-bin/iipsrv.fcgi
RUN chown www-data:www-data /fcgi-bin/iipsrv.fcgi

# Add php configs.
# Cron + Drush tasks should NOT use APCu → causes stale caches during deployments.
COPY config/apcu/zz-apcu-custom.ini /usr/local/etc/php/conf.d/zz-apcu-custom.ini

# Redis sessions: store PHP sessions in Redis with bounded lock retries
# (see comments in the ini). The extension itself is enabled by the
# docker-php-ext-enable snippet copied from ext-builder.
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

# Configure session.
COPY config/session/zz-session-recommended.ini /usr/local/etc/php/conf.d/zz-session-recommended.ini

# Prepare IIPImage and xdebug log files. The xdebug log is pre-created
# www-data-owned and group-writable: the root-run php-fpm master would
# otherwise create it root:root 644 on startup, and the www-data workers
# could no longer append to it.
RUN set -eux; \
    touch /var/log/iipsrv.log; \
    chown www-data:www-data /var/log/iipsrv.log; \
    mkdir -p /var/log/xdebug; \
    touch /var/log/xdebug/xdebug.log; \
    chown -R www-data:www-data /var/log/xdebug; \
    chmod 775 /var/log/xdebug; \
    chmod 664 /var/log/xdebug/xdebug.log

# Isolated /tmp directory for temporary files.
RUN mkdir -p /var/tmp/drupal \
    && chown www-data:www-data /var/tmp/drupal
ENV TMPDIR=/var/tmp/drupal

# Configure PHP-FPM to listen on a UNIX socket. A dedicated override file is
# used instead of editing the base image's conf (the location of the default
# `listen = 9000` directive moved between php image releases); zzz-* sorts
# last in the php-fpm.d include glob, so these directives always win.
COPY config/php-fpm/zzz-wisski-socket.conf /usr/local/etc/php-fpm.d/zzz-wisski-socket.conf
RUN mkdir -p /run/php

# Raise max_children for concurrent WissKI entity views (default pool is 5).
# Applies to both modes so development/staging matches production concurrency.
COPY config/php-fpm/zz-wisski-pool.conf /usr/local/etc/php-fpm.d/zz-wisski-pool.conf

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

# The Drupal codebase is baked in the codebase stage as www-data with correct
# modes by construction; ownership and permissions are preserved by the copy,
# so /opt/drupal lands in the image in a single layer with zero chown/chmod.
COPY --from=codebase /opt/drupal /opt/drupal

# COPY --from preserves ownership of the contents but creates the destination
# directory itself as root; fix the single top-level directory (non-recursive,
# needed for entrypoint composer.json/lock writes). /var/www is www-data's
# home directory: unprivileged drush/composer calls need it writable for
# their dot-directories (also non-recursive, nearly empty).
RUN set -eux; \
    chown www-data:www-data /opt/drupal; \
    ln -sf /opt/drupal/vendor/bin/drush /usr/local/bin/drush; \
    rm -rf /var/www/html; \
    ln -sfn /opt/drupal/web /var/www/html; \
    chown www-data:www-data /var/www

WORKDIR /opt/drupal

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

# Sanity check: fail the build (not the container) if an extension or one of
# its shared-library dependencies is missing on the plain php base image.
RUN set -eux; \
    php -r 'foreach (["apcu", "gd", "intl", "pdo_mysql", "pdo_pgsql", "redis", "uploadprogress", "zip", "Zend OPcache"] as $ext) { if (!extension_loaded($ext)) { fwrite(STDERR, "MISSING PHP EXTENSION: {$ext}\n"); exit(1); } }'; \
    extDir="$(php -r 'echo ini_get("extension_dir");')"; \
    ! ldd "$extDir"/*.so | grep 'not found'

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

# Health check via the health_check module endpoint. The Host header must
# match the trusted host patterns, otherwise Drupal answers 400 (compose
# deployments pass DRUPAL_DOMAIN; standalone runs fall back to localhost).
# Long start period: the first boot installs and configures the whole site.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30m --retries=3 \
    CMD curl -fsS -H "Host: ${DRUPAL_DOMAIN:-localhost}" http://localhost/health || exit 1

# Use tini as PID 1 for signal forwarding and zombie reaping.
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["nginx","-g","daemon off;"]
