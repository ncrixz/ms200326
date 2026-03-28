#!/bin/sh
set -e

# Render sets PORT; default to 10000 if not provided
export PORT="${PORT:-10000}"

# Substitute $PORT into nginx config
envsubst '${PORT}' < /etc/nginx/conf.d/render.conf.template \
    > /etc/nginx/conf.d/default.conf

# Bootstrap .env from example if missing
if [ ! -f /var/www/html/.env ]; then
    echo "[entrypoint] No .env found, copying from .env.example"
    cp /var/www/html/.env.example /var/www/html/.env
fi

# Inject environment variables that Render provides
{
    echo "DB_HOST=${DB_HOST:-127.0.0.1}"
    echo "DB_PORT=${DB_PORT:-3306}"
    echo "DB_DATABASE=${DB_DATABASE:-ultimatepos}"
    echo "DB_USERNAME=${DB_USERNAME:-posuser}"
    echo "DB_PASSWORD=${DB_PASSWORD:-secret}"
    echo "REDIS_HOST=${REDIS_HOST:-127.0.0.1}"
    echo "REDIS_PORT=${REDIS_PORT:-6379}"
    echo "APP_URL=${APP_URL:-http://localhost}"
    echo "APP_ENV=${APP_ENV:-production}"
} >> /var/www/html/.env

# Generate app key if blank
if grep -q "^APP_KEY=$" /var/www/html/.env || ! grep -q "^APP_KEY=" /var/www/html/.env; then
    echo "[entrypoint] Generating application key..."
    php /var/www/html/artisan key:generate --force
fi

# Wait for MySQL
echo "[entrypoint] Waiting for MySQL at ${DB_HOST:-127.0.0.1}:${DB_PORT:-3306}..."
until php -r "
    new PDO(
        'mysql:host=${DB_HOST:-127.0.0.1};port=${DB_PORT:-3306};dbname=${DB_DATABASE:-ultimatepos}',
        '${DB_USERNAME:-posuser}',
        '${DB_PASSWORD:-secret}'
    );
" 2>/dev/null; do
    echo "[entrypoint] MySQL not ready, retrying in 3s..."
    sleep 3
done
echo "[entrypoint] MySQL is ready."

# Run migrations
echo "[entrypoint] Running migrations..."
php /var/www/html/artisan migrate --force

# Passport keys
if [ ! -f /var/www/html/storage/oauth-private.key ]; then
    echo "[entrypoint] Generating Passport keys..."
    php /var/www/html/artisan passport:keys --force || true
fi

# Production caching
if [ "${APP_ENV}" = "production" ]; then
    php /var/www/html/artisan config:cache
    php /var/www/html/artisan route:cache
    php /var/www/html/artisan view:cache
fi

# Permissions
chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache
mkdir -p /var/log/supervisor

echo "[entrypoint] Starting supervisord (nginx + php-fpm) on port ${PORT}..."
exec supervisord -c /etc/supervisor/conf.d/supervisord.conf
