#!/usr/bin/env bash

# This directories must me there to watch the files inside
mkdir -p /etc/letsencrypt/live /etc/nginx/conf.d

while true
do
  info=$(inotifywait -r --exclude .swp -e create -e modify -e delete -e move /etc/letsencrypt/live)
  domain=$(echo ${info} | cut -d' ' -f1 | cut -d'/' -f5)
  if [ $? -ne 0 ]; then
    echo "### inotifywait exited with status != 0 ($?)."
    echo "### reloader will exit"
    exit 1
  else
    echo "### Change detected in /etc/letsencrypt/live ($?)."
  fi
  nginx -t
  if [ $? -eq 0 ]; then
    echo "### Detected certificate change for ${domain}."
    echo "### Executing: nginx -s reload"
    nginx -s reload
    echo "### Adding signal file to /signal/${domain}."
    mkdir -p /signal
    echo "DETECTED CERTIFICATE CHANGE" > /signal/${domain}
  else
    echo "### Errors detected in nginx config, not reloading."
  fi
done