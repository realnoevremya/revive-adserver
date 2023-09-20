FROM php:8.2.4-fpm

WORKDIR /var/www/adserver_550

EXPOSE 80

#RUN apk --update upgrade && apk update && apk add curl ca-certificates && update-ca-certificates --fresh && apk add openssl
RUN apt update && apt install -y zip gzip nginx curl openssl wget

RUN wget -qO- https://download.revive-adserver.com/revive-adserver-5.5.0.tar.gz | tar xz --strip 1 \
    && chown -R www-data:www-data . \
    && rm -rf /var/cache/apk/*

COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/old_revive/adserver_500/ /var/www/adserver_500/
COPY docker/old_revive/adserver_500/live/var/bs.realnoevremya.ru.conf.php /var/www/adserver_550/var/bs.realnoevremya.ru.conf.php
COPY docker/old_revive/adserver_500/live/var/default.conf.php /var/www/adserver_550/var/default.conf.php
COPY docker_old_revive/adserver_500/live/www/admin/assets/images/rvlogo.png /var/www/adserver_550/www/admin/assets/images/rvlogo.png


# Easy installation of PHP extensions in official PHP Docker images
# @see https://github.com/mlocati/docker-php-extension-installer
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

# Install PHP extensions
RUN install-php-extensions pdo_mysql mysqli opcache zip


# Start services
CMD service nginx start && php-fpm
