FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
        mariadb-server \
    && rm -rf /var/lib/apt/lists/*

COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf
COPY tools/init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

RUN rm -rf /var/lib/mysql/* \
    && mkdir -p /var/run/mysqld /var/lib/mysql \
    && chown -R mysql:mysql /var/run/mysqld /var/lib/mysql

EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/init.sh"]
