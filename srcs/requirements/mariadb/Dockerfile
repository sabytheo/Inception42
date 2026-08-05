FROM debian:bookworm

RUN apt-get update && apt-get install -y \
    mariadb-server \
    && rm -rf /var/lib/apt/lists/*

COPY conf/99-server.cnf /etc/mysql/mariadb.conf.d/99-server.cnf
COPY tools/init.sh /init.sh

RUN chmod +x /init.sh

EXPOSE 3306

ENTRYPOINT ["/init.sh"]
