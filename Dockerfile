ARG DRUPAL_VERSION=11.1.2-php8.3-apache-bookworm

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
    echo 'max_execution_time = 1200'; \
    echo 'max_input_time = 600'; \
    echo 'max_input_nesting_level = 640'; \
    echo 'max_input_vars = 10000'; \
    echo 'memory_limit = 512M'; \
    echo 'upload_max_filesize = 512M'; \
    echo 'max_file_uploads = 50'; \
    echo 'post_max_size = 512M'; \
    echo 'assert.active = 0'; \
    } >> /usr/local/etc/php/conf.d/zz-wisski-recommended.ini;

# Enable output buffering
RUN { \
    echo 'output_buffering = on'; \
    } >> /usr/local/etc/php/conf.d/zz-drupal-recommended.ini;

# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    } >> /usr/local/etc/php/conf.d/zz-opcache-recommended.ini;

# Create configs directory
RUN mkdir -p /var/configs

# Install drush
RUN composer require drush/drush

# add composer bin to PATH
RUN ln -s /opt/drupal/vendor/bin/drush /usr/local/bin/drush

# Change ownerships
RUN chown -R www-data:www-data /var/www/html

# Add entrypoint
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
