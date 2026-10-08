# PHP 8.3 FPM for the Nutɔfe Laravel API (development image; production installs --no-dev and caches config/routes)
FROM php:8.3-fpm-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends git unzip \
 && docker-php-ext-install pdo_mysql opcache pcntl \
 && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY php.ini /usr/local/etc/php/conf.d/zz-nutofe.ini
COPY entrypoint.sh /usr/local/bin/nutofe-entrypoint
RUN sed -i 's/\r$//' /usr/local/bin/nutofe-entrypoint && chmod +x /usr/local/bin/nutofe-entrypoint

WORKDIR /var/www/backend
ENTRYPOINT ["nutofe-entrypoint"]
CMD ["php-fpm"]
