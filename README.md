# Secure Multifunctional Nginx Reverse Proxy

The _S_ ecure _M_ ultifuctional _N_ ginx _R_ everse _P_ roxy (SMNRP) is a reverse proxy based on Nginx that supports the following features:

- Automatic generation and renewal of https certificates ([using Let's Encrypt](https://letsencrypt.org/))
- Loadbalancer to different locations
- Reverse proxy to a web application

## Getting started

To integrate the SMNRP into your web application you just need to configure the following environment variables (in the `.env` file):

```bash
SMNRP_DOMAINS=domain.com,www.domain.com
SMNRP_UPSTREAMS=app.server1.com:443,app.server2.com:443
SMNRP_UPSTREAM_PROTOCOL=https
SMNRP_LOCATIONS=/api/!https://targets/api/,/api/static!/usr/share/static
SMNRP_SELF_SIGNED=false
SMNRP_SELF_SIGNED_RENEW=false
SMNRP_OWN_CERT=false
```

### `SMNRP_DOMAINS`

(required) Define a comma separated list of domains you want to have included in the https certificate.

### `SMNRP_UPSTREAMS`

(optional) Define the upstream servers in a comma separated list. The upstreams can be referenced in the `SMNRP_LOCATIONS` as `targets`. If this setting is not given the `/web_root` is served.

### `SMNRP_UPSTREAM_PROTOCOL`

(optional) Define the protocoll to be used to communicate with the upstreams. This can be ether `http` or `https`.

### `SMNRP_LOCATIONS`

(optional) Define additional locations you want to support. This is essential if you use `SMNRP` as a simple proxy for your web application. The definitions are comma separated and consists of two mandatory and an optional part:

```bash
path!alias|proxy_url[!flags]
``` 

An `alias` need to be configured as a path (e.g. `/usr/share/static`).

A `proxy_url` need to be configured as a url (e.g. `https://targets/api/`).

The flags is a `:` separated string with flags.

The three parts are separated by a `!`.

#### Flags

- **t**:  Adds a `try_files` clause to an alias location.

#### Translation to Nginx config

Basically the translation inside the Nginx config is

- for an `alias`:

```nginx
location <path> {
  alias <alias>
  try_files $uri $uri/ /index.html;      <--[Only if flag 't' is set]
}
```

- for a `proxy_url`:

```nginx
location <path> {
  proxy_pass <proxy_url>
}
```

If you want to redirect to the configured upstream(s) you can use `targets` as the server name. If you want to redirect to another docker contatiner you need to use the _service name_ of the particular application.
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
      - /etc/pki/tls/certs2022/careapp.ethz.ch.pem:/etc/letsencrypt/live/careapp.ethz.ch/fullchain.pem:ro
      - /etc/pki/tls/certs2022/careapp.ethz.ch.key:/etc/letsencrypt/live/careapp.ethz.ch/privkey.pem:ro
```

> Replace the `${domain}` with the first domain name in `SMNRP_DOMAINS`.
## Integration into `docker-compose`

To integrate `SMNRP` into docker compose to setup a reverse proxy to the application you just need to add the following part into you `docker-compose.yml`:

```yaml
version: "3"
volumes:
  web_root:
  smnrp_live:
services:
  ws:
    image: ethnexus/smnrp
    volumes: 
      - "web_root:/web_root:ro"
      - "smnrp_live:/etc/letsencrypt/live"
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
