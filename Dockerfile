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

# Copy an initial index html to the webroot
# normaly you would mount a directory
# to the webroot what will shadow this default
COPY ./nginx/index.html /web_root/index.html
COPY ./nginx/background.jpg /web_root/background.jpg

# Create the webroot for certbot
RUN mkdir -p /var/www/certbot

# Add the dh-params to the image
RUN mkdir -p /etc/letsencrypt
COPY ./ssl-dhparams.pem /etc/letsencrypt/ssl-dhparams.pem

# Copy the nginx configurtion files
COPY ./nginx/nginx.conf /etc/nginx/nginx.conf
COPY ./nginx/conf.d /etc/nginx/conf.d

# Copy the errorpages
RUN mkdir -p /usr/share/nginx/html/error
COPY ./nginx/errorpages/* /usr/share/nginx/html/error/.

# Copy the entrypoint
COPY ./entrypoint.sh /entrypoint.sh
COPY ./reloader.sh /reloader.sh
COPY ./renewer.sh /renewer.sh
RUN chmod 755 /entrypoint.sh /reloader.sh /renewer.sh

ENTRYPOINT [ "/entrypoint.sh" ]