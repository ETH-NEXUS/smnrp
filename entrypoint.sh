#!/usr/bin/env bash

if [ -z ${SMNRP_DOMAINS} ]; then
  echo "### The following environment variables need to be set"
  echo "  SMNRP_DOMAINS            : comma seperated list of domains"
  echo ""
  echo "### The following environment variables optional to be set"
  echo "  SMNRP_UPSTREAMS          : comma seperated list of upstreams (for the same application)"
  echo "  SMNRP_LOCATIONS          : comma seperated list of locations (for the same application)"
  exit 1
fi

# Prepare some paths and files
# this is necessary if user wants to bind mount
# various directories
mkdir -p /var/log/nginx
touch /var/log/nginx/error.log
touch /var/log/nginx/access.log

# If there is no ssl-dhparams file, generate one
if [ ! -e /etc/letsencrypt/ssl-dhparams.pem ]; then
  echo "### Generating Diffie-Hellman (DH) parameters, this may take a while..."
  # We only generate one if the SMNRP_GENERATE_DH_PARAMS parameter is set to true
  # otherwise we copy over the template
  if [ "${SMNRP_GENERATE_DH_PARAMS}" == 'true' ]; then
    openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 4096
  else
    cp /usr/share/nginx/ssl-dhparams.pem /etc/letsencrypt/ssl-dhparams.pem
  fi
fi

echo "### Generating configuration files based on enviroment"
default_config='/etc/nginx/conf.d/default.conf'
rm -f ${default_config}
cat >> ${default_config} << EOF
# Top-level HTTP config for WebSocket headers
# If Upgrade is defined, Connection = upgrade
# If Upgrade is empty, Connection = close
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}
EOF

# Handling vhosts
readarray -d '|' -t vhosts < <(printf '%s' "${SMNRP_DOMAINS}")
readarray -d '|' -t vhost_csps < <(printf '%s' "${SMNRP_CSP}")
readarray -d '|' -t vhost_upstreams < <(printf '%s' "${SMNRP_UPSTREAMS}")
readarray -d '|' -t vhost_locations < <(printf '%s' "${SMNRP_LOCATIONS}")
readarray -d '|' -t vhost_users < <(printf '%s' "${SMNRP_USERS}")
readarray -d '|' -t vhost_whitelist < <(printf '%s' "${SMNRP_WHITELIST}")
readarray -d '|' -t vhost_client_max_body_size < <(printf '%s' "${SMNRP_CLIENT_MAX_BODY_SIZE}")
readarray -d '|' -t vhost_own_cert < <(printf '%s' "${SMNRP_OWN_CERT}")
readarray -d '|' -t vhost_self_signed < <(printf '%s' "${SMNRP_SELF_SIGNED}")
readarray -d '|' -t vhost_self_signed_renew < <(printf '%s' "${SMNRP_SELF_SIGNED_RENEW}")
readarray -d '|' -t vhost_request_on_boot < <(printf '%s' "${SMNRP_REQUEST_ON_BOOT}")
readarray -d '|' -t vhost_disable_ocsp_stapling < <(printf '%s' "${SMNRP_DISABLE_OCSP_STAPLING}")
readarray -d '|' -t vhost_server_tokens < <(printf '%s' "${SMNRP_SERVER_TOKENS}")
readarray -d '|' -t vhost_client_body_buffer_size < <(printf '%s' "${SMNRP_CLIENT_BODY_BUFFER_SIZE}")
readarray -d '|' -t vhost_large_client_header_buffers < <(printf '%s' "${SMNRP_LARGE_CLIENT_HEADER_BUFFERS}")
readarray -d '|' -t vhost_disable_https < <(printf '%s' "${SMNRP_DISABLE_HTTPS}")
readarray -d '|' -t vhost_use_bypass < <(printf '%s' "${SMNRP_USE_BUYPASS}")

if [ ${#vhosts[@]} -gt 1 ]; then
  VHOSTS=1
  echo "### Enabling Vhosts."
else
  VHOSTS=0
fi

# We need to remove the upstreams in the beginning
# because they are globally managed
upstream_config="/etc/nginx/conf.d/upstreams.nginx"
rm -f ${upstream_config}

for i in "${!vhosts[@]}"
do
  readarray -d , -t domains < <(printf '%s' "${vhosts[i]}")
  domain=${domains[0]}
  vhost_path_suffix=''
  vhost_upstream_prefix=''
  listen_suffix=''
  if [ ${VHOSTS} -eq 1 ]; then
    vhost_path_suffix="/${domain}"
    vhost_upstream_prefix="${domain}_"
    mkdir -p /web_root${vhost_path_suffix}
    mkdir -p /var/log${vhost_path_suffix}
    if [ ! -f "/web_root${vhost_path_suffix}/index.html" ]; then
      cp /usr/share/nginx/index.html /web_root${vhost_path_suffix}
      cp /usr/share/nginx/favicon.ico /web_root${vhost_path_suffix}
      cp /usr/share/nginx/background.jpg /web_root${vhost_path_suffix}
    fi
  else
    if [ ! -f /web_root/index.html ]; then
      cp /usr/share/nginx/index.html /web_root/.
      cp /usr/share/nginx/favicon.ico /web_root/.
      cp /usr/share/nginx/background.jpg /web_root/.
    fi
    listen_suffix=" default_server"
  fi
  echo "### Domain: ${domain}"
  if [[ "${vhost_disable_https[i]}" == 'true' ]]; then
    cat >> ${default_config} << EOF
server {
  listen 80${listen_suffix};
  # listen [::]:80 http2${listen_suffix};
  http2 on;
  server_name ${domains[@]};
EOF
  else
    cat >> ${default_config} << EOF
server {
  listen 443 ssl${listen_suffix};
  # listen [::]:443 ssl http2${listen_suffix};
  http2 on;
  server_name ${domains[@]};

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
EOF
  fi
  # General part http and https
  cat >> ${default_config} << EOF
  proxy_hide_header Referrer-Policy;
  add_header Referrer-Policy strict-origin-when-cross-origin;
  
  add_header X-Frame-Options "SAMEORIGIN";
  add_header X-XSS-Protection "1; mode=block";
  add_header X-Content-Type-Options nosniff;
  add_header Cache-Control no-cache="Set-Cookie";
  include /etc/nginx/conf.d${vhost_path_suffix}/csp.nginx;

  proxy_set_header Host \$host;
  proxy_set_header X-Real-IP \$remote_addr;
  proxy_set_header X-Scheme \$scheme;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto \$scheme;
  proxy_set_header X-Forwarded-Ssl on;
  # according to https://www.freecodecamp.org/news/docker-nginx-letsencrypt-easy-secure-reverse-proxy-40165ba3aee2/
  proxy_set_header X-Forwarded-Host \$host;
  proxy_set_header X-Forwarded-Port \$server_port;
  # websocket headers
  proxy_http_version 1.1;
  proxy_set_header Upgrade \$http_upgrade;
  proxy_set_header Connection \$connection_upgrade;

  proxy_read_timeout 180s;
  proxy_redirect off;
  proxy_buffering off;

  error_log  /var/log${vhost_path_suffix}/error.log error;
  access_log  /var/log${vhost_path_suffix}/access.log combined;

  root /web_root${vhost_path_suffix};
  index index.html;

  client_max_body_size ${vhost_client_max_body_size[i]:-1m};

  # Hardening
  server_tokens ${vhost_server_tokens[i]:-off};
  client_body_buffer_size ${vhost_client_body_buffer_size[i]:-1k};
  large_client_header_buffers ${vhost_large_client_header_buffers[i]:-2 1k};

  include /etc/nginx/conf.d/custom${vhost_path_suffix}/*.nginx;
  include /etc/nginx/conf.d/errorpages.nginx;
  include /etc/nginx/conf.d${vhost_path_suffix}/locations.nginx;
}
EOF

  ###
  # Upstreams
  ###
  declare -A upstream_names=()
  if [ ! -z ${vhost_upstreams[i]} ]; then
    readarray -d , -t upstreams < <(printf '%s' "${vhost_upstreams[i]}")
    declare -A targets=()
    for upstream in ${upstreams[@]}
    do
      if grep -q "!" <<< "${upstream}"; then
        parts=($(echo "$upstream" | tr '!' '\n'))
        target="${vhost_upstream_prefix}${parts[0]}"
        upstream_to=${parts[1]}
        upstream_names+=(${parts[0]})
      else
        target="${vhost_upstream_prefix}targets"
        upstream_to="${upstream}"
      fi
      echo "### Upstream for ${domain}: ${target} --> ${upstream_to}"
      targets[$target]="${targets[$target]} ${upstream_to}"
    done
    for target in "${!targets[@]}"
    do
      echo "upstream ${target} {" >> ${upstream_config}
      for _upstream in ${targets[$target]}
      do
        echo "  server ${_upstream} max_fails=3 fail_timeout=10s;" >> ${upstream_config}
        echo "  keepalive 32;" >> ${upstream_config}
      done
      echo "}" >> ${upstream_config}
    done
  else
    touch ${upstream_config}
  fi

  ###
  # Locations
  ###
  location_dir="/etc/nginx/conf.d${vhost_path_suffix}"
  mkdir -p ${location_dir}
  location_config="${location_dir}/locations.nginx"
  default_root_location=1
  rm -f ${location_config}
  readarray -d , -t locations < <(printf '%s' "${vhost_locations[i]}")
  cat >> ${location_config} << EOF
location /.well-known/acme-challenge/ {
    root /var/www/certbot;
}
location /gows/ {
  proxy_pass http://localhost:789${i};
}
location /analytics/ {
  root /web_root${vhost_path_suffix};
  index dashboard.html;
}
EOF
  if [ ! -z ${vhost_locations[i]} ]; then
    for location in ${locations[@]}
    do
      parts=($(echo "$location" | tr '!' '\n'))
      uri=${parts[0]}
      target=${parts[1]}
      flags=($(echo "${parts[2]}" | tr ':' '\n'))
      echo "location ${uri} {" >> ${location_config}
      echo "### Target for ${domain}: ${uri} --> ${target}"
      if [ ! -z ${flags} ]; then
        echo "### Flags for ${uri}: ${flags}"
      fi
      if [[ "$uri" == "/" ]]; then
        echo "### Skipping default / target because it's configured as a location to ${target}."
        default_root_location=0
      fi
      if [[ $target == http* ]]; then
        # if curl --head --silent ${target} > /dev/null 2>&1; then
        potential_upstream_name=$(echo "${target}" | sed -E "s,(http(s)?:\/\/)([^/]+).*,\3,")
        if echo ${upstream_names[@]} | grep -q ${potential_upstream_name}; then
          target_to_use="${target}"
        else
          target_to_use=$(echo "${target}" | sed -E "s,(http(s)?:\/\/)(.*),\1${vhost_upstream_prefix}\3,")
        fi
        if [[ " ${flags[*]} " =~ " r " ]]; then
          echo "  return 301 ${target};" >> ${location_config}
        else
          echo "  proxy_pass ${target_to_use};" >> ${location_config}
        fi
        if [[ " ${flags[*]} " =~ " h " ]] && [[ ! " ${flags[*]} " =~ " r " ]]; then
          echo '  proxy_set_header Host $http_host;' >> ${location_config}
          echo '  proxy_set_header X-Forwarded-Host $http_host;' >> ${location_config}
        fi
      else
        if [[ " ${flags[*]} " =~ " r " ]]; then
          echo "  return 301 ${target};" >> ${location_config}
        else
          echo "  alias ${target};" >> ${location_config}
        fi
        if [[ " ${flags[*]} " =~ " t " ]] && [[ ! " ${flags[*]} " =~ " r " ]]; then
          echo "  try_files \$uri \$uri/ /index.html;" >> ${location_config}
        fi
      fi
      if [[ " ${flags[*]} " =~ " a " ]] && [[ ! " ${flags[*]} " =~ " r " ]]; then
        echo '  auth_basic "Authorization Required";' >> ${location_config}
        echo "  auth_basic_user_file /etc/nginx/conf.d${vhost_path_suffix}/htpasswd;" >> ${location_config}
      fi
      if [[ " ${flags[*]} " =~ " c " ]] && [[ ! " ${flags[*]} " =~ " r " ]]; then
        echo '  add_header Last-Modified $date_gmt;' >> ${location_config}
        echo "  add_header Cache-Control 'private no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0';" >> ${location_config}
        echo '  if_modified_since off;' >> ${location_config}
        echo '  expires off;' >> ${location_config}
        echo '  etag off;' >> ${location_config}
      fi
      if [[ " ${flags[*]} " =~ " w " ]] && [[ ! " ${flags[*]} " =~ " r " ]]; then
        echo "### Configure whitelisting on location ${uri} to only allow: ${vhost_whitelist[i]}..."
        if [ ! -z ${vhost_whitelist[i]} ]; then
          readarray -d , -t ips < <(printf '%s' "${vhost_whitelist[i]}")
          for ip in ${ips[@]}
          do
            echo "  allow ${ip};" >> ${location_config}
          done
          echo '  deny all;' >> ${location_config}
        fi
      fi
      echo "}" >> ${location_config}
    done
    if [[ $default_root_location -eq 1 ]]; then
      cat >> ${location_config} << EOF
location / {
  try_files \$uri \$uri/ /index.html;
}
EOF
    fi
  else
    if [ ! -z ${vhost_upstreams[i]} ]; then
      cat >> ${location_config} << EOF
location / {
  proxy_next_upstream error timeout http_503;
  proxy_pass https://${vhost_upstream_prefix}targets;
}
EOF
    fi
  fi

  ###
  # Users
  ###
  if [ ! -z ${vhost_users[i]} ]; then
    auth_config="/etc/nginx/conf.d${vhost_path_suffix}/htpasswd"
    rm -f ${auth_config}
    readarray -d , -t users < <(printf '%s' "${vhost_users[i]}")
    for user in ${users[@]}
    do
      parts=($(echo "$user" | tr ':' '\n'))
      _user=${parts[0]}
      _pass=${parts[1]}
      echo "### User for ${domain}: ${_user}"
      htpasswd -bc "${auth_config}" "${_user}" "${_pass}"
    done
  fi

  ###
  # CSP
  ###
  csp_config="/etc/nginx/conf.d${vhost_path_suffix}/csp.nginx"
  rm -f ${csp_config}
  touch ${csp_config}
  if [ ! -z "${vhost_csps[i]}" ]; then
    if [ "${vhost_csps[i]}" != "none" ]; then
      echo "### Add CSP header for ${domain}: ${vhost_csps[i]}"
      cat > ${csp_config} << EOF
add_header Content-Security-Policy "${vhost_csps[i]}" always;
EOF
    else
      echo "### None CSP header configured for ${domain}"
    fi
  else
    echo "### Adding default (most secure) CSP header"
    cat > ${csp_config} << EOF
add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
EOF
  fi

  ###
  # Ocsp stampling
  ###
  ocspstapling_config='/etc/nginx/conf.d/ocspstapling.nginx'
  if [[ "${vhost_disable_https[i]}" != 'true' ]] && [[ "${vhost_self_signed[i]}" != 'true' ]] && [[ "${vhost_disable_ocsp_stapling[i]}" != "true" ]]; then
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
done # END VHOSTS


# We empty the config and leave only certbot.conf
mkdir -p /tmp/nginx
mv /etc/nginx/conf.d/*.conf /tmp/nginx/.
mv /tmp/nginx/certbot.conf /etc/nginx/conf.d/.

echo "### Starting nginx in background"
nginx
if [ $? -ne 0 ]; then
  echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
  echo "### Nginx can not be started due to an error"
  exit 1
fi

echo "### Waiting for nginx to start ..."
wait -n


for i in "${!vhosts[@]}"
do
  vhost=${vhosts[i]}
  readarray -d , -t domains < <(printf '%s' "${vhost}")
  domain=${domains[0]}
  domains_md5=$(echo "${domains[@]}" | md5sum | awk '{print $1}')
  domains_hash_file="/etc/letsencrypt/${domain}.hash"
  last_domains_md5=''
  if [ -e ${domains_hash_file} ]; then
    last_domains_md5=$(cat ${domains_hash_file})
  fi
  domain_config_changed=0
  if [ "${domains_md5}" != "${last_domains_md5}" ]; then
    echo "### Domain config has changed, taking required actions..."
    echo "${domains_md5}" > ${domains_hash_file}
    domain_config_changed=1
  fi
  if [ "${vhost_disable_https[i]}" == "true" ]; then
    echo "### HTTPS is disabled for ${vhost}, let's skip generating certificates ..."
    # Remove the default certbot config that is listening on port 80
    # otherwise we have a conflicting configuration
    rm -f /etc/nginx/conf.d/certbot.conf
    continue
  fi
  if [ "${vhost_own_cert[i]}" == "true" ]; then
    echo "### Using own certificate for ${vhost} ..."
  else
    if [ "${vhost_self_signed[i]}" == 'true' ]; then
      echo "### Using self signed certificate for ${vhost} ..."
      # mkdir -p /etc/letsencrypt/rootCA
      mkdir -p /etc/letsencrypt/live/${domain}
      if [[ "${vhost_self_signed_renew[i]}" == 'true' ]] || [[ ! -e /etc/letsencrypt/live/${domain}/csr.conf ]]; then
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
      if [[ "${domain_config_changed}" -eq 1 ]] || [[ "${vhost_self_signed_renew[i]}" == 'true' ]] || [[ ! -e /etc/letsencrypt/live/${domain}/fullchain.pem ]]; then
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
      if [[ "${domain_config_changed}" -eq 1 ]] || [[ "${vhost_request_on_boot[i]}" == 'true' ]] || [[ ! -e /etc/letsencrypt/live/${domain}/fullchain.pem ]]; then
        rsa_key_size=4096
        if [[ "${vhost_use_bypass[i]}" == 'true' ]]; then
          if [ ! -d /etc/letsencrypt/accounts/api.buypass.com ]; then
            email=$(tmpmail -g)
            certbot register -m ${email} \
              --no-eff-email \
              --agree-tos \
              --server 'https://api.buypass.com/acme/directory'
          fi
          echo "### Requesting Buypass certificate for ${vhost} ..."
          certbot certonly --webroot -w /var/www/certbot \
            -d ${vhost} \
            --agree-tos \
            --server 'https://api.buypass.com/acme/directory'
        else
          echo "### Requesting Let's Encrypt certificate for ${vhost} ..."
          certbot certonly --webroot -w /var/www/certbot \
            --register-unsafely-without-email \
            -d ${vhost} \
            --rsa-key-size $rsa_key_size \
            --agree-tos \
            --force-renewal
        fi
      else
        echo "### No new certificate request needed for ${vhost} ..."
      fi
    fi
  fi
done # vhost done

# We move back the original config
mv /tmp/nginx/*.conf /etc/nginx/conf.d/.

# Reload nginx
nginx -s reload
echo "### Waiting for nginx to reload ..."
wait -n

if [[ "${SMNRP_ENABLE_ANALYTICS}" == 'true' ]]; then
  sh -c "/analyser.sh"
fi

echo "### Starting nginx reloader in background"
sh -c "/reloader.sh" &

if [ ! -z $@ ]; then
  $@
else
  # We start the certbot observer to check every 12h if a certificate has expired
  echo "### Starting certbot renewal in background"
  sh -c "/renewer.sh"
fi
