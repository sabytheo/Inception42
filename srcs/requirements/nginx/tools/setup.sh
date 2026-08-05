#!/bin/bash
set -e
if [ ! -f /etc/ssl/certs/inception.crt ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/inception.key \
        -out    /etc/ssl/certs/inception.crt \
        -subj   "/C=FR/ST=69/L=Lyon/O=42/OU=42/CN=${DOMAIN_NAME}" \
        -addext "subjectAltName=DNS:${DOMAIN_NAME}"

fi

envsubst '${DOMAIN_NAME}' \
    < /etc/nginx/templates/nginx.conf.template \
    > /etc/nginx/nginx.conf

exec nginx -g 'daemon off;'
