#!/bin/bash
set -e

echo "Aguardando o MariaDB..."
until mariadb -h mariadb -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "SELECT 1" &>/dev/null; do
    sleep 2
done
echo "MariaDB disponível."

cd /var/www/html

if [ ! -f wp-config.php ]; then
    echo "Instalando o WordPress..."

    wp core download --allow-root

    wp config create --allow-root \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${MYSQL_PASSWORD}" \
        --dbhost=mariadb

    wp core install --allow-root \
        --url="${DOMAIN_NAME}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email

    wp user create --allow-root \
        "${WP_USER}" "${WP_USER_EMAIL}" \
        --user_pass="${WP_USER_PASSWORD}" \
        --role=author

    chown -R www-data:www-data /var/www/html
    echo "WordPress instalado."
fi

exec php-fpm8.2 -F
