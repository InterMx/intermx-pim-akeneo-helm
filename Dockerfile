FROM ubuntu:18.04 AS php-builder

MAINTAINER Intermx

RUN apt-get update && apt-get install -y apt-transport-https

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y git wget zip \
    && wget https://getcomposer.org/composer.phar -O /usr/local/bin/composer \
    && chmod +x /usr/local/bin/composer

RUN DEBIAN_FRONTEND=noninteractive apt-get install php7.2 -y

RUN apt-get install php7.2-cli php7.2-apcu php7.2-bcmath php7.2-curl php7.2-fpm php7.2-gd php7.2-intl php7.2-mysql php7.2-xml php7.2-zip php7.2-zip php7.2-mbstring php7.2-imagick php7.2-exif -y

WORKDIR /app

RUN php -d memory_limit=4G /usr/local/bin/composer create-project --prefer-dist akeneo/pim-community-standard . "3.0.*@stable" \
    && rm -rf /app/var/*

COPY parameters.yml /app/app/config/parameters.yml

# NodeJS
FROM node:10 AS js-builder

WORKDIR /app

COPY --from=php-builder /app /app

RUN yarn install && yarn run webpack && rm -rf node_modules

# PHP Apache server
FROM php:7.2-apache AS apache-builder

COPY --from=js-builder /app /app

COPY pim-init-db.sh /usr/local/bin/pim-init-db.sh

ENV APACHE_RUN_USER docker

COPY wait-for-it.sh /usr/local/bin/wait-for-it.sh

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        git wget zip zlib1g-dev libicu-dev libpng-dev libfreetype6-dev libjpeg62-turbo-dev libmagickwand-dev cron vim supervisor \
    && wget https://getcomposer.org/composer.phar -O /usr/local/bin/composer \
    && chmod +x /usr/local/bin/composer \
    && docker-php-ext-install pdo pdo_mysql opcache zip bcmath exif \
    && pecl install imagick \
    && docker-php-ext-enable imagick \
    && pecl install apcu \
    && docker-php-ext-enable apcu \
    && docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-configure intl \
    && docker-php-ext-install intl \
    && a2enmod rewrite \
    && sed -i 's/Listen 80$/Listen 80/g' /etc/apache2/ports.conf \
    && chmod +x /usr/local/bin/wait-for-it.sh \
    && chmod +x /usr/local/bin/pim-init-db.sh

COPY php.ini /usr/local/etc/php/conf.d/custom.ini

RUN useradd -s /bin/bash -d /home/docker -m -g www-data docker \
    && mkdir -p /app \
    && chown -R docker /app \
    && chmod -R 755 /app

# Configure cron
RUN crontab -l | { cat; echo "* * * * * /usr/local/bin/php /app/bin/console akeneo:batch:job-queue-consumer-daemon --env=prod"; } | crontab -

# Configure supervisor
COPY supervisord.conf /etc/supervisor/supervisord.conf

# Enable Https
COPY ./tls/apache-selfsigned.crt /etc/ssl/certs/
COPY ./tls/apache-selfsigned.key /etc/ssl/private/
COPY ./tls/dhparam.pem /etc/ssl/certs/
COPY ./tls/ssl-params.conf /etc/apache2/conf-available/
COPY ./tls/default-ssl.conf /etc/apache2/sites-available/

RUN a2enmod rewrite \
    && a2enmod ssl \
    && a2enmod headers \
    && a2enconf ssl-params \
    && a2dissite 000-default.conf \
    && a2ensite default-ssl \
    && apache2ctl configtest

WORKDIR /app

EXPOSE 80
EXPOSE 443

CMD supervisord -c /etc/supervisor/supervisord.conf
