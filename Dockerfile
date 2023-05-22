FROM php:8.1-fpm

WORKDIR /var/www/html

EXPOSE 80

#RUN apk --update upgrade && apk update && apk add curl ca-certificates && update-ca-certificates --fresh && apk add openssl
RUN apt update && apt install -y zip gzip nginx curl openssl wget

RUN wget -qO- https://download.revive-adserver.com/revive-adserver-5.4.1.tar.gz | tar xz --strip 1 \
    && chown -R www-data:www-data . \
    && rm -rf /var/cache/apk/*

COPY docker/nginx.conf /etc/nginx/nginx.conf


# Easy installation of PHP extensions in official PHP Docker images
# @see https://github.com/mlocati/docker-php-extension-installer
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

# Install PHP extensions
RUN install-php-extensions pdo_mysql mysqli opcache zip


# Start services
CMD service nginx start && php-fpm
