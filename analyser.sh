#!/usr/bin/env bash

ACCESS_LOG=/var/log/analytics/access.log

readarray -d , -t domains < <(printf '%s' "${SMNRP_DOMAINS}")
domain=${domains[0]}

mkdir -p /web_root/analytics

goaccess ${ACCESS_LOG} -o /web_root/analytics/dashboard.html \
  --log-format=COMBINED \
  --real-time-html \
  --addr=0.0.0.0 \
  --port=7890 \
  --ws-url=wss://${domain}:443/ws/ \
  --external-assets \
  --persist \
  --restore