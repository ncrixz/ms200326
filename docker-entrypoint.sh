#!/bin/bash
set -e

# Copy .env if it doesn't exist
if [ ! -f /var/www/html/.env ]; then
    cp /var/www/html/.env.example /var/www/html/.env
fi

# Generate app key if APP_KEY env var is not set
if [ -z "$APP_KEY" ]; then
    php artisan key:generate --force
fi

# Clear config before caching (picks up env vars injected by Coolify)
php artisan config:clear

# Run database migrations
php artisan migrate --force

# Cache configuration for performance
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Fix storage permissions at runtime
chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

# Start Apache
exec "$@"
