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
```

### `SMNRP_DOMAINS`

Define a comma separated list of domains you want to have included in the https certificate.

### `SMNRP_UPSTREAMS`

Define the upstream servers in a comma separated list. The upstreams can be referenced in the `SMNRP_LOCATIONS` as `targets`.

### `SMNRP_UPSTREAM_PROTOCOL`

Define the protocoll to be used to communicate with the upstreams. This can be ether `http` or `https`.

### `SMNRP_LOCATIONS`

Define additional locations you want to support. This is essential if you use `SMNRP` as a simple proxy for your web application. The definitions are comma separated and consists of two parts `path!alias|proxy_url`. An `alias` need to be configured as a path (e.g. `/usr/share/static`). A `proxy_url` need to be configured as a url (e.g. `https://targets/api/`). The two parts are separated by a `!`. 
Basically the translation inside the Nginx config is

- for an `alias`:

```nginx
location <path> {
  alias <alias>
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

### `SMNRP_SELF_SIGNED`

If set to `true` smnrp is generating self signed certificates instead of gathering it from Let's Encrypt.

### `SMNRP_SELF_SIGNED_RENEW`

If set to `true` smnrp will regenerate the self signed certificate on each start.

## Integration into `docker-compose`

To integrate `SMNRP` into docker compose to setup a reverse proxy to the application you just need to add the following part into you `docker-compose.yml`:

```yaml
version: "3"
volumes:
  web_root:
services:
  ws:
    image: ethnexus/smnrp
    volumes: 
      - "web_root:/web_root:ro"
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
