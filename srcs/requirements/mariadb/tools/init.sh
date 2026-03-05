#!/bin/bash
set -e

DB_PASSWORD=$(cat /run/secrets/db_password)
DB_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)

mkdir -p /run/mysqld
chown -R mysql:mysql  /run/mysqld

# N'initialiser que si la base n'existe pas encore (premier démarrage)
if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then

    # Initialiser le répertoire de données MariaDB
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1

    # Démarrer MariaDB temporairement pour la configuration
    mysqld --user=mysql &
    MYSQL_PID=$!

    # Attendre que MariaDB soit prêt
    until mysqladmin ping --silent 2>/dev/null; do
        sleep 1
    done

    # Configurer la base de données et les utilisateurs
    mysql --user=root << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
EOF

    # Arrêter l'instance temporaire proprement
    kill $MYSQL_PID
    wait $MYSQL_PID
fi

# Lancer MariaDB en foreground comme PID 1
exec mysqld --user=mysql
