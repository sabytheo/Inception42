#!/bin/bash
set -e

# Générer le certificat SSL auto-signé si inexistant
if [ ! -f /etc/ssl/certs/inception.crt ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/inception.key \
        -out    /etc/ssl/certs/inception.crt \
        -subj   "/C=FR/ST=IDF/L=Paris/O=42/OU=42/CN=${DOMAIN_NAME}"
fi

# Substituer la variable DOMAIN_NAME dans la config NGINX
envsubst '${DOMAIN_NAME}' \
    < /etc/nginx/templates/nginx.conf.template \
    > /etc/nginx/nginx.conf

# Lancer nginx en foreground (PID 1)
exec nginx -g 'daemon off;'
