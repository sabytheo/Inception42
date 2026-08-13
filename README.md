*This project has been created as part of the 42 curriculum by tsaby.*

# Inception

## Description

Inception is a system administration project whose goal is to build a small,
complete web infrastructure from scratch, entirely containerised with Docker
and orchestrated with Docker Compose.

The stack serves a WordPress website over HTTPS only. It is composed of three
services, each running in its own dedicated container, built from a Dockerfile
written by hand — no ready-made image is ever pulled from Docker Hub apart from
the Debian base image:

| Service     | Role                                                          | Base image        |
|-------------|---------------------------------------------------------------|-------------------|
| `nginx`     | TLS termination and reverse proxy, sole entry point (port 443) | `debian:bookworm` |
| `wordpress` | WordPress + PHP-FPM listening on port 9000 (no web server)     | `debian:bookworm` |
| `mariadb`   | The database backing WordPress (no web server)                 | `debian:bookworm` |

The three containers communicate over a private Docker bridge network. Only
NGINX publishes a port to the host, and only `443`, using TLSv1.2 / TLSv1.3.
Two named volumes keep the database and the website files alive across restarts
and rebuilds.

Debian **bookworm** is used as the base image for every service: it is the
penultimate stable Debian release, as required by the subject.

## Instructions

### Prerequisites

* A Linux virtual machine with `docker`, `docker compose` and `make` installed.
* Your user must be able to run Docker (member of the `docker` group, or use
  `sudo`).
* The domain `tsaby.42.fr` must resolve to the local machine. Add this line to
  `/etc/hosts` on the host:

  ```
  127.0.0.1	tsaby.42.fr
  ```

### Configuration files (not versioned)

Credentials are deliberately kept out of Git. Before the first build you must
create them locally — see [`DEV_DOC.md`](DEV_DOC.md) for the exact contents:

```
Inception42/
├── secrets/
│   ├── credentials.txt        # WordPress administrator password
│   ├── db_password.txt        # MariaDB application user password
│   ├── db_root_password.txt   # MariaDB root password
│   └── wp_user_password.txt   # WordPress second user password
└── srcs/
    └── .env                   # DOMAIN_NAME, MYSQL_*, WP_* variables
```

### Build and run

From the root of the repository:

```bash
make          # create the host data directories, build the images and start the stack
```

Then open <https://tsaby.42.fr> in a browser. The certificate is self-signed,
so the browser will show a warning that you have to accept.

### Available targets

| Command       | Effect                                                                    |
|---------------|---------------------------------------------------------------------------|
| `make`        | Create `/home/tsaby/data/{wordpress,mariadb}`, build the images, start all |
| `make stop`   | Stop the containers without removing them                                 |
| `make down`   | Stop and remove the containers and the network                            |
| `make clean`  | `make down` then prune all unused Docker images, containers and volumes   |
| `make fclean` | `make clean` then delete `/home/tsaby/data` (**destroys all data**)       |
| `make re`     | `make fclean` followed by a full rebuild                                  |

## Project description

### Use of Docker

Docker is used here to isolate each service of the infrastructure into its own
container, with its own filesystem, its own process tree and its own lifecycle,
while keeping everything reproducible from a handful of text files.

Every image is built locally from `debian:bookworm` by a Dockerfile stored in
`srcs/requirements/<service>/`. Each Dockerfile installs only the packages that
service needs, copies its configuration file from `conf/` and its startup
script from `tools/`, then declares that script as the `ENTRYPOINT`.

Each startup script ends with `exec`, so the real daemon replaces the shell and
becomes **PID 1** inside the container. This matters: PID 1 is the process that
receives the signals sent by Docker, so `docker stop` results in a clean
shutdown rather than a `SIGKILL` after a timeout. It is also why no
`tail -f`, `sleep infinity` or `while true` hack is needed anywhere — the
daemons themselves are run in the foreground (`nginx -g 'daemon off;'`,
`php-fpm8.2 -F`, `mysqld`).

### Sources included in the project

```
.
├── Makefile                          # single entry point, drives docker compose
├── README.md
├── USER_DOC.md                       # end-user / administrator documentation
├── DEV_DOC.md                        # developer documentation
└── srcs
    ├── docker-compose.yml            # services, network, volumes, secrets
    ├── .env                          # environment variables (git-ignored)
    └── requirements
        ├── mariadb
        │   ├── Dockerfile
        │   ├── conf/99-server.cnf    # listen on the Docker network
        │   └── tools/init.sh         # first-run bootstrap, then exec mysqld
        ├── nginx
        │   ├── Dockerfile
        │   ├── conf/nginx.conf       # TLS vhost template, PHP-FPM upstream
        │   └── tools/setup.sh        # self-signed cert, envsubst, exec nginx
        └── wordpress
            ├── Dockerfile
            ├── conf/www.conf         # PHP-FPM pool listening on 0.0.0.0:9000
            └── tools/setup.sh        # wait for DB, wp-cli install, exec php-fpm
```

### Main design choices

**One process per container.** NGINX does not run PHP, WordPress does not run a
web server, MariaDB does not serve HTTP. The three talk to each other over the
`inception` bridge network by container name: NGINX forwards `.php` requests to
`fastcgi_pass wordpress:9000;`, and WordPress connects to the database at host
`mariadb`. Docker's embedded DNS resolves those names, which is why `links:` is
neither needed nor allowed.

**Templated NGINX configuration.** The vhost is shipped as a template and
rendered at startup with `envsubst`, so the domain name lives in a single place
(`DOMAIN_NAME` in `.env`) and is injected into both the server name and the
self-signed certificate's `CN` / `subjectAltName`.

**Idempotent startup scripts.** Both `mariadb/tools/init.sh` and
`wordpress/tools/setup.sh` detect whether the volume already contains data
(`/var/lib/mysql/$MYSQL_DATABASE`, `wp-config.php`) and skip the bootstrap if so.
Restarting or rebuilding the stack therefore never wipes or duplicates data.

**Startup ordering handled in the application, not in Compose.**
`depends_on` only guarantees start order, not readiness. The WordPress entrypoint
actively polls the database with `mariadb-admin ping` until it answers before
running `wp core install`, which makes the stack resilient to a slow first boot
of MariaDB.

**Secrets read from the filesystem, never baked into images.** Passwords are
mounted by Docker into `/run/secrets/` and read by the entrypoint scripts at
runtime. They appear in no layer of any image, in no `ENV`, and in no commit.

### Virtual Machines vs Docker

A virtual machine emulates a whole computer: the hypervisor gives it virtual
hardware, and a complete guest kernel plus a full userland boots on top of it.
Isolation is very strong — the guest kernel is genuinely separate — but the cost
is high: gigabytes of disk, hundreds of megabytes of RAM before a single useful
process starts, and tens of seconds to boot.

A container shares the host kernel. It is a normal process on the host, isolated
by kernel features (namespaces for PID, network, mounts, users; cgroups for
resource limits). Only the userland is packaged in the image, so a container
starts in milliseconds and weighs megabytes.

For this project the trade-off is clear: the three services all need Linux and
none of them need kernel-level isolation from each other, so running three
containers on one kernel is dramatically cheaper than three virtual machines.
The counterpart is that containers give weaker isolation — a kernel
vulnerability is shared by every container — and that a container cannot run a
different kernel than the host, which is why the whole project itself is
required to run inside a VM.

### Secrets vs Environment Variables

Environment variables are convenient and are the standard way to configure a
container, but they leak easily. They are visible in `docker inspect`, in
`/proc/<pid>/environ`, in the output of `env` for any process in the container,
and they are inherited by every child process. If they are set with `ENV` in a
Dockerfile they are also permanently baked into an image layer.

Docker secrets take a different route: the value lives in a file on the host,
and Docker mounts it read-only inside the container at `/run/secrets/<name>`.
It never appears in the image, never appears in the process environment, and the
mount is scoped to the services that explicitly declare it.

This project uses both, according to sensitivity:

* `.env` holds non-secret configuration — `DOMAIN_NAME`, `MYSQL_DATABASE`,
  `MYSQL_USER`, the WordPress usernames and e-mail addresses.
* `secrets/*.txt` holds every password — the MariaDB root and application
  passwords, and the two WordPress account passwords. The entrypoint scripts
  read them with `cat /run/secrets/...` at startup.

Both `srcs/.env` and `secrets/` are listed in `.gitignore`, so no credential is
ever pushed to the repository.

### Docker Network vs Host Network

With `network_mode: host`, a container shares the host's network namespace
directly: it has no IP of its own and every port it opens is opened on the host.
Three containers would then compete for the same port space, and MariaDB's 3306
and PHP-FPM's 9000 would be reachable from outside the machine.

A user-defined bridge network — `inception` here — gives the containers their
own isolated network namespace with private IPs, plus an embedded DNS server
that resolves container names. Only what is explicitly published with `ports:`
crosses over to the host.

That is exactly what the project needs: NGINX publishes `443:443` and nothing
else does, so port 443 is the single door into the infrastructure. MariaDB and
PHP-FPM are reachable at `mariadb:3306` and `wordpress:9000` from inside the
network and are completely unreachable from the host or the outside world.
The DNS resolution also makes the configuration portable — nothing hardcodes an
IP address — which is why `--link` is both obsolete and forbidden.

### Docker Volumes vs Bind Mounts

A container's writable layer disappears when the container is removed, so
anything that must survive a rebuild has to live outside it.

A **bind mount** maps an arbitrary host path into the container. It is simple
and great for development — editing a file on the host is instantly visible
inside — but the path must already exist and is machine-specific, and Docker
manages none of its lifecycle.

A **named volume** is a storage object managed by Docker: it is created,
listed, inspected and removed through the Docker CLI, it is decoupled from any
particular host path, and it survives `docker compose down`.

This project uses two named volumes, `wordpress_db` for `/var/lib/mysql` and
`wordpress_files` for `/var/www/wordpress`. The latter is mounted into both the
WordPress container (which writes the files) and the NGINX container (which
serves the static ones), which is another thing volumes make easy.

The subject additionally requires the data to live under `/home/tsaby/data`.
The volumes are therefore declared with the `local` driver and
`driver_opts: type=none, o=bind, device=/home/tsaby/data/...`, which pins a
Docker-managed named volume to a chosen host directory. They remain named
volumes — declared in the top-level `volumes:` section and referenced by name in
the services — while satisfying the required storage location. The Makefile
creates those directories before starting, since the `local` driver will not
create a missing `device` path itself.

## Resources

### Documentation

* [Docker documentation](https://docs.docker.com/) — engine, images, storage,
  networking.
* [Dockerfile reference](https://docs.docker.com/reference/dockerfile/) and
  [Building best practices](https://docs.docker.com/build/building/best-practices/).
* [Compose file reference](https://docs.docker.com/reference/compose-file/) —
  services, `volumes`, `networks`, `secrets`, `depends_on`.
* [Manage sensitive data with Docker secrets](https://docs.docker.com/engine/swarm/secrets/).
* [NGINX documentation](https://nginx.org/en/docs/) — in particular
  [`ngx_http_ssl_module`](https://nginx.org/en/docs/http/ngx_http_ssl_module.html)
  and [`ngx_http_fastcgi_module`](https://nginx.org/en/docs/http/ngx_http_fastcgi_module.html).
* [PHP-FPM configuration](https://www.php.net/manual/en/install.fpm.configuration.php).
* [MariaDB knowledge base](https://mariadb.com/kb/en/documentation/) —
  `mariadb-install-db`, user privileges, server system variables.
* [WP-CLI commands](https://developer.wordpress.org/cli/commands/) —
  `wp core download`, `wp config create`, `wp core install`, `wp user create`.
* [OpenSSL `req`](https://docs.openssl.org/master/man1/openssl-req/) — generating
  the self-signed certificate.

### Articles and background reading

* [Docker and the PID 1 zombie reaping problem](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)
  — why the entrypoint must `exec` the real daemon.
* [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/) —
  reference for the TLS protocol and cipher directives.
* [Linux namespaces](https://man7.org/linux/man-pages/man7/namespaces.7.html) —
  the kernel mechanisms containers are built on.

### Use of AI

AI assistance was used on this project in a limited and reviewed way:

* **Documentation writing.** Producing a first draft of `README.md`,
  `USER_DOC.md` and `DEV_DOC.md` from the actual content of the repository,
  which I then read, corrected and completed.
* **Explaining concepts.** Clarifying points I wanted to understand properly
  before writing the code: what PID 1 changes in a container, how Docker secrets
  differ from environment variables, and how a `local` volume with
  `driver_opts` behaves compared to a plain bind mount.
* **Reviewing configuration.** Having my `nginx.conf`, `www.conf` and
  entrypoint scripts read over to spot mistakes, which I then verified myself
  against the official documentation listed above.

No part of the infrastructure was generated and used without being understood.
Every configuration file and script in `srcs/` was written, tested and debugged
by hand against a running stack, and every AI suggestion was checked against the
official documentation before being kept.
