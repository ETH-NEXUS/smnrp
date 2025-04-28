FROM nginx:1.26

# Define a volume for /etc/letsencrypt
# to make sure the requested certificates
# are persistent
VOLUME /etc/letsencrypt

# Define a volume for /var/log
# to make sure the analytics data
# is persistent
VOLUME /var/log

# Install the requirements
RUN apt-get update && apt-get install -y \
  certbot \
  python3-certbot-nginx \
  inotify-tools \
  wget \
  gpg \
  apache2-utils \
  jq \ 
  w3m \ 
  xclip

# Install goaccess
# RUN wget -O - https://deb.goaccess.io/gnugpg.key | gpg --dearmor | tee /usr/share/keyrings/goaccess.gpg >/dev/null && \
#   echo "deb [signed-by=/usr/share/keyrings/goaccess.gpg arch=$(dpkg --print-architecture)] https://deb.goaccess.io/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/goaccess.list && \
#   apt-get update
# RUN apt-get install -y goaccess
RUN apt-get install -y \
  build-essential \
  libmaxminddb-dev \
  libncursesw5-dev
RUN wget https://tar.goaccess.io/goaccess-1.9.4.tar.gz && \
  tar -xzvf goaccess-1.9.4.tar.gz && \
  cd goaccess-1.9.4/ && \
  ./configure --enable-utf8 --enable-geoip=mmdb && \
  make && \
  make install && \
  cd .. && rm -rf goaccess-1.9.4

# Install tmpmail
RUN curl -sL "https://git.io/tmpmail" > /usr/bin/tmpmail && chmod +x /usr/bin/tmpmail

# Clean up the apt cache
RUN apt-get clean autoclean && apt-get autoremove -y && rm -rf /var/lib/{apt,dpkg,cache,log}/

# Cerate the web root directory
RUN mkdir -p /web_root

# Copy an initial index html to the webroot
# normaly you would mount a directory
# to the webroot what will shadow this default
COPY ./nginx/index.html /usr/share/nginx/index.html
COPY ./nginx/background.jpg /usr/share/nginx/background.jpg
COPY ./nginx/favicon.ico /usr/share/nginx/favicon.ico

# Create the webroot for certbot
RUN mkdir -p /var/www/certbot

# Add the dh-params to the image
RUN mkdir -p /etc/letsencrypt
COPY ./ssl-dhparams.pem /usr/share/nginx/ssl-dhparams.pem
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
COPY ./smnrp_reset /smnrp_reset
RUN chmod 755 /entrypoint.sh /analyser.sh /reloader.sh /renewer.sh /smnrp_reset

# Copy over the geoip databases
COPY ./db /db

ENTRYPOINT [ "/entrypoint.sh" ]