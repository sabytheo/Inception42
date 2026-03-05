#!/bin/bash
set -e

DB_PASSWORD=$(cat /run/secrets/db_password)
WP_ADMIN_PASSWORD=$(cat /run/secrets/credentials)

# Attendre que MariaDB soit disponible sur le port 3306
echo "Attente de MariaDB..."
while ! (echo > /dev/tcp/mariadb/3306) 2>/dev/null; do
    sleep 1
done
echo "MariaDB est prêt."

cd /var/www/wordpress

if [ ! -f wp-settings.php ]; then
	echo " Telechargement de  Wordpress.."
	wp core download --allow-root
fi

# N'installer WordPress que si ce n'est pas déjà fait (persistance du volume)
if [ ! -f wp-config.php ]; then

    # Créer wp-config.php
    wp config create \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASSWORD}" \
        --dbhost=mariadb \
        --allow-root

    # Installer WordPress (le WP_ADMIN_USER ne doit pas contenir admin/Admin)
    wp core install \
        --url="https://${DOMAIN_NAME}" \
        --title="Inception" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email \
        --allow-root

    # Créer le second utilisateur (auteur, pas admin)
    wp user create "${WP_USER}" "${WP_USER_EMAIL}" \
        --role=author \
        --user_pass="${WP_USER_PASSWORD}" \
        --allow-root

    chown -R www-data:www-data /var/www/wordpress
fi

# Lancer php-fpm en foreground comme PID 1
exec php-fpm8.2 -F
