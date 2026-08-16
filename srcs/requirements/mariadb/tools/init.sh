#!/bin/bash
set -e

DB_PASSWORD=$(cat /run/secrets/db_password)
DB_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)

mkdir -p /run/mysqld
chown -R mysql:mysql  /run/mysqld

if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then

    mariadb-install-db --user=mysql --datadir=/var/lib/mysql > /dev/null
    mysqld --user=mysql --skip-networking &
    MYSQL_PID=$!
    until mariadb-admin ping --silent 2>/dev/null; do
        sleep 1
    done
    mysql --user=root << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
EOF
    mariadb-admin -u root -p"${DB_ROOT_PASSWORD}" shutdown
    wait $MYSQL_PID
fi

exec mysqld --user=mysql
