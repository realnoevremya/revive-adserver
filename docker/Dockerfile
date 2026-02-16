FROM alpine:3.20 AS downloader

ARG REVIVE_VERSION=6.0.5

RUN apk add --no-cache curl tar

WORKDIR /tmp/revive

RUN curl -fsSL "https://codeload.github.com/revive-adserver/revive-adserver/tar.gz/refs/tags/v${REVIVE_VERSION}" \
    | tar -xz --strip-components=1


FROM alpine:3.20

WORKDIR /var/www/html

RUN apk add --no-cache \
    nginx \
    php82 \
    php82-cli \
    php82-ctype \
    php82-curl \
    php82-dom \
    php82-fileinfo \
    php82-fpm \
    php82-gd \
    php82-iconv \
    php82-intl \
    php82-mbstring \
    php82-mysqli \
    php82-opcache \
    php82-openssl \
    php82-phar \
    php82-session \
    php82-simplexml \
    php82-tokenizer \
    php82-xml \
    php82-xmlreader \
    php82-xmlwriter \
    php82-zip \
    tzdata \
    && ln -sf /usr/bin/php82 /usr/bin/php

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
COPY --from=downloader /tmp/revive/ /var/www/html/

RUN COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --prefer-dist --optimize-autoloader --no-interaction \
    && rm -rf /root/.composer/cache \
    && rm -f /usr/local/bin/composer

COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker/nginx/default.conf /etc/nginx/http.d/default.conf
COPY docker/php/php.ini /etc/php82/php.ini
COPY docker/php/www.conf /etc/php82/php-fpm.d/www.conf
COPY docker/scripts/entrypoint /usr/local/bin/entrypoint
COPY docker/scripts/start /usr/local/bin/start

RUN chmod +x /usr/local/bin/entrypoint /usr/local/bin/start \
    && mkdir -p /run/nginx /run/php-fpm82 \
    && mkdir -p /var/www/html/var/cache /var/www/html/var/plugins \
    && mkdir -p /var/www/html/www/images /var/www/html/www/delivery \
    && touch /var/www/html/var/UPGRADE \
    && chown -R nginx:nginx /var/www/html /run/nginx /run/php-fpm82

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["/usr/local/bin/start"]
