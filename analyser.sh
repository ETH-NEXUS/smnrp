#!/usr/bin/env bash

readarray -d '|' -t vhosts < <(printf '%s' "${SMNRP_DOMAINS}")
for i in "${!vhosts[@]}"
do
  readarray -d , -t domains < <(printf '%s' "${vhosts[i]}")
  domain=${domains[0]}
  vhost_path_suffix=''
  if [ ${#vhosts[@]} -gt 1 ]; then
    vhost_path_suffix="/${domain}"
  fi
  access_log=/var/log${vhost_path_suffix}/access.log
  mkdir -p /web_root${vhost_path_suffix}/analytics
  mkdir -p /var/log${vhost_path_suffix}
  touch ${access_log}
  echo "### Starting analyser for ${domain}..."
  goaccess ${access_log} -o /web_root${vhost_path_suffix}/analytics/dashboard.html \
    --log-format=COMBINED \
    --real-time-html \
    --addr=0.0.0.0 \
    --port=789${i} \
    --ws-url=wss://${domain}:443/gows/ \
    --external-assets \
    --persist \
    --db-path /web_root${vhost_path_suffix}/analytics \
    --geoip-database /db/GeoLite2-City.mmdb \
    --restore &
done
