#!/usr/bin/env bash

if [ -z ${DOMAINS} ] || [ -z ${UPSTREAMS} ]; then
  echo "### The following environment variables need to be set"
  echo "  DOMAINS            : comma seperated list of domains"
  echo "  UPSTREAMS          : comma seperated list of upstreams (for the same application)"
  echo "  UPSTREAM_PROTOCOL  : the protocol used for upstreams (http or https)"
  echo ""
  echo "### The following environment variables optional to be set"
  echo "  LOCATIONS          : comma seperated list of locations (for the same application)"
  exit 1
fi

echo "### Generating configuration files based on enviroment"
default_config='/etc/nginx/conf.d/default.conf'
rm -f ${default_config}
readarray -d , -t domains <<< "${DOMAINS}"
for domain in ${domains[@]}
do
  echo "### Domain: ${domain}"
  cat >> ${default_config} << EOF
server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name ${domain};

  ssl_certificate "/etc/letsencrypt/live/${domain}/fullchain.pem";
  ssl_certificate_key "/etc/letsencrypt/live/${domain}/privkey.pem";

  # For security reasons
  # include /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

  ssl_prefer_server_ciphers on;
  ssl_protocols TLSv1.2;
  ssl_ciphers "EECDH+ECDSA+AESGCM EECDH+aRSA+AESGCM EECDH+ECDSA+SHA384 EECDH+ECDSA+SHA256 EECDH+aRSA+SHA384 EECDH+aRSA+SHA256 EECDH+aRSA+RC4 EECDH EDH+aRSA HIGH !RC4 !aNULL !eNULL !LOW !3DES !MD5 !EXP !PSK !SRP !DSS";
  ssl_session_cache shared:le_nginx_SSL:10m;
  ssl_session_timeout 1440m;
  ssl_session_tickets off;

  # enables HSTS for 1 year (31536000 seconds)
  add_header Strict-Transport-Security "max-age=31536000" always;

  add_header X-Frame-Options "SAMEORIGIN";
  add_header X-XSS-Protection "1; mode=block";
  add_header X-Content-Type-Options nosniff;
  add_header Cache-Control no-cache="Set-Cookie";

  root /web_root;
  index index.html;

  include /etc/nginx/conf.d/locations.nginx;
}
EOF
done

upstream_config='/etc/nginx/conf.d/upstreams.nginx'
readarray -d , -t upstreams <<< "${UPSTREAMS}"
echo "upstream targets {" > ${upstream_config}
for upstream in ${upstreams[@]}
do
  echo "### Upstream: ${upstream}"
  echo "  server ${upstream} max_fails=3 fail_timeout=10s;" >> ${upstream_config}
done
echo "}" >> ${upstream_config}

location_config='/etc/nginx/conf.d/locations.nginx'
rm -f ${location_config}
readarray -d , -t locations <<< "${LOCATIONS}"
cat >> ${location_config} << EOF
location /.well-known/acme-challenge/ {
    root /var/www/certbot;
}
EOF
if [ ! -z ${LOCATIONS} ]; then
  for location in ${locations[@]}
  do
    uri=${location%%!*}
    target=${location#*!}
    echo "location ${uri} {" >> ${location_config}
    echo "### Target: ${uri} --> ${target}"
    if [[ $target == http* ]]; then
      cat >> ${location_config} << EOF
  proxy_set_header Host \$http_host;
  proxy_set_header X-Real-IP \$remote_addr;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Scheme \$scheme;
  proxy_set_header X-Forwarded-Proto \$scheme;
  proxy_read_timeout 180s;
  proxy_redirect off;
  proxy_pass ${target};
EOF
    else
      echo "  alias ${target};" >> ${location_config}
    fi
    echo "}" >> ${location_config}
  done
  cat >> ${location_config} << EOF
location / {
  try_files \$uri \$uri/ /index.html;
}
EOF
else
  cat >> ${location_config} << EOF
location / {
  proxy_next_upstream error timeout http_503;
  proxy_pass https://targets;
}
EOF
fi

conf_dir='/etc/letsencrypt'
rsa_key_size=4096

if [ ! -e "${conf_dir}/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "${conf_dir}"
  # curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "${conf_dir}/options-ssl-nginx.conf"
  # We should chage this to generate dh-params using openssl
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "${conf_dir}/ssl-dhparams.pem"
  echo
fi

# We empty the config and leave only certbot.conf
mkdir -p /tmp/nginx
mv /etc/nginx/conf.d/*.conf /tmp/nginx/.
mv /tmp/nginx/certbot.conf /etc/nginx/conf.d/.

echo "### Staring nginx in background"
nginx
if [ $? -ne 0 ]; then
  echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
  echo "### Nginx can not be started due to an error"
  exit 1
fi

echo "### Waiting for nginx to start ..."
wait -n

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
mv /tmp/nginx/*.conf /etc/nginx/conf.d/. 

# Reload nginx
nginx -s reload
echo "### Waiting for nginx to start ..."
wait -n

echo "### Staring nginx reloader in background"
sh -c "/reloader.sh" &

# We start the certbot observer to check every 12h if a certificate has expired
echo "### Staring certbot renewal in background"
# sh -c "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $!; done;'" &
sh -c "/renewer.sh" &

$@
