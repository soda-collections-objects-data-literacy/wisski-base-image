ARG DRUPAL_VERSION=11.2.4-php8.3-apache-bookworm

FROM drupal:${DRUPAL_VERSION}

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
    libapache2-mod-fcgid \
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
    redis-server \
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
# Not yet used
#RUN set -eux; \
#    git clone https://github.com/ruven/iipsrv.git; \
#    cd iipsrv; \
#    ./autogen.sh; \
#    ./configure; \
#    make; \
#    mkdir /fcgi-bin; \
#    cp src/iipsrv.fcgi /fcgi-bin/iipsrv.fcgi

# Add IIPServer config
# COPY iipsrv.conf /etc/apache2/mods-available/iipsrv.conf

# Add php configs
RUN { \
    echo 'extension=apcu.so'; \
    echo "apc.enable_cli=1"; \
    echo "apc.enable=1"; \
    echo "apc.shm_size=256M"; \
    echo "apc.ttl=7200"; \
    echo "apc.gc_ttl=3600"; \
    echo "apc.entries_hint=4096"; \
    } >> /usr/local/etc/php/conf.d/zz-apcu-custom.ini;

# Redis configuration
# Note: extension is already enabled by docker-php-ext-enable above
RUN { \
    echo 'redis.session.locking_enabled=1'; \
    echo 'redis.session.lock_retries=-1'; \
    echo 'redis.session.lock_wait_time=10000'; \
    } >> /usr/local/etc/php/conf.d/zz-redis-custom.ini;

# set memory settings for WissKI
RUN { \
    echo 'max_execution_time = 300'; \
    echo 'max_input_time = 300'; \
    echo 'max_input_nesting_level = 64000'; \
    echo 'max_input_vars = 10000'; \
    echo 'memory_limit = 1G'; \
    echo 'upload_max_filesize = 512M'; \
    echo 'max_file_uploads = 50'; \
    echo 'post_max_size = 512M'; \
    echo 'zend.assertions=-1'; \
    } >> /usr/local/etc/php/conf.d/zz-wisski-recommended.ini;

# Disable deprecated assert.* directives (PHP 8.4+).
RUN { \
    echo '; Disable deprecated assert.* INI settings for PHP 8.4+ compatibility.'; \
    echo 'assert.active=0'; \
    echo 'assert.bail=0'; \
    echo 'assert.warning=0'; \
    echo 'error_reporting = E_ALL & ~E_DEPRECATED'; \
    } >> /usr/local/etc/php/conf.d/zz-assert-disable.ini;

# Enable output buffering
RUN { \
    echo 'output_buffering = on'; \
    } >> /usr/local/etc/php/conf.d/zz-drupal-recommended.ini;

# see https://secure.php.net/manual/en/opcache.installation.php
ARG WITH_OPCACHE=1
RUN set -eux; \
    ([ "$WITH_OPCACHE" = "1" ] && { \
    echo 'opcache.enable=1'; \
    echo 'opcache.memory_consumption=512'; \
    echo 'opcache.interned_strings_buffer=32'; \
    echo 'opcache.max_accelerated_files=30000'; \
    echo 'opcache.validate_timestamps=1'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.save_comments=1'; \
    echo 'opcache.enable_file_override=1'; \
    echo 'opcache.optimization_level=0x7FFEBFFF'; \
    echo 'opcache.max_wasted_percentage=10'; \
    echo 'opcache.use_cwd=1'; \
    echo 'opcache.huge_code_pages=1'; \
    echo 'opcache.preload_user=www-data'; \
    echo 'opcache.jit=tracing'; \
    echo 'opcache.jit_buffer_size=128M'; \
    } || { \
    echo 'opcache.enable=0'; \
    }) >> /usr/local/etc/php/conf.d/zz-opcache-recommended.ini;

# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
    echo 'mysqli.allow_persistent = On'; \
    echo 'mysqli.max_persistent = 100'; \
    echo 'mysqli.max_links = 150'; \
    } >> /usr/local/etc/php/conf.d/zz-mysqli-recommended.ini;

RUN { \
    echo 'session.gc_maxlifetime = 7200'; \
    echo 'session.gc_probability = 1'; \
    echo 'session.gc_divisor = 100'; \
    } >> /usr/local/etc/php/conf.d/zz-session-recommended.ini;

# install xdebug if enabled by build tag "WITH_XDEBUG"
ARG WITH_XDEBUG=
RUN set -eux; \
    (([ "$WITH_XDEBUG" = "1" ] && pecl install xdebug-3.4.3 && { \
    echo 'xdebug.mode=debug'; \
    echo 'xdebug.start_with_request=trigger'; \
    echo 'xdebug.client_host=127.0.0.1'; \
    echo 'xdebug.client_port=9003'; \
    echo 'xdebug.log=/var/log/xdebug.log'; \
    echo 'xdebug.idekey=VSCODE'; \
    } > /usr/local/etc/php/conf.d/zz-xdebug.ini && docker-php-ext-enable xdebug) || true)


# Create configs directory
RUN mkdir -p /var/configs

# Create private files directory
RUN mkdir -p /var/private-files

# Create composer home directory for www-data user
RUN mkdir -p /var/composer-home

# Copy Redis settings configuration
COPY redis.settings.php /var/configs/redis.settings.php

# Install drush
RUN composer require 'drush/drush:^13.7'

# add composer bin to PATH
RUN ln -s /opt/drupal/vendor/bin/drush /usr/local/bin/drush

# Set initial ownerships and permissions
# TODO: Make this more secure by using the correct permissions.
RUN chown -R www-data:www-data /opt/drupal; \
    chown -R www-data:www-data /var/private-files; \
    chown -R www-data:www-data /var/composer-home; \
    chmod -R 775 /opt/drupal; \
    chmod -R 775 /var/private-files; \
    chmod -R 775 /var/composer-home


# Set Composer home directory
ENV COMPOSER_HOME=/var/composer-home

# Set www-data user to use bash
RUN usermod -s /bin/bash www-data

# Disable Apache logging
ARG APACHE_LOGGING=false
RUN (([ "$APACHE_LOGGING" = "false" ] && { \
    echo 'ErrorLog /dev/null'; \
    echo 'CustomLog /dev/null combined'; \
    echo 'LogLevel emerg'; \
    echo 'TransferLog /dev/null'; \
    } > /etc/apache2/conf-available/disable-logs.conf && \
    a2enconf disable-logs) || true)

# Override default site configuration to disable access logs
RUN (([ "$APACHE_LOGGING" = "false" ] && sed -i 's/CustomLog.*/CustomLog \/dev\/null combined/' /etc/apache2/sites-available/000-default.conf && \
    sed -i 's/ErrorLog.*/ErrorLog \/dev\/null/' /etc/apache2/sites-available/000-default.conf) || true)

# Disable additional logging in apache2.conf
RUN (([ "$APACHE_LOGGING" = "false" ] && sed -i 's/LogLevel.*/LogLevel emerg/' /etc/apache2/apache2.conf && \
    sed -i '/ErrorLog/s/^/#/' /etc/apache2/apache2.conf && \
    sed -i '/CustomLog/s/^/#/' /etc/apache2/apache2.conf) || true)

# Enable Apache performance modules
RUN a2enmod deflate expires headers http2 brotli || true

# Add Apache performance configuration
RUN { \
    echo '<IfModule mod_deflate.c>'; \
    echo '  AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript'; \
    echo '  AddOutputFilterByType DEFLATE application/xml application/xhtml+xml application/rss+xml'; \
    echo '  AddOutputFilterByType DEFLATE application/javascript application/x-javascript'; \
    echo '  AddOutputFilterByType DEFLATE application/json'; \
    echo '  AddOutputFilterByType DEFLATE image/svg+xml'; \
    echo '  BrowserMatch ^Mozilla/4 gzip-only-text/html'; \
    echo '  BrowserMatch ^Mozilla/4\.0[678] no-gzip'; \
    echo '  BrowserMatch \bMSIE !no-gzip !gzip-only-text/html'; \
    echo '  Header append Vary User-Agent env=!dont-vary'; \
    echo '  SetEnvIfNoCase Request_URI \.(?:gif|jpe?g|png|ico|woff2?)$ no-gzip dont-vary'; \
    echo '</IfModule>'; \
    echo ''; \
    echo '<IfModule mod_expires.c>'; \
    echo '  ExpiresActive On'; \
    echo '  ExpiresDefault "access plus 1 month"'; \
    echo '  ExpiresByType text/html "access plus 0 seconds"'; \
    echo '  ExpiresByType text/css "access plus 1 year"'; \
    echo '  ExpiresByType application/javascript "access plus 1 year"'; \
    echo '  ExpiresByType application/x-javascript "access plus 1 year"'; \
    echo '  ExpiresByType text/javascript "access plus 1 year"'; \
    echo '  ExpiresByType image/gif "access plus 1 year"'; \
    echo '  ExpiresByType image/jpeg "access plus 1 year"'; \
    echo '  ExpiresByType image/png "access plus 1 year"'; \
    echo '  ExpiresByType image/svg+xml "access plus 1 year"'; \
    echo '  ExpiresByType image/x-icon "access plus 1 year"'; \
    echo '  ExpiresByType image/webp "access plus 1 year"'; \
    echo '  ExpiresByType font/woff "access plus 1 year"'; \
    echo '  ExpiresByType font/woff2 "access plus 1 year"'; \
    echo '  ExpiresByType application/font-woff "access plus 1 year"'; \
    echo '  ExpiresByType application/font-woff2 "access plus 1 year"'; \
    echo '</IfModule>'; \
    echo ''; \
    echo '<IfModule mod_headers.c>'; \
    echo '  Header set X-Content-Type-Options "nosniff"'; \
    echo '  Header set X-Frame-Options "SAMEORIGIN"'; \
    echo '  Header set X-XSS-Protection "1; mode=block"'; \
    echo '  <FilesMatch "\.(js|css|xml|gz|html|woff|woff2)$">'; \
    echo '    Header append Vary: Accept-Encoding'; \
    echo '  </FilesMatch>'; \
    echo '  <FilesMatch "\.(ico|pdf|flv|jpg|jpeg|png|gif|svg|webp|swf|mp3|mp4)$">'; \
    echo '    Header set Cache-Control "max-age=31536000, public"'; \
    echo '  </FilesMatch>'; \
    echo '  <FilesMatch "\.(css|js)$">'; \
    echo '    Header set Cache-Control "max-age=31536000, public"'; \
    echo '  </FilesMatch>'; \
    echo '</IfModule>'; \
    echo ''; \
    echo 'KeepAlive On'; \
    echo 'MaxKeepAliveRequests 100'; \
    echo 'KeepAliveTimeout 5'; \
    } > /etc/apache2/conf-available/performance.conf && \
    a2enconf performance

# Add permission scripts
COPY set-permissions.sh /usr/local/bin/set-permissions.sh
RUN chmod +x /usr/local/bin/set-permissions.sh

# Add entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]

