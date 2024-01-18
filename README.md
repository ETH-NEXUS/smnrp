# Secure Multifunctional Nginx Reverse Proxy

The _S_ ecure _M_ ultifuctional _N_ ginx _R_ everse _P_ roxy (SMNRP) is a reverse proxy based on Nginx that supports the following features:

- Automatic generation and renewal of https certificates ([using Let's Encrypt](https://letsencrypt.org/))
- Automatic generation of a self signed certificate
- Usage of custom certificates
- Load balancer to different locations
- Reverse proxy to a web application
- High baseline security
- Maintenance mode
- Basic authentication to specific locations
- Customized `Content-Security-Policy`
- OCSP stapling [(?)](https://www.ssls.com/knowledgebase/what-is-ocsp-stapling/)
- Analytics website with traffic analytics
- Virtual host support (new in version 2)

## Getting started

To integrate the SMNRP into your web application you just need to configure the following environment variables (in the `.env` file):

To start with the most basic configuration to just reverse proxy a web application you can configure the following:

```bash
SMNRP_DOMAINS=domain.com,www.domain.com
SMNRP_UPSTREAMS=api:5000
SMNRP_LOCATIONS=/api/!http://targets/api/,/api/static!/usr/share/static
SMNRP_SELF_SIGNED=false
SMNRP_SELF_SIGNED_RENEW=false
SMNRP_OWN_CERT=false
```

The following example shows the load balancing mode:

```bash
SMNRP_DOMAINS=domain.com,www.domain.com
SMNRP_UPSTREAMS=app.server1.com:443,app.server2.com:443s
SMNRP_LOCATIONS=/api/!https://targets/api/,/api/static!/usr/share/static
SMNRP_SELF_SIGNED=false
SMNRP_SELF_SIGNED_RENEW=false
SMNRP_OWN_CERT=false
```

### `SMNRP_DOMAINS`

(required) Define a comma separated list of domains you want to have included in the https certificate.

### `SMNRP_UPSTREAMS`

(optional) Define the upstream servers in a comma separated list. Unnamed upstreams can be referenced in the `SMNRP_LOCATIONS` as `targets`. You can also name targets by prefixing them with `target_name!`. If you use named targets you can reference them in `SMNRP_LOCATIONS` by its `target_name`. If this setting is not given the `/web_root` is served.

```bash
SMNRP_UPSTREAMS=api:5000,notebook!notebook:8888
```

### `SMNRP_LOCATIONS`

(optional) Define additional locations you want to support. This is essential if you use `SMNRP` as a simple proxy for your web application. The definitions are comma separated and consists of two mandatory and an optional part:

```bash
SMNRP_LOCATIONS=path!alias|proxy_url[!flags]
```

An `alias` need to be configured as a path (e.g. `/usr/share/static`).

A `proxy_url` need to be configured as a url (e.g. `https://targets/api/`).

The flags is a `:` separated string with flags.

The three parts are separated by a `!`.

#### Flags

- **t**:  Adds a `try_files` clause to an alias location.
- **a**:  Adds a `auth_basic` clause to the location so that only `SMNRP_USERS` have access to it.

#### Example

The following example routes the `/` location to `/`, adds a `try_files` clause as well as a `auth_basic` clause to
the location section. The `/api/` location is `proxy_pass`ed to _https://postman-echo.com/get/_

```bash
SMNRP_LOCATIONS=/!/!t:a,/api/!https://postman-echo.com/get/
```

#### Translation to Nginx config

Basically the translation inside the Nginx config is

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

- for `auth_basic`:

```nginx
location <path> {
  auth_basic "Authorization Required";
  auth_basic_user_file <path_to_user_pw_list>;
}
```

If you want to redirect to the configured unnamed upstream(s) you can use `targets` as the server name. If you want to redirect to another docker contatiner you need to use the _service name_ of the particular application.
If you only want to proxy to other servers, just leave `SMNRP_LOCATIONS` empty.

### `SMNRP_REQUEST_ON_BOOT`

If set to `true` smnrp requests a new certificate from Let's Encrypt on every boot.

### `SMNRP_SELF_SIGNED`

If set to `true` smnrp is generating self signed certificates instead of gathering it from Let's Encrypt.

### `SMNRP_SELF_SIGNED_RENEW`

If set to `true` smnrp will regenerate the self signed certificate on each start.

### `SMNRP_OWN_CERT`

If set to `true` smnrp will not create any certificate but it requires the following two files to be mapped into
the container (i.e. as docker read-only volume):

- `/etc/letsencrypt/live/${domain}/fullchain.pem`
- `/etc/letsencrypt/live/${domain}/privkey.pem`

Here is an example:

```yaml
  ...
  ws:
    image: ethnexus/smnrp
    volumes:
      ...
      - /etc/pki/tls/certs2022/domain.com.pem:/etc/letsencrypt/live/domain.com/fullchain.pem:ro
      - /etc/pki/tls/certs2022/domain.com.key:/etc/letsencrypt/live/domain.com/privkey.pem:ro
```

> Replace the `${domain}` with the first domain name in `SMNRP_DOMAINS`.

### `SMNRP_CSP`

You can define the `Content-Security-Policy` header. If this is not defined the default (most secure) header is used:

```bash
default-src 'self' http: https: data: blob: 'unsafe-inline'
```

If you want to completely disable the `Content-Security-Policy` header set `SMNRP_CSP` to `none`:

```bash
SMNRP_CSP=none
```

### `SMNRP_CLIENT_MAX_BODY_SIZE`

You can set the nginx servers global `client_max_body_size`. Default is `1m`.

```bash
SMNRP_CLIENT_MAX_BODY_SIZE=1m
```

### `SMNRP_ENABLE_ANALYTICS`

If `true` smnrp is generating an analytics dashboard page based on [goaccess](https://goaccess.io/) in at `analytics/dashboard.html`. To enable this feature set `SMNRP_ENABLE_ANALYTICS` to `true`, default is `false`.

### `SMNRP_USERS`

A comma separated list of `user:password` combinations to be allowed to do basic authentication on targets with the `a` flag.

```bash
SMNRP_USERS=admin:admin,dave:pass
```

## Add virtual host support

To enable virtual hosts you need to use the `|` separator in the config variables:

```bash
SMNRP_DOMAINS=domain.com,www.domain.com|otherdomain.com
SMNRP_UPSTREAMS=|postman-echo.com:443
SMNRP_LOCATIONS=/!/web_root/localhost/!t:a,/api/!https://postman-echo.com/get/|/api/!https://targets/get/
SMNRP_SELF_SIGNED=true|true
SMNRP_USERS=admin:secret,user1:xzy|user2:pass
```

The configuration will take the order into account. First section is the first vhost, second the second and so on. If you add vhost support for one config variable you need to add it for every other config variable as well except for `SMNRP_ENABLE_ANALYTICS`.

## Apply custom configurations

`SMNRP` also loads `*.nginx` files in the directory `/etc/nginx/conf.d/custom/*.nginx`. You can bind mount or copy a local directory including your custom configs to `/etc/nginx/conf.d/custom`.

## Integration into `docker-compose`

To integrate `SMNRP` into docker compose to setup a reverse proxy to the application you just need to add the following part into you `docker-compose.yml`:

```yaml
version: "3"
volumes:
  web_root:
  smnrp_data:
services:
  ws:
    image: ethnexus/smnrp
    volumes: 
      - "web_root:/web_root:ro"
      - "smnrp_data:/etc/letsencrypt"
      - "./custom/configs:/etc/nginx/conf.d/custom"
    ports:
      - "80:80"
      - "443:443"
    env_file: .env
    restart: unless-stopped
    depends_on:
      - ui
      - api
  ui:
    ...
    volumes:
      - "web_root:/path/to/dist"
    ...
  api:
    ...
```

Your web application files need to be generated into the docker volume `web_root` that needs to be mapped to `/web_root`. 

Essential is the `smnrp-data` volume. You should always bind mount this one to `/etc/letsencrypt` otherwise smnrp may create too many requests to let's encrypt.

## Maintenance mode

To enable the maintenance mode you need to touch the file `.maintenance` into the folder `/web_root`. As long as the file exists `smnrp` will return `503 Service unavailable` and displays a nice maintenance page.

### Script to enable, disable the maintenance mode

Here is a script that you could use to enable, disable the maintenance mode with one command:

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

### Change the maintenance page

To add a custom maintenance page you need to overwrite the file `/usr/share/nginx/html/error/maintenance.html`.

```yaml
...
  volumes:
    - ./my-maintenance.html:/usr/share/nginx/html/error/maintenance.html
```

## Restrict access

To enable basic authentication on selected targets you need to flag the locations with the `a` flag and define the
users and passwords using the `SMNRP_USERS` environment variable.

To add a custom _Authorization Required_ page you need to overwrite the file `/usr/share/nginx/html/error/auth_required.html`.

```yaml
...
  volumes:
    - ./my-auth_required.html:/usr/share/nginx/html/error/auth_required.html
```

