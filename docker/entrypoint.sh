#!/bin/sh
set -e

# Copy .env if it doesn't exist
if [ ! -f /var/www/html/.env ]; then
    echo "[entrypoint] No .env found, copying from .env.example"
    cp /var/www/html/.env.example /var/www/html/.env
fi

# Override DB/Redis host from environment (Docker service names)
sed -i "s/^DB_HOST=.*/DB_HOST=${DB_HOST:-db}/" /var/www/html/.env
sed -i "s/^REDIS_HOST=.*/REDIS_HOST=${REDIS_HOST:-redis}/" /var/www/html/.env

# Generate app key if not set
if grep -q "^APP_KEY=$" /var/www/html/.env || grep -q "^APP_KEY=\"\"" /var/www/html/.env; then
    echo "[entrypoint] Generating application key..."
    php artisan key:generate --force
fi

# Wait for MySQL to be ready
echo "[entrypoint] Waiting for MySQL..."
until php -r "new PDO('mysql:host=${DB_HOST:-db};port=${DB_PORT:-3306};dbname=${DB_DATABASE:-ultimatepos}', '${DB_USERNAME:-posuser}', '${DB_PASSWORD:-secret}');" 2>/dev/null; do
    echo "[entrypoint] MySQL not ready yet, retrying in 3s..."
    sleep 3
done
echo "[entrypoint] MySQL is ready."

# Run migrations
echo "[entrypoint] Running migrations..."
php artisan migrate --force

# Generate Passport keys if not present
if [ ! -f /var/www/html/storage/oauth-private.key ]; then
    echo "[entrypoint] Generating Passport keys..."
    php artisan passport:keys --force || true
fi

# Cache config/routes in production
if [ "${APP_ENV}" = "production" ]; then
    echo "[entrypoint] Caching config and routes..."
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
fi

# Fix permissions on storage
chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

exec "$@"
