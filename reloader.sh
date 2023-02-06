#!/usr/bin/env bash

# This directories must me there to watch the files inside
mkdir -p /etc/letsencrypt/live /etc/nginx/conf.d

while true
do
  inotifywait -r --exclude .swp -e create -e modify -e delete -e move /etc/letsencrypt/live
  if [ $? -ne 0 ]; then
    echo "### inotifywait exited with status != 1 ($?)."
    echo "### reloader will exit"
    exit 1
  else
    echo "### Change detected in /etc/letsencrypt/live ($?)."
  fi
  nginx -t
  if [ $? -eq 0 ]; then
    echo "### Detected Nginx change"
    echo "### Executing: nginx -s reload"
    nginx -s reload
  else
    echo "### Errors detected in nginx config, not reloading."
  fi
done