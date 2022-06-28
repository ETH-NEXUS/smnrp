#!/usr/bin/env bash

if [ -z ${DOMAINS} ]; then
  echo "### Environment variable DOMAINS is not set"
  exit 1
fi

conf_dir='/etc/letsencrypt'
rsa_key_size=4096

if [ ! -e "${conf_dir}/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "${conf_dir}"
  # curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "${conf_dir}/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "${conf_dir}/ssl-dhparams.pem"
  echo
fi

echo "### Staring nginx in background"
nginx
echo "### Waiting 5 secs for nginx to start ..."
sleep 5

# We empty the config and leave only certbot.conf
mkdir -p /tmp/nginx
mv /etc/nginx/conf.d/* /tmp/nginx/.
mv /tmp/nginx/certbot.conf /etc/nginx/conf.d/.

echo "### Requesting Let's Encrypt certificate for ${DOMAINS} ..."
certbot certonly --webroot -w /var/www/certbot \
  --staging \
  --debug \
  --register-unsafely-without-email \
  -d ${DOMAINS} \
  --rsa-key-size $rsa_key_size \
  --agree-tos \
  --force-renewal

# We move back the original config
mv /tmp/nginx/* /etc/nginx/conf.d/. 

# Reload nginx
nginx -s reload
echo "### Waiting 5 secs for nginx to restart ..."
sleep 5

# We start the certbot observer to check every 12h if a certificate has expired
echo "### Staring certbot renewal in background"
sh -c "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $!; done;'" &

echo "### Staring nginx reloader in background"
sh -c "/reloader.sh" &

$@
