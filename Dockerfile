FROM nginx:1.24-bullseye

# Define a volume for /etc/letsencrypt/live
# to make sure the requested certificates
# are persistent
VOLUME /etc/letsencrypt/live
VOLUME /var/log/analytics

# Install the requirements
RUN apt-get update && apt-get install -y \
  certbot \
  python3-certbot-nginx \
  inotify-tools \
  wget \
  gpg \
  apache2-utils

# Install goaccess
RUN wget -O - https://deb.goaccess.io/gnugpg.key | gpg --dearmor | tee /usr/share/keyrings/goaccess.gpg >/dev/null && \
  echo "deb [signed-by=/usr/share/keyrings/goaccess.gpg arch=$(dpkg --print-architecture)] https://deb.goaccess.io/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/goaccess.list && \
  apt-get update
RUN apt-get install -y goaccess

# Clean up the apt cache
RUN apt-get clean autoclean && apt-get autoremove -y && rm -rf /var/lib/{apt,dpkg,cache,log}/

# Cerate the web root directory
RUN mkdir -p /web_root

# Copy an initial index html to the webroot
# normaly you would mount a directory
# to the webroot what will shadow this default
COPY ./nginx/index.html /web_root/index.html
COPY ./nginx/background.jpg /web_root/background.jpg
COPY ./nginx/favicon.ico /web_root/favicon.ico

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

# Preparation for analytics
RUN mkdir -p /var/log/analytics

# Copy the entrypoint
COPY ./entrypoint.sh /entrypoint.sh
COPY ./analyser.sh /analyser.sh
COPY ./reloader.sh /reloader.sh
COPY ./renewer.sh /renewer.sh
RUN chmod 755 /entrypoint.sh /analyser.sh /reloader.sh /renewer.sh

ENTRYPOINT [ "/entrypoint.sh" ]