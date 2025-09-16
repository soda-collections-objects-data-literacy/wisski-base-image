ARG DRUPAL_VERSION=11.2.2-php8.3-apache-bookworm

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
    iipimage-server \
    iipimage-doc \
    imagemagick \
    libapache2-mod-fcgid \
    libfreetype6-dev \
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
    openjdk-17-jdk \
    redis-server \
    unzip \
    vim \
    wget;

# Upload progress
RUN	set -eux; \
    git clone https://github.com/php/pecl-php-uploadprogress/ /usr/src/php/ext/uploadprogress/; \
    docker-php-ext-configure uploadprogress; \
    docker-php-ext-install uploadprogress; \
    rm -rf /usr/src/php/ext/uploadprogress;

# Install apcu
RUN set -eux; \
    pecl install apcu;

# Install intl
RUN set -eux; \
    docker-php-ext-configure intl \
    && docker-php-ext-install intl;

# Redis
RUN set -eux; \
    pecl install redis; \
    docker-php-ext-enable redis;

# Install iipsrv
RUN set -eux; \
    git clone https://github.com/ruven/iipsrv.git; \
    cd iipsrv; \
    ./autogen.sh; \
    ./configure; \
    make; \
    mkdir /fcgi-bin; \
    cp src/iipsrv.fcgi /fcgi-bin/iipsrv.fcgi

# Add IIPServer config
COPY iipsrv.conf /etc/apache2/mods-available/iipsrv.conf

# Add php configs
RUN { \
    echo 'extension=apcu.so'; \
    echo "apc.enable_cli=1"; \
    echo "apc.enable=1"; \
    echo "apc.shm_size=128M"; \
    } >> /usr/local/etc/php/conf.d/zz-apcu-custom.ini;

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
    echo 'zend.assertions=-1 '; \
    } >> /usr/local/etc/php/conf.d/zz-wisski-recommended.ini;

# Enable output buffering
RUN { \
    echo 'output_buffering = on'; \
    } >> /usr/local/etc/php/conf.d/zz-drupal-recommended.ini;

# see https://secure.php.net/manual/en/opcache.installation.php
ARG WITH_OPCACHE=1
RUN set -eux; \
    ([ "$WITH_OPCACHE" = "1" ] && { \
    echo 'opcache.enable=1'; \
    echo 'opcache.memory_consumption=256'; \
    echo 'opcache.interned_strings_buffer=16'; \
    echo 'opcache.max_accelerated_files=20000'; \
    echo 'opcache.validate_timestamps=1'; \
    echo 'opcache.revalidate_freq=60'; \
    echo 'opcache.save_comments=1'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_file_override=1'; \
    echo 'opcache.optimization_level=0x7FFEBFFF'; \
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

# Install drush
RUN composer require drush/drush

# add composer bin to PATH
RUN ln -s /opt/drupal/vendor/bin/drush /usr/local/bin/drush

# Change ownerships
RUN chown -R www-data:www-data /opt/drupal; \
    chown -R www-data:www-data /var/private-files; \
    chown -R www-data:www-data /var/composer-home; \
    chmod -R 775 /var/www/html; \
    chmod -R 775 /var/private-files; \
    chmod -R 775 /var/composer-home

# Set Composer home directory
ENV COMPOSER_HOME=/var/composer-home

# Set www-data user to use bash
RUN usermod -s /bin/bash www-data

# Add entrypoint
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

