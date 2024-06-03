#!/usr/bin/env bash

ts_file='/etc/letsencrypt/last_renew.ts'
# ~12h
timeout=43190

readarray -d '|' -t vhosts < <(printf '%s' "${SMNRP_DOMAINS}")
readarray -d '|' -t vhost_own_cert < <(printf '%s' "${SMNRP_OWN_CERT}")
readarray -d '|' -t vhost_self_signed < <(printf '%s' "${SMNRP_SELF_SIGNED}")
while true
do
  renew=0
  for i in "${!vhosts[@]}"
  do
    # Check if there's at least one vhost with a let's encrypt certificate
    if [[ "${vhost_own_cert[i]}" != 'true' ]] && [[ "${vhost_self_signed[i]}" != 'true' ]]; then
      renew=1
      break
    fi
  done
  if [ $renew -eq 1 ]; then
    if [ ! -e ${ts_file} ]; then
      echo "$(date +%s)" > ${ts_file}
      last=0
    else
      last=$(cat ${ts_file})
    fi
    now=$(date +%s)
    diff=$(( $now - $last ))
    # we only renew to if last renew was ~12h ago
    if [ $diff -gt $timeout ]; then
      echo "Trying to renew certificate..."
      certbot renew
      echo "$(date +%s)" > ${ts_file}
    else
      pp_min=$(( ($timeout - $diff) / 60 ))
      pp_h=$(( ($timeout - $diff) / 60 / 60 ))
      if [ $pp_h -eq 0 ]; then
        echo "Postpone renewal for another ${pp_min}min..."
      else
        echo "Postpone renewal for another ${pp_h}h..."
      fi
    fi
  fi
  # we wait 12h until next renew
  sleep 12h
done