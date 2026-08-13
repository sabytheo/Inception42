# Developer documentation

This document is meant for a developer who needs to set the Inception stack up
from scratch, build it, run it, and understand where its data lives.

For day-to-day usage of the running site, see [`USER_DOC.md`](USER_DOC.md).
For the design rationale behind the architecture, see [`README.md`](README.md).

---

## 1. Setting up the environment from scratch

### 1.1 Prerequisites

The project must run inside a **Linux virtual machine**. On the guest you need:

| Requirement      | Notes                                                       |
|------------------|-------------------------------------------------------------|
| `docker`         | Engine 20.10 or later                                        |
| `docker compose` | v2, invoked as `docker compose` (not the legacy `docker-compose`) |
| `make`           | GNU Make                                                     |
| `git`            | To clone the repository                                      |
| `sudo`           | Needed by `make fclean` and to edit `/etc/hosts`             |

Verify the toolchain:

```bash
docker --version
docker compose version
make --version
```

Add your user to the `docker` group so Docker can be used without `sudo`
(log out and back in for it to take effect):

```bash
sudo usermod -aG docker $USER
```

### 1.2 Clone the repository

```bash
git clone <repository-url> Inception42
cd Inception42
```

### 1.3 Configure the domain name

The stack answers to `tsaby.42.fr`, which must resolve to the local machine.
Add it to the host's `/etc/hosts`:

```bash
echo "127.0.0.1	tsaby.42.fr" | sudo tee -a /etc/hosts
```

Confirm with `ping -c 1 tsaby.42.fr`.

### 1.4 Create the environment file

`srcs/.env` is git-ignored and therefore absent from a fresh clone. Create it:

```bash
cat > srcs/.env <<'EOF'
# Domain
DOMAIN_NAME=tsaby.42.fr

# MariaDB
MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user

# WordPress administrator
WP_ADMIN_USER=bossman
WP_ADMIN_EMAIL=bossman@tsaby.42.fr

# WordPress secondary user
WP_USER=redactor
WP_USER_EMAIL=redactor@tsaby.42.fr
EOF
```

Every variable is consumed as follows:

| Variable         | Read by               | Purpose                                                   |
|------------------|-----------------------|-----------------------------------------------------------|
| `DOMAIN_NAME`    | `nginx`, `wordpress`  | `server_name`, certificate `CN`/SAN, WordPress site URL    |
| `MYSQL_DATABASE` | `mariadb`, `wordpress`| Name of the database to create and connect to              |
| `MYSQL_USER`     | `mariadb`, `wordpress`| Application database user                                  |
| `WP_ADMIN_USER`  | `wordpress`           | WordPress administrator login                              |
| `WP_ADMIN_EMAIL` | `wordpress`           | WordPress administrator e-mail                             |
| `WP_USER`        | `wordpress`           | Second WordPress account (role `author`)                   |
| `WP_USER_EMAIL`  | `wordpress`           | Second account's e-mail                                    |

> **Constraint from the subject.** `WP_ADMIN_USER` must not contain `admin` or
> `administrator` in any casing — `admin`, `Admin`, `administrator`,
> `admin-123` are all rejected at evaluation. Pick something unrelated.

### 1.5 Create the secrets

Passwords never go in `.env`. They live one-per-file in `secrets/`, which is
also git-ignored. The four files are mandatory — a missing one makes the
corresponding container fail at startup.

```bash
mkdir -p secrets

printf '%s' 'YourDbUserPassword'    > secrets/db_password.txt
printf '%s' 'YourDbRootPassword'    > secrets/db_root_password.txt
printf '%s' 'YourWpAdminPassword'   > secrets/credentials.txt
printf '%s' 'YourWpUserPassword'    > secrets/wp_user_password.txt

chmod 600 secrets/*.txt srcs/.env
```

Use `printf` rather than `echo` so no trailing newline is written — the scripts
read these files with `cat` and pass the result straight into SQL statements and
`wp` commands, where a stray newline would become part of the password.

| Secret file             | Mounted in            | Used for                                     |
|-------------------------|-----------------------|----------------------------------------------|
| `db_root_password.txt`  | `mariadb`             | MariaDB `root@localhost` password             |
| `db_password.txt`       | `mariadb`, `wordpress`| `MYSQL_USER` password, and WordPress DB login |
| `credentials.txt`       | `wordpress`           | WordPress administrator password              |
| `wp_user_password.txt`  | `wordpress`           | WordPress `author` account password           |

Docker mounts each of them read-only at `/run/secrets/<name>` in the services
that declare them in `docker-compose.yml`.

### 1.6 Verify `.gitignore`

Before any commit, make sure neither file is tracked:

```bash
cat .gitignore          # must list secrets/ and srcs/.env
git status --short      # must not show secrets/ or srcs/.env
```

A credential present anywhere in the Git history — even in an old commit — fails
the project.

---

## 2. Building and launching the project

Everything goes through the `Makefile` at the root, which is the only entry
point. It drives `docker compose -f srcs/docker-compose.yml`.

```bash
make
```

`make` runs the `setup` target first (`mkdir -p /home/tsaby/data/wordpress
/home/tsaby/data/mariadb`), then `docker compose up --build -d`. The `setup`
step is not optional: the volumes use the `local` driver with a `device` option,
and that driver refuses to start if the host directory does not already exist.

### Make targets

| Target        | Command behind it                                | Effect                                                              |
|---------------|--------------------------------------------------|---------------------------------------------------------------------|
| `all`         | `setup` + `docker compose up --build -d`         | Default target: create data dirs, build images, start detached      |
| `setup`       | `mkdir -p /home/tsaby/data/{wordpress,mariadb}`   | Create the host directories backing the volumes                     |
| `stop`        | `docker compose stop`                            | Stop the containers, keep them                                      |
| `down`        | `docker compose down`                            | Stop and remove containers and network; volumes survive             |
| `clean`       | `down` + `docker system prune -af --volumes`     | Also prune unused images, containers and volumes                    |
| `fclean`      | `clean` + `sudo rm -rf /home/tsaby/data`         | **Destroys all persistent data**                                    |
| `re`          | `fclean` + `all`                                 | Full rebuild from a blank slate                                     |

> `make clean` runs `docker system prune -af --volumes`, which is
> **system-wide**: it removes every unused image, container, network and volume
> on the machine, not only this project's. Do not run it on a host with other
> Docker workloads you care about.

### What happens on the first build

1. Compose builds the three images from `srcs/requirements/<service>/Dockerfile`,
   each `FROM debian:bookworm`.
2. `mariadb` starts. `init.sh` sees `/var/lib/mysql/$MYSQL_DATABASE` is missing,
   runs `mariadb-install-db`, starts a temporary server, sets the root password,
   creates the database and the application user, removes the anonymous users and
   the `test` database, shuts the temporary server down, then `exec mysqld`.
3. `wordpress` starts. `setup.sh` polls `mariadb-admin ping -h mariadb` until the
   database answers, downloads WordPress with `wp core download`, generates
   `wp-config.php`, runs `wp core install`, creates the second user with role
   `author`, fixes ownership to `www-data`, then `exec php-fpm8.2 -F`.
4. `nginx` starts. `setup.sh` generates a self-signed certificate for
   `$DOMAIN_NAME` if none exists, renders `nginx.conf` from its template with
   `envsubst`, then `exec nginx -g 'daemon off;'`.

Every one of those steps is guarded by an existence check, so a restart or a
rebuild re-runs none of the bootstrap and destroys nothing.

Note the ordering guarantee: `depends_on` only controls **start order**, not
readiness. Readiness is handled in `wordpress/tools/setup.sh` by the
`mariadb-admin ping` loop.

### Rebuilding after a change

| What you changed                            | What to run                                    |
|---------------------------------------------|------------------------------------------------|
| A `Dockerfile`, a `conf/` or `tools/` file  | `make down && make` (rebuilds the image)       |
| `docker-compose.yml`                        | `make down && make`                            |
| `srcs/.env`                                 | `make down && make` — but see the warning below |
| Something needing a truly clean state       | `make re`                                      |

> Changing `MYSQL_*` or `WP_*` values in `.env` after the first start does **not**
> reconfigure the running stack: the database and the WordPress installation
> already exist, so both bootstrap blocks are skipped. Only `DOMAIN_NAME` takes
> effect on a restart, because NGINX re-renders its configuration every time.
> To apply new database or account settings you need `make re`.

---

## 3. Managing containers and volumes

### Containers

```bash
docker ps                        # running containers
docker ps -a                     # including stopped ones
docker logs <container>          # full logs
docker logs -f --tail 50 nginx   # follow the last 50 lines live
docker restart wordpress         # restart one service
docker stats                     # live CPU / memory usage
```

Open a shell inside a container to inspect it:

```bash
docker exec -it nginx     /bin/bash
docker exec -it wordpress /bin/bash
docker exec -it mariadb   /bin/bash
```

Check that the entrypoint really is PID 1 — this is what makes `docker stop`
shut the service down cleanly instead of killing it after a timeout:

```bash
docker exec nginx     ps -o pid,comm -p 1     # nginx
docker exec wordpress ps -o pid,comm -p 1     # php-fpm8.2
docker exec mariadb   ps -o pid,comm -p 1     # mariadbd
```

### Images

```bash
docker images                                    # list built images
docker compose -f srcs/docker-compose.yml build  # rebuild without starting
docker compose -f srcs/docker-compose.yml build --no-cache mariadb
docker image inspect nginx --format '{{.Config.Entrypoint}}'
```

### Network

The `inception` bridge network is created by Compose and carries all inter-service
traffic.

```bash
docker network ls
docker network inspect srcs_inception    # containers attached, subnet, IPs
```

Verify that name resolution works between containers:

```bash
docker exec wordpress getent hosts mariadb
docker exec nginx     getent hosts wordpress
```

Verify that nothing but 443 is published to the host:

```bash
docker ps --format '{{.Names}}\t{{.Ports}}'
```

Only the `nginx` row should show `0.0.0.0:443->443/tcp`.

### Volumes

```bash
docker volume ls
docker volume inspect srcs_wordpress_db
docker volume inspect srcs_wordpress_files
```

`docker volume inspect` shows the `driver_opts` pinning each volume to its host
directory under `/home/tsaby/data`.

Volumes are **not** removed by `docker compose down`. To remove them explicitly:

```bash
docker compose -f srcs/docker-compose.yml down -v
```

### Database

```bash
# interactive SQL session as root
docker exec -it mariadb mariadb -u root -p

# one-off query
docker exec -it mariadb mariadb -u root -p -e "SHOW DATABASES;"

# dump the WordPress database to the host
docker exec mariadb mariadb-dump -u root -p"$(cat secrets/db_root_password.txt)" \
    wordpress > backup.sql

# restore it
docker exec -i mariadb mariadb -u root -p"$(cat secrets/db_root_password.txt)" \
    wordpress < backup.sql
```

### WordPress via WP-CLI

`wp` is installed in the WordPress image and is the fastest way to inspect or
modify the site from the command line:

```bash
docker exec -it wordpress wp user list    --allow-root --path=/var/www/wordpress
docker exec -it wordpress wp plugin list  --allow-root --path=/var/www/wordpress
docker exec -it wordpress wp option get siteurl --allow-root --path=/var/www/wordpress
docker exec -it wordpress wp core version --allow-root --path=/var/www/wordpress
```

---

## 4. Where the data is stored and how it persists

### The two named volumes

`docker-compose.yml` declares two named volumes. Both use the `local` driver
with `driver_opts` that pin them to a chosen host directory:

```yaml
volumes:
  wordpress_db:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/tsaby/data/mariadb
  wordpress_files:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/tsaby/data/wordpress
```

| Volume            | Host directory                | Mounted in                                  | Contents                                              |
|-------------------|-------------------------------|---------------------------------------------|-------------------------------------------------------|
| `wordpress_db`    | `/home/tsaby/data/mariadb`    | `mariadb:/var/lib/mysql`                    | InnoDB tablespaces, logs, the whole database          |
| `wordpress_files` | `/home/tsaby/data/wordpress`  | `wordpress:/var/www/wordpress` (read/write) | WordPress core, `wp-config.php`, themes, plugins, uploads |
|                   |                               | `nginx:/var/www/wordpress`                  | same files, served as static content by NGINX          |

`wordpress_files` is deliberately mounted in **two** containers: PHP-FPM needs
the PHP sources to execute them, and NGINX needs the same tree to resolve
`try_files` and serve CSS, JavaScript and images directly without going through
PHP. Sharing one volume is what keeps the two views identical.

They are named volumes — declared in the top-level `volumes:` section and
referenced by name in the services — rather than service-level bind mounts. The
`device` option only tells the `local` driver *where* to keep the data, which is
how the subject's requirement to store it under `/home/login/data` is met while
still being a Docker-managed volume.

### How persistence behaves

| Action                     | Containers | Images  | Volume data          |
|----------------------------|------------|---------|----------------------|
| `make stop`                | stopped    | kept    | **kept**             |
| `make down`                | removed    | kept    | **kept**             |
| `make clean`               | removed    | pruned  | **kept on the host** |
| `make fclean`              | removed    | pruned  | **deleted**          |
| `docker compose down -v`   | removed    | kept    | **deleted**          |

`make clean` prunes the Docker volume objects, but the actual bytes live in
`/home/tsaby/data`, so the data survives and is picked up again when the volumes
are recreated. Only `make fclean` — which `rm -rf`s that directory — is
destructive.

### Inspecting the data directly

Because the volumes are pinned to host paths, the data can be read from the host
without entering a container:

```bash
ls -la /home/tsaby/data/wordpress    # wp-config.php, wp-content, wp-admin, …
sudo ls -la /home/tsaby/data/mariadb # ibdata1, mysql/, the WordPress DB dir, …
```

The MariaDB directory is owned by the `mysql` user from inside the container, so
reading it from the host needs `sudo`.

### Testing persistence end to end

```bash
docker exec -it wordpress wp post create --post_title='Persistence test' \
    --post_status=publish --allow-root --path=/var/www/wordpress
make down
make
docker exec -it wordpress wp post list --allow-root --path=/var/www/wordpress
```

The post must still be listed after the stack has been torn down and rebuilt.

### Backing up

Both storages are plain directories on the host, so a backup is a copy:

```bash
# stop writes first for a consistent database snapshot
make stop
sudo tar czf inception-backup-$(date +%F).tar.gz -C /home/tsaby data
make
```

Do not include `secrets/` in an archive you intend to share.

---

## 5. Reference: repository layout

```
Inception42/
├── Makefile                    # the only entry point; drives docker compose
├── README.md                   # project presentation and design rationale
├── USER_DOC.md                 # end-user / administrator documentation
├── DEV_DOC.md                  # this file
├── .gitignore                  # ignores secrets/ and srcs/.env
├── secrets/                    # NOT versioned — one password per file
│   ├── credentials.txt
│   ├── db_password.txt
│   ├── db_root_password.txt
│   └── wp_user_password.txt
└── srcs/
    ├── .env                    # NOT versioned — non-secret configuration
    ├── docker-compose.yml      # services, network, volumes, secrets
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── conf/99-server.cnf
        │   └── tools/init.sh
        ├── nginx/
        │   ├── Dockerfile
        │   ├── conf/nginx.conf
        │   └── tools/setup.sh
        └── wordpress/
            ├── Dockerfile
            ├── conf/www.conf
            └── tools/setup.sh
```

### Ports and endpoints

| Where                    | Port   | Exposed to  | Protocol            |
|--------------------------|--------|-------------|---------------------|
| `nginx` → host           | `443`  | The host    | HTTPS, TLSv1.2/1.3  |
| `wordpress` (PHP-FPM)    | `9000` | The network | FastCGI             |
| `mariadb`                | `3306` | The network | MySQL protocol      |

Only the first line crosses the container boundary to the host.
