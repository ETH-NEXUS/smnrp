FROM nginx:mainline

# Install the requirements
RUN apt-get update && apt-get install -y \
  certbot \
  python3-certbot-nginx \
  inotify-tools

# Clean up the apt cache
RUN apt-get clean autoclean && apt-get autoremove -y && rm -rf /var/lib/{apt,dpkg,cache,log}/

# Cerate the web root directory
RUN mkdir -p /web_root
RUN mkdir -p /var/www/certbot

# Copy the nginx configurtion files
COPY ./nginx/nginx.conf /etc/nginx.conf
COPY ./nginx/conf.d /etc/nginx/conf.d

# Copy the entrypoint
COPY ./entrypoint.sh /entrypoint.sh
COPY ./reloader.sh /reloader.sh
RUN chmod 755 /entrypoint.sh /reloader.sh

ENTRYPOINT [ "/entrypoint.sh" ]