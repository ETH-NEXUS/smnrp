#!/usr/bin/env bash

while true
do 
  if [ "${SMNRP_SELF_SIGNED}" != 'true' ] && [ "${SMNRP_OWN_CERT}" != 'true' ]; then
    certbot renew 
  fi
  sleep 12h
done