FROM drupal:11.0.5-php8.3-apache-bookworm

LABEL org.opencontainers.image.source=https://github.com/soda-collections-objects-data-literacy/wisski-base-image.git
LABEL org.opencontainers.image.description="Plain Drupal with preinstalled Site and basic WissKI environment with only core components with connection to triplestore provided by env variables."

# Install apts

RUN apt-get update; \
    apt-get install -y --no-install-recommends \
    default-mysql-client \
    git \
    unzip \
    vim \
    wget

# Upload progress
RUN	set -eux; \
    git clone https://github.com/php/pecl-php-uploadprogress/ /usr/src/php/ext/uploadprogress/; \
    docker-php-ext-configure uploadprogress; \
    docker-php-ext-install uploadprogress; \
    rm -rf /usr/src/php/ext/uploadprogress;

# Install apcu
RUN set -eux; \
    pecl install apcu;

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

RUN chown -R www-data:www-data /var/www/html

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
