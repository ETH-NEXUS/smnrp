# Secure Multifunctional Nginx Reverse Proxy

The _Secure Multifuctional Nginx Reverse Proxy (SMNRP)_ is a reverse proxy based on nginx.

![SMNRP](https://raw.githubusercontent.com/ETH-NEXUS/smnrp/main/img/SMNRP.png)

## Features

### HTTPS Certificates

- Automatic generation and renewal of https certificates ([using Let's Encrypt](https://letsencrypt.org/))
- Automatic generation of a self signed certificate
- Usage of custom certificates

### Usage options

- Load balancer to different locations
- Reverse proxy to a web application
- Virtual host support (new since version 2)

### Security features

- High baseline security
- Customized `Content-Security-Policy`
- OCSP stapling [:information_source:](https://www.ssls.com/knowledgebase/what-is-ocsp-stapling/)
- Basic authentication to specific locations

### Additional features

- Analytics website with traffic analytics
- Maintenance mode

## Getting started

SMNRP can be configured using only environment variables, what makes it ideal to implement into a configurable container. All possible configuration environment variables are described in this readme.

To integrate the SMNRP into your web application you just need to configure the environment variables (in the `.env` file).

Let's start with some examples.

## Examples

### Simple reverse proxy

To start with the most basic configuration to use `SMNRP` as a reverse proxy to a web application while requesting the certificates automatically from Let's Encrypt.

![Example1](https://raw.githubusercontent.com/ETH-NEXUS/smnrp/main/img/SMNRP_ex1.png)

```bash
SMNRP_DOMAINS=dom.org,www.dom.org
SMNRP_UPSTREAMS=api:5000
SMNRP_LOCATIONS=/api/!http://targets/api/,/api/static!/usr/share/static
```

In this example the domain names (`SMNRP_DOMAINS`) are provided. The first name in the comma separated list is used as the _common name (cn)_ in the certificate. The additional ones are configured as _Subject Alternative Names (SAN)_.

Only a single upstream (`SMNRP_UPSTREAMS`) needs to be configured. This _anonymous_ upstream can be referenced as `target` in the locations (`SMNRP_LOCATIONS`) section.

The locations (`SMNRP_LOCATIONS`) can be configured in a comma separated list where the parts are separated by `!`. In this example the `/api/` location will be _proxied_ (nginx: `proxy_pass`) to `http://targets/api/` and `/api/static` will be _aliased_ (nginx: `alias`) to `/usr/share/static`.

### Simple load balancing

The following example shows the load balancing mode.

![Example2](https://raw.githubusercontent.com/ETH-NEXUS/smnrp/main/img/SMNRP_ex2.png)

```bash
SMNRP_DOMAINS=dom.org,www.dom.org
SMNRP_UPSTREAMS=srv1.dom.org:443,srv2.dom.org:443
SMNRP_LOCATIONS=/api/!https://targets/api/,/api/static!/usr/share/static
```

In this scenario the certificates are requested from Let's Encrypt as in the first example. The traffic is then load balanced to two servers `srv1.dom.org` and `srv2.dom.org`. The load balancing is internally configured as:

```nginx
upstream targets {
  server srv1.dom.org:443 max_fails=3 fail_timeout=10s;
  keepalive 32;
  server srv2.dom.org:443 max_fails=3 fail_timeout=10s;
  keepalive 32;
}
```

The requests are equally distributed to the different targets. If one fails only the others are used. This mechanism can only be used for high availability scenarios **without** shared storage or shared state.

### Add virtual host support

![Example3](https://raw.githubusercontent.com/ETH-NEXUS/smnrp/main/img/SMNRP_ex3.png)

To enable virtual hosts you need to use the `|` separator in the config variables:

```bash
SMNRP_DOMAINS=dom.org,www.dom.org|otherdom.org
SMNRP_UPSTREAMS=|postman-echo.com:443
SMNRP_LOCATIONS=/!/web_root/dom.org/!t:a,/api/!https://postman-echo.com/get/|/api/!https://targets/get/
```

The configuration will take the order into account. First section is the first vhost (`dom.org`), second the second (`otherdom.org`) and so on. If you add vhost support for one config variable you need to add it for every other config variable as well except for `SMNRP_ENABLE_ANALYTICS` (this is a global setting).

In this example two vhosts are configured. **vhost1** does not have any upstream configured, where the upstream of **vhost2** is configured to be `postman-echo.com:443`. The first location for **vhost1** are configured as `/` to be _aliased_ (nginx: `alias`) to `/web_root/dom.org` as this is the directory inside SMNRP that is created to hold the files to be served for the vhost named `dom.org`. Additionally there are two flags configured for this location `t` and `a`. Those are described in details under the [Flags](####flags) section. The `/api/` location is _proxied_ (nginx: `proxy_pass`) to `https://postman-echo.com/get/`. The second vhost only _proxies_ the `/api/` location to `https://targets/get/`, what is basically the same as in vhost1 because the _upstream_ of vhost 2

## Configuration

### `SMNRP_DOMAINS`

(required) Define a _comma separated list_ of domains you want to have included in the https certificate. The fist entry is used as the _common name (cn)_ and the domain name in general, the subsequent names are used as _Subject Alternative Names (SAN)_.
If virtual hosts are configured the first entry is used as the folder name in the `/web_root/<fist entry>` directory.

### `SMNRP_UPSTREAMS`

(optional) Define the upstream servers in a _comma separated list_. Unnamed upstreams can be referenced in the `SMNRP_LOCATIONS` as `targets`. You can also name targets by prefixing them with `target_name!`. If you use named targets you can reference them in `SMNRP_LOCATIONS` by its `target_name`. If this setting is not given the `/web_root` or `/web_root/<vhost>` is served.

```bash
SMNRP_UPSTREAMS=api:5000,notebook!notebook:8888
```

### `SMNRP_LOCATIONS`

(optional) Define additional locations you want to support. This is essential if you use `SMNRP` as a simple proxy for your web application. The definitions are _comma separated_ and consists of two mandatory and an optional part separated by `!`.

```bash
SMNRP_LOCATIONS=path!alias|proxy_url[!flags]
```

The `path` is the url location that should be directed. A `path` need to be configured as the tail of the uri (e.g. `/api/`).

The `alias` is a local directory inside SMNRP, normally bind mounted. An `alias` need to be configured as a path (e.g. `/usr/share/static` or `/web_root/<vhost>`).

The `proxy_url` defines a target outside of the SMNRP context. It could be an external web application or another container. A `proxy_url` need to be configured as a url (e.g. `https://target_name/api/` where `target_name` of the unnamed upstreams is `targets`).

Additionally, flags can be configured using a `:` separated string.

The three parts are separated by a `!`.

#### Flags

- **t**:  Adds a `try_files` clause to an alias location. This must be used if the files in the target need to be served.
- **a**:  Adds a `auth_basic` clause to the location so that only `SMNRP_USERS` have access to it. `SMNRP_USERS` must be configured in order to make this working.
- **c**:  Sets the headers to disables the browser cache.
- **r**:  Returns a _permanent redirect_ (301) to the `alias` or `proxy_url`. This flag can not be mixed with other flags.

#### Example

```bash
SMNRP_LOCATIONS=/!/web_root/dom.org/!t:a,/api/!https://postman-echo.com/get/,/redirect/!/new-destination/!r
```

This example _aliases_ (nginx: `alias`) the `/` path to `/web_root/dom.org/`, adds a `try_files` clause as well as a `auth_basic` clause to
the location section. The `/api/` path is _proxied_ (nginx: `proxy_pass`) to `https://postman-echo.com/get/`

#### Translation to nginx config

Basically the translation inside the nginx config is

- for an `alias`:

```nginx
location <path> {
  alias <alias>;
  try_files $uri $uri/ /index.html;      <--[Only if flag 't' is set]
}
```

- for a `proxy_url`:

```nginx
location <path> {
  proxy_pass <proxy_url>;
}
```

- for `auth_basic`, only if flag `a` is set:

```nginx
location <path> {
  auth_basic "Authorization Required";
  auth_basic_user_file <path_to_user_pw_list>;   <--[Derived from 'SMNRP_USERS']
}
```

- for _permanent redirect_, only if flag `r` is set:

```nginx
location <path> {
  return 301 <alias|proxy_url>;
}
```

If you want to redirect to the configured unnamed upstream(s) you can use `targets` as the server name.

If you want to redirect to another container you need to use the _service name_ of the particular application.

If you only want to proxy to the configured upstreams (`SMNRP_UPSTREAMS`), just leave `SMNRP_LOCATIONS` empty.

### `SMNRP_REQUEST_ON_BOOT`

If set to `true` SMNRP requests a new certificate from Let's Encrypt on every boot. Do not force this - it leads to problems getting a certificate because of too many requests. This is meant to be used in case of troubleshooting.

### `SMNRP_SELF_SIGNED`

If set to `true` SMNRP is generating self signed certificates instead of gathering it from Let's Encrypt.

### `SMNRP_SELF_SIGNED_RENEW`

If set to `true` SMNRP will regenerate the self signed certificate on each start.

### `SMNRP_OWN_CERT`

If set to `true` SMNRP will not create any certificate but it requires the following two files to be mapped into the container (i.e. as docker read-only volume):

- `/etc/letsencrypt/live/${domain}/fullchain.pem`
- `/etc/letsencrypt/live/${domain}/privkey.pem`

Here is an example:

```yaml
  ...
  ws:
    image: ethnexus/SMNRP
    volumes:
      ...
      - /path/to/dom.org.fullchain.pem:/etc/letsencrypt/live/dom.org/fullchain.pem:ro
      - /path/to/dom.org.key.pem:/etc/letsencrypt/live/dom.org/privkey.pem:ro
```

> Replace the `${domain}` with the **first** domain name in `SMNRP_DOMAINS` comma separated list.

### `SMNRP_CSP`

You can define the `Content-Security-Policy` header. If this is not defined, the default (most secure) header is used:

```bash
default-src 'self' http: https: data: blob: 'unsafe-inline'
```

If you want to completely disable the `Content-Security-Policy` header set `SMNRP_CSP` to `none`:

```bash
SMNRP_CSP=none
```

It's often a good idea to set this to `none` to avoid unexprected access problems. It should only be set if you need to extensively secure your web application.

### `SMNRP_DISABLE_OCSP_STAPLING`

If `true` ocsp-stapling is disabled.

### `SMNRP_DISABLE_HTTPS`

If set to `true` SMNRP will completely ignore https for communication and only listen on port 80 to serve the resources.

### `SMNRP_USE_BUYPASS`

If `true` smnrp uses Buypass certificate service in case of Let's Encrypt

```bash
SMNRP_USE_BUYPASS=false
```

### `SMNRP_USERS`

A comma separated list of `user:password` combinations to be allowed to do basic authentication on targets with the `a` flag.

```bash
SMNRP_USERS=admin:admin,user:pass
```

### `SMNRP_ENABLE_ANALYTICS`

If `true` SMNRP is generating an analytics dashboard page based on [goaccess](https://goaccess.io/) at `analytics/dashboard.html`. To enable this feature set `SMNRP_ENABLE_ANALYTICS` to `true`, default is `false`.

## Virtual host configuration

To enable virtual hosts you need to use the `|` separator in the config variables:

```bash
SMNRP_DOMAINS=dom.org,www.dom.org|otherdom.org
SMNRP_UPSTREAMS=|postman-echo.com:443
SMNRP_LOCATIONS=/!/web_root/localhost/!t:a,/api/!https://postman-echo.com/get/|/api/!https://targets/get/
SMNRP_SELF_SIGNED=true|true
SMNRP_USERS=admin:secret,user1:xzy|user2:pass
```

The configuration will take the order into account. First section is **vhost1**, the second is **vhost2** and so on. If you add vhost support for one config variable you **must add it for every other config variable** as well except for `SMNRP_ENABLE_ANALYTICS` which is a global setting.

A vhost configuration may contain all configuration entries as a configuration without vhost support. The configuration that will be taken into account is selected by the url that is accessing SMNRP (default vhost behavior).

## Apply custom configurations

`SMNRP` also loads `*.nginx` files in the directory `/etc/nginx/conf.d/custom/*.nginx`. You can bind mount or copy a local directory including your custom configs to `/etc/nginx/conf.d/custom/`.

## Integration into `docker-compose`

To integrate `SMNRP` into docker compose to setup a reverse proxy to the application, you need to add the following part into you `docker-compose.yml`:

```yaml
volumes:
  web_root:
  smnrp_data:
services:
  ws:
    image: ethnexus/smnrp
    volumes: 
      - web_root:/web_root
      - smnrp_data:/etc/letsencrypt
      # - "./custom/configs:/etc/nginx/conf.d/custom"
    ports:
      - 80:80
      - 443:443
    env_file: .env
    restart: unless-stopped
    depends_on:
      - ui
      - api
  ui:
    ...
    volumes:
      - "web_root:/path/to/webapp"
    ...
  api:
    ...
```

Your web application files need to be generated into the docker volume `web_root` that needs to be mapped to `/web_root`. In case of vhosts it should be bind mounted to `/web_root/<vhost>`

Essential is the `smnrp_data` volume. It should **always** bind mounted to `/etc/letsencrypt`, otherwise SMNRP may create too many requests to Let's Encrypt and gets blocked for about 24h to request certificates. 
If you are using a local directory to bind mount `/etc/letsencrypt` (i.e. `./ssl:/etc/letsencrypt`) you must create the `ssl-dhparams.pem` in the root of this directory (i.e. `./ssl`) by using:

```bash
openssl dhparam -out ssl-dhparams.pem 4096 
```

## Maintenance mode

To enable the maintenance mode you need to touch the file `.maintenance` into the folder `/web_root` or `/web_root/<vhost>`. As long as the file exists `SMNRP` will return `503 Service unavailable` and displays a nice maintenance page.

### Change the maintenance page

To add a custom maintenance page you need to overwrite the file `/usr/share/nginx/html/error/maintenance.html`.

```yaml
...
  volumes:
    - ./my-maintenance.html:/usr/share/nginx/html/error/maintenance.html
```

### Script to enable, disable the maintenance mode

Here is a script that you could use to enable, disable the maintenance mode with one command (`maint.sh`):

```bash
#!/usr/bin/env bash

DC_EXEC="docker-compose -f docker-compose.yml -f docker-compose.prod.yml exec ws"

if [[ "$1" == "on" ]]; then
    ${DC_EXEC} sh -c 'touch /web_root/.maintenance'
elif [[ "$1" == "off" ]]; then
    ${DC_EXEC} sh -c 'rm -f /web_root/.maintenance'
else
    echo "Please specify 'on' or 'off'"
    exit 1
fi
```

## Restrict access

To enable basic authentication on selected targets you need to flag the locations with the `a` flag and define the
users and passwords using the `SMNRP_USERS` environment variable.

```bash
SMNRP_LOCATIONS=/!/web_root/!t:a
SMNRP_USERS=admin:admin,user:pass
```

This example restricts the access to the `/` location to the users `admin` with the password `admin` and the user `user` with the password `pass` using _Basic Authentication_.

### Change the Authorization Required page

To add a custom _Authorization Required_ page you need to overwrite the file `/usr/share/nginx/html/error/auth_required.html`.

```yaml
...
  volumes:
    - ./my-auth_required.html:/usr/share/nginx/html/error/auth_required.html
```

## Detect and handle certificate renewals on host

`SMNRP` is adding a file called like the domain for which the certificate update happened into the directory `/signal`. You can bind mount this directory and run a cronjob on your host os to detect changes. An example script:

```bash
#!/usr/bin/env bash

SIGNAL_DIR="/path/to/signal"
DOMAIN="domain.of.interest"

if [ -f "${SIGNAL_DIR}/${DOMAIN}" ]; then
    echo "##############"
    echo `date`
    rm -f "${SIGNAL_DIR}/${DOMAIN}"
    ### EXAMPLE to reload postfix
    postfix reload
    service dovecot reload
    ### you can add your own logic here
fi
```

The following entry can be added to the repository's owners crontab:

```crontab
* * * * * (sudo /path/to/scripts/certRenew.sh 2>&1) >> /path/to/logs/certRenew.log
```

## Configure hardening parameters

### `SMNRP_CLIENT_MAX_BODY_SIZE`

Set the `client_max_body_size`, default is `1m`. This must be set to support large file uploads through SMNRP.

```bash
SMNRP_CLIENT_MAX_BODY_SIZE=1m
```

### `SMNRP_SERVER_TOKENS`

Set the `server_tokens` parameter for this server, default is `off`.

```bash
SMNRP_SERVER_TOKENS=off
```

### `SMNRP_CLIENT_BODY_BUFFER_SIZE`

Set the `client_body_buffer_size` parameter for this server, default is `1k`. Nginx default would be `8k|16k`

```bash
SMNRP_CLIENT_BODY_BUFFER_SIZE=1k
```

### `SMNRP_LARGE_CLIENT_HEADER_BUFFERS`

Set the `large_client_header_buffers` parameter for this server, default is `2 1k`. Nginx default would be `4 8k`

```bash
SMNRP_LARGE_CLIENT_HEADER_BUFFERS=2 1k
```

## Reset smnrp

If you went into troubles because of too many different configuration changes, you may want to reset smnrp:

```bash
docker exec <smnrp-container> smnrp_reset
```