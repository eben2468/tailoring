#!/bin/sh
# Dev entrypoint: the backend is bind-mounted from the host (on Windows, Docker Desktop shows it as
# root-owned 755), so make Laravel's writable folders writable for php-fpm's www-data user on every start.
set -e
cd /var/www/backend
if [ -d storage ]; then
    mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs bootstrap/cache
    chmod -R a+rwX storage bootstrap/cache
fi
exec "$@"
