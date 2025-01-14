FROM drupal:11.1.1-php8.3-apache-bookworm

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
    } >> /usr/local/etc/php/conf.d/99-apcu-custom.ini;

# Install drush
RUN composer require drush/drush

# add composer bin to PATH
RUN ln -s /opt/drupal/vendor/bin/drush /usr/local/bin/drush

# Add ConfigConfigurator
COPY ConfigConfigurator.php /opt/drupal/ConfigConfigurator.php

# Change ownerships
RUN chown -R www-data:www-data /var/www/html

# Add entrypoint
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
