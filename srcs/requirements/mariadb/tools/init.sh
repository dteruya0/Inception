#!/bin/bash
set -e

if [ ! -d /var/lib/mysql/mysql ]; then
    echo "Inicializando o banco..."
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null

    mysqld --user=mysql --skip-networking &
    PID=$!

    until mysqladmin ping --silent 2>/dev/null; do
        sleep 1
    done

    mysql -u root <<-SQL
        DROP DATABASE IF EXISTS test;
        CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
        CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
        GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
        ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
        FLUSH PRIVILEGES;
SQL

    mysqladmin -u root -p"${MYSQL_ROOT_PASSWORD}" shutdown
    wait $PID
    echo "Banco inicializado."
fi

exec mysqld --user=mysql
