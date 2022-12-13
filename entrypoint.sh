#!/usr/bin/env bash

if [ -z ${SMNRP_DOMAINS} ]; then
  echo "### The following environment variables need to be set"
  echo "  SMNRP_DOMAINS            : comma seperated list of domains"
  echo ""
  echo "### The following environment variables optional to be set"
  echo "  SMNRP_UPSTREAMS          : comma seperated list of upstreams (for the same application)"
  echo "  SMNRP_UPSTREAM_PROTOCOL  : the protocol used for upstreams (http or https)"
  echo "  SMNRP_LOCATIONS          : comma seperated list of locations (for the same application)"
  exit 1
fi

echo "### Generating configuration files based on enviroment"
default_config='/etc/nginx/conf.d/default.conf'
rm -f ${default_config}
readarray -d , -t domains < <(printf '%s' "${SMNRP_DOMAINS}")
domain=${domains[0]}
echo "### Domain: ${domain}"
cat >> ${default_config} << EOF
server {
  listen 443 ssl http2 default_server;
  # listen [::]:443 ssl http2 default_server;
  server_name _;

  ssl_certificate "/etc/letsencrypt/live/${domain}/fullchain.pem";
  ssl_certificate_key "/etc/letsencrypt/live/${domain}/privkey.pem";

  # For security reasons
  # include /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

  ssl_prefer_server_ciphers on;
  ssl_protocols TLSv1.2 TLSv1.3;
  # proposal from https://raymii.org/s/tutorials/Strong_SSL_Security_On_nginx.html
  ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
  # for backward compatibility we could use:
  # ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:ECDHE-RSA-AES128-GCM-SHA256:AES256+EECDH:DHE-RSA-AES128-GCM-SHA256:AES256+EDH:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA:ECDHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES256-GCM-SHA384:AES128-GCM-SHA256:AES256-SHA256:AES128-SHA256:AES256-SHA:AES128-SHA:DES-CBC3-SHA:HIGH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4";
  ssl_session_cache shared:le_nginx_SSL:10m;
  ssl_session_timeout 1440m;
  ssl_session_tickets off;

  include /etc/nginx/conf.d/ocspstapling.nginx;

  # enables HSTS for 1 year (31536000 seconds)
  add_header Strict-Transport-Security "max-age=31536000; includeSubdomains; preload";

  add_header X-Frame-Options "SAMEORIGIN";
  add_header X-XSS-Protection "1; mode=block";
  add_header X-Content-Type-Options nosniff;
  add_header Cache-Control no-cache="Set-Cookie";
  # We remove this and make the CSP configurable
  # add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

  root /web_root;
  index index.html;

  include /etc/nginx/conf.d/errorpages.nginx;
  include /etc/nginx/conf.d/locations.nginx;
}
EOF

ocspstapling_config='/etc/nginx/conf.d/ocspstapling.nginx'
if [ "${SMNRP_SELF_SIGNED}" != 'true' ]; then
  echo "### Enable OCSP Stapling"
  cat > ${ocspstapling_config} << EOF
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
EOF
else
  touch ${ocspstapling_config}
fi

upstream_config='/etc/nginx/conf.d/upstreams.nginx'
if [ ! -z ${SMNRP_UPSTREAMS} ]; then
  readarray -d , -t upstreams < <(printf '%s'  "${SMNRP_UPSTREAMS}")
  echo "upstream targets {" > ${upstream_config}
  for upstream in ${upstreams[@]}
  do
    echo "### Upstream: ${upstream}"
    echo "  server ${upstream} max_fails=3 fail_timeout=10s;" >> ${upstream_config}
  done
  echo "}" >> ${upstream_config}
else
  touch ${upstream_config}
fi

location_config='/etc/nginx/conf.d/locations.nginx'
rm -f ${location_config}
readarray -d , -t locations < <(printf '%s' "${SMNRP_LOCATIONS}")
cat >> ${location_config} << EOF
location /.well-known/acme-challenge/ {
    root /var/www/certbot;
}
EOF
if [ ! -z ${SMNRP_LOCATIONS} ]; then
  for location in ${locations[@]}
  do
    parts=($(echo "$location" | tr '!' '\n'))
    uri=${parts[0]}
    target=${parts[1]}
    flags=($(echo "${parts[2]}" | tr ':' '\n'))
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
      if [[ " ${flags[*]} " =~ " t " ]]; then
        echo "  try_files \$uri \$uri/ /index.html;" >> ${location_config}
      fi
    fi
    echo "}" >> ${location_config}
  done
  cat >> ${location_config} << EOF
location / {
  try_files \$uri \$uri/ /index.html;
}
EOF
else
  if [ ! -z ${SMNRP_UPSTREAMS} ]; then
    cat >> ${location_config} << EOF
location / {
  proxy_next_upstream error timeout http_503;
  proxy_pass https://targets;
}
EOF
  fi
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

if [ "${SMNRP_OWN_CERT}" == "true" ]; then
  echo "### Using own certificate for ${SMNRP_DOMAINS} ..."
else
  if [ "${SMNRP_SELF_SIGNED}" == 'true' ]; then
    echo "### Generating self signed certificate for ${SMNRP_DOMAINS} ..."
    # mkdir -p /etc/letsencrypt/rootCA
    mkdir -p /etc/letsencrypt/live/${domain}
    if [[ "${SMNRP_SELF_SIGNED_RENEW}" == 'true' ]] || [[ ! -f /etc/letsencrypt/live/${domain}/csr.conf ]]; then
      cat > /etc/letsencrypt/live/${domain}/csr.conf << EOF
[ req ]
default_bits = 2048
default_md = sha256
req_extensions = req_ext
x509_extensions = v3_req
distinguished_name = dn
prompt = no

[ dn ]
C = XX
ST = N/A
L = N/A
O = Self-signed certificate
CN = ${domain}

[ req_ext ]
subjectAltName = @alt_names

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
EOF
      ip_cnt=1
      dns_cnt=1
      for entry in "${domains[@]}"
      do
        if [[ $entry =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
          echo "IP.${ip_cnt} = ${entry}" >> /etc/letsencrypt/live/${domain}/csr.conf
          (( ip_cnt++ ))
        else
          echo "DNS.${dns_cnt} = ${entry}" >> /etc/letsencrypt/live/${domain}/csr.conf
          (( dns_cnt++ ))
        fi
      done
    fi
    if [[ "${SMNRP_SELF_SIGNED_RENEW}" == 'true' ]] || [[ ! -f /etc/letsencrypt/live/${domain}/fullchain.pem ]]; then
      openssl req \
        -x509 \
        -nodes \
        -days 3650 \
        -newkey rsa:4096 \
        -keyout /etc/letsencrypt/live/${domain}/privkey.pem \
        -out /etc/letsencrypt/live/${domain}/fullchain.pem \
        -config /etc/letsencrypt/live/${domain}/csr.conf
    fi
  else
    if [[ "${SMNRP_REQUEST_ON_BOOT}" == 'true' ]] || [[ ! -f /etc/letsencrypt/live/${domain}/fullchain.pem ]]; then
      echo "### Requesting Let's Encrypt certificate for ${SMNRP_DOMAINS} ..."
      rsa_key_size=4096
      certbot certonly --webroot -w /var/www/certbot \
        --register-unsafely-without-email \
        -d ${SMNRP_DOMAINS} \
        --rsa-key-size $rsa_key_size \
        --agree-tos \
        --force-renewal
    else
      echo "### No new Let's Encrypt certificate request needed for ${SMNRP_DOMAINS} ..."
    fi
  fi
fi

# We move back the original config
mv /tmp/nginx/*.conf /etc/nginx/conf.d/. 

# Reload nginx
nginx -s reload
echo "### Waiting for nginx to start ..."
wait -n

echo "### Staring nginx reloader in background"
sh -c "/reloader.sh" &

if [ ! -z $@ ]; then
  $@
else
  # We start the certbot observer to check every 12h if a certificate has expired
  echo "### Staring certbot renewal in background"
  sh -c "/renewer.sh"
fi
