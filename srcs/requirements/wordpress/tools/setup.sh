#!/bin/bash
set -e

DB_PASSWORD=$(cat /run/secrets/db_password)
WP_ADMIN_PASSWORD=$(cat /run/secrets/credentials)
WP_USER_PASSWORD=$(cat /run/secrets/wp_user_password)

echo "Attente de MariaDB..."
until mariadb-admin ping -h mariadb -u "${MYSQL_USER}" -p"${DB_PASSWORD}" --silent; do
    sleep 2
done
echo "MariaDB est prêt."

cd /var/www/wordpress

if [ ! -f wp-settings.php ]; then
	echo " Telechargement de  Wordpress.."
	wp core download --allow-root
fi

if [ ! -f wp-config.php ]; then

    wp config create \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASSWORD}" \
        --dbhost=mariadb \
        --allow-root

    wp core install \
        --url="https://${DOMAIN_NAME}" \
        --title="Inception" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email \
        --allow-root

    wp user create "${WP_USER}" "${WP_USER_EMAIL}" \
        --role=author \
        --user_pass="${WP_USER_PASSWORD}" \
        --allow-root

    chown -R www-data:www-data /var/www/wordpress
fi

exec php-fpm8.2 -F
