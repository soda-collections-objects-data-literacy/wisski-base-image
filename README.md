# WissKI Base Image

A containerized WissKI (Wissenschaftliche KommunikationsInfrastruktur) environment built on Drupal with integrated triplestore connectivity, IIIF image serving, and semantic web capabilities.

## Prerequisites

- Triplestore with repository (e.g. [OpenGDB](https://github.com/FAU-CDI/open_gdb), [GraphDB](https://graphdb.ontotext.com/), or [Blazegraph](https://blazegraph.com/))
- Database (e.g. MariaDB or MySQL)
- Redis (recommended; the entrypoint configures Drupal to use it when `REDIS_HOST` is set)

## Overview

This Docker image provides a complete WissKI installation with:

- **Base image**: `drupal:11.3-php8.3-fpm-bookworm` (pinned via `DRUPAL_BASE_IMAGE_TAG`)
- **Web stack**: Nginx + PHP-FPM (not Apache)
- **WissKI**: Digital humanities platform for managing scholarly data
- **Immutable codebase**: Drupal core, modules, recipes, and Drush are baked at build time from the [drupal_packages](https://github.com/soda-collections-objects-data-literacy/drupal_packages) `wisski_base` manifests — no Composer calls at runtime
- **Triplestore integration**: SPARQL 1.1 adapter with default ontology import
- **IIIF**: IIPImage server (`iipsrv` 1.3) with memcached-backed tile cache
- **Security**: OpenID Connect SSO and optional reverse-proxy trust for Traefik/Varnish edges
- **Performance**: Redis cache backend, APCu, OPcache, and tuned PHP settings for WissKI workloads

Current production package manifest: **3.3.0** (see `WISSKI_PACKAGES_VERSION` in the Dockerfile).

## Published Images

Images are built and published to GitHub Container Registry on pushes to `2.x` / `3.x` branches and semver tags:

| Image | Purpose |
| --- | --- |
| `ghcr.io/soda-collections-objects-data-literacy/wisski-base-image-production` | Pinned semver manifest + lock file; OPcache on, no Xdebug |
| `ghcr.io/soda-collections-objects-data-literacy/wisski-base-image-development` | Floating major-line manifest (e.g. `3.x`); Xdebug on, dev OPcache settings |

Tagging:

- Semver git tags (e.g. `3.3.0`) produce matching image tags.
- `latest` is published only for the highest semver release tag.
- Branch pushes (e.g. `3.x`) produce an image tag matching the branch name.

## Architecture

```
┌─────────────────────────────────────────────┐
│  Container (tini → entrypoint.sh)           │
│                                             │
│  nginx :80  ──►  php-fpm (unix socket)      │
│       │                                     │
│       ├── /fcgi-bin/iipsrv.fcgi :9100 (IIIF)│
│       └── memcached :11211 (iipsrv cache)   │
└─────────────────────────────────────────────┘
         │              │              │
    MariaDB/MySQL    Redis         Triplestore
```

On boot the entrypoint starts PHP-FPM, memcached, and iipsrv, then runs nginx in the foreground. SIGTERM triggers a graceful shutdown of all services.

## Features

### Core Components

- Drupal 11.3 with PHP 8.3 FPM and Nginx
- WissKI modules, starter recipe, and default data model (baked into the image)
- SPARQL 1.1 triplestore adapter (`sparql11_with_pb`)
- Redis caching (PhpRedis extension + Drupal Redis module)
- ImageMagick, VIPS, and GD (with AVIF support) for image processing
- IIPImage server for high-resolution IIIF serving
- Baked JS libraries: WissKI Mirador integration, Colorbox, DOMPurify, DFG 3D Viewer

### Development & Administration

- Drush (symlinked from the baked vendor tree)
- Health Check module (`/health` endpoint)
- Single Content Sync for recipe content import
- Sophron MIME type guesser (enabled on install)
- Devel module (development images only)

### Security & Authentication

- OpenID Connect integration (Keycloak-compatible)
- SSO Bouncer for seamless authentication
- Trusted host pattern protection
- Optional reverse-proxy trust (`DRUPAL_PROXY_ADDRESSES`) for TLS-terminating edges
- Secure file permissions following Drupal guidelines

### Optional Integrations

- **Nextcloud**: WebDAV mount module when `NEXTCLOUD_*` variables are set
- **Keycloak SSO**: OpenID Connect client and role mappings when `OPENID_CONNECT_CLIENT_SECRET` is set

## Persistent Volumes

The Drupal codebase under `/opt/drupal` is immutable and recreated on every container build. Only runtime state persists in volumes:

| Path | Purpose |
| --- | --- |
| `/opt/drupal/web/sites` | `settings.php`, uploaded files, install markers |
| `/opt/drupal/private-files` (default) | Private files outside the web root |

Install progress is tracked via marker files in the sites volume (`.wisski-install-complete`, `.wisski-install-in-progress`). A failed install leaves the in-progress marker; wipe the database and sites volume to retry.

## Configuration

Configure the container with environment variables. See [`example-env`](example-env) for a starting template.

### General

| Variable | Description |
| --- | --- |
| `MODE` | `production` (default) or `development` — must match the image variant |
| `USER_GROUPS` | Comma-separated GID values; `www-data` is added to `g_<gid>` on every boot |

### Database

| Variable | Description |
| --- | --- |
| `DB_DRIVER` | Database driver (e.g. `mysql`) |
| `DB_HOST` | Database hostname |
| `DB_PORT` | Database port (default `3306`) |
| `DB_NAME` | Database name |
| `DB_USER` | Database username |
| `DB_PASSWORD` | Database password |

### Drupal

| Variable | Description |
| --- | --- |
| `DRUPAL_DOMAIN` | Public hostname (used for IIIF and 3D viewer URLs) |
| `DRUPAL_SITE_NAME` | Site display name |
| `DRUPAL_USER` | Admin username (account is created as `admin` during `drush si`) |
| `DRUPAL_PASSWORD` | Admin password |
| `DRUPAL_LOCALE` | Install locale (e.g. `en`) |
| `DRUPAL_TRUSTED_HOSTS` | Pipe-separated trusted host regex patterns (e.g. `'^localhost$|^127\.0\.0\.1$'`) |
| `DRUPAL_PRIVATE_FILES_DIR` | Private files path (default `/opt/drupal/private-files`) |
| `DRUPAL_PROXY_ADDRESSES` | Reverse proxy trust: unset/`none` (default), `auto` (detect container CIDRs), or pipe-separated CIDRs |

### Redis

| Variable | Description |
| --- | --- |
| `REDIS_HOST` | Redis hostname (required) |
| `REDIS_PORT` | Redis port (default `6379`) |

### WissKI

| Variable | Description |
| --- | --- |
| `WISSKI_DEFAULT_GRAPH` | Full URI of the default graph (e.g. `http://my.institution.edu/data/`) |
| `WISSKI_STARTER_VERSION` | Non-empty = apply the WissKI starter recipe on first install |
| `WISSKI_DEFAULT_DATA_MODEL_VERSION` | Non-empty = install triplestore adapter, import ontology, and apply the default data model recipe |

Module and recipe versions are determined at **image build time** from the `drupal_packages` manifest. The `WISSKI_*_VERSION` variables are apply flags only; they do not select package versions.

### Triplestore

| Variable | Description |
| --- | --- |
| `TS_READ_URL` | SPARQL query endpoint |
| `TS_WRITE_URL` | SPARQL update endpoint |
| `TS_REPOSITORY` | Repository name |
| `TS_USERNAME` / `TS_PASSWORD` | Basic authentication (when not using a token) |
| `TS_TOKEN` | Token authentication (alternative to username/password) |

Either `TS_TOKEN` or both `TS_USERNAME` and `TS_PASSWORD` must be set.

### OpenID Connect / Keycloak (optional)

When `OPENID_CONNECT_CLIENT_SECRET` is set, all of the following are required:

| Variable | Description |
| --- | --- |
| `KEYCLOAK_URL` | Keycloak base URL (e.g. `https://keycloak.example.com`) |
| `KEYCLOAK_REALM` | Realm name |
| `KEYCLOAK_ADMIN_GROUP` | Keycloak group mapped to the `administrator` role |
| `KEYCLOAK_USER_GROUP` | Keycloak group mapped to the `wisski_user` role |

### Nextcloud (optional)

| Variable | Description |
| --- | --- |
| `NEXTCLOUD_BASE_URL` | Nextcloud server URL |
| `NEXTCLOUD_LOGIN_NAME` | Service account login |
| `NEXTCLOUD_APP_PASSWORD` | App password for WebDAV sync |

## Initial Setup Process

On first startup (when no install marker exists), the container will:

1. Wait for the database to become reachable
2. Install Drupal via Drush (`drush si`)
3. Configure trusted hosts, private files, and Redis settings
4. Enable core modules (health check, single content sync, sophron guesser)
5. Create the `wisski_user` role
6. Configure OpenID Connect and SSO Bouncer (if Keycloak credentials provided)
7. Enable Nextcloud WebDAV mount (if Nextcloud credentials provided)
8. Apply the WissKI starter recipe (if `WISSKI_STARTER_VERSION` is set)
9. Install the triplestore adapter, import the default ontology, and apply the default data model recipe (if `WISSKI_DEFAULT_DATA_MODEL_VERSION` is set)
10. Configure IMCE profiles, Redis module, reverse proxy trust, and secure permissions
11. Write the install-complete marker

This process may take several minutes. The Docker health check allows a 30-minute start period to accommodate first-boot installation.

## Image Upgrades

When a new image ships a different package set version, the entrypoint runs `drush updatedb` on boot and records the new version in the sites volume. Only `web/sites` and private files need to be preserved across upgrades; the codebase is replaced by the new image.

## Health Checks

The image includes a Docker `HEALTHCHECK` that probes:

- `/health` — Health Check module endpoint (no authentication required)

Detailed system status is available at `/admin/reports/status` (requires authentication).

## Troubleshooting

### Container won't start

- Check database connectivity and credentials
- Verify the triplestore is accessible
- Review container logs: `docker logs <container-name>`

### Permission errors

- Ensure mounted volumes have correct ownership (`www-data`, UID/GID `33:33`)
- Writable paths are `web/sites`, `web/sites/default/files`, and the private files directory

### Slow startup

- Initial installation downloads ontology data and imports content
- Subsequent startups are much faster
- Monitor progress: `docker logs -f <container-name>`

### Failed installation

If a previous attempt did not finish, the container exits with an error referencing `.wisski-install-in-progress`. Wipe the database and sites volume, then recreate the container.

### Database connection issues

- Verify the database server is running and reachable from the container network
- Confirm credentials and that the database exists

### Debugging

Enable verbose logging:

```bash
docker exec -it <container-name> drush config-set system.logging error_level verbose
```

Access the container shell:

```bash
docker exec -it <container-name> bash
```

Check system status:

```bash
docker exec -it <container-name> drush status
```

Development images run with `set -ex` in the entrypoint and include Xdebug 3.4.

## Development

### Building the Image

```bash
git clone git@github.com:soda-collections-objects-data-literacy/wisski-base-image.git
cd wisski-base-image
docker build -t wisski-base-image .
```

Production build with a specific package manifest:

```bash
docker build \
  --build-arg MODE=production \
  --build-arg WISSKI_PACKAGES_VERSION=3.3.0 \
  -t wisski-base-image:3.3.0 .
```

Development build (latest compatible packages from the `3.x` line, Xdebug enabled):

```bash
docker build \
  --build-arg MODE=development \
  --build-arg WISSKI_PACKAGES_LINE=3.x \
  -t wisski-devel-image .
```

### Build Arguments

| Argument | Default | Description |
| --- | --- | --- |
| `DRUPAL_BASE_IMAGE_TAG` | `11.3-php8.3-fpm-bookworm` | Upstream Drupal image tag |
| `MODE` | `production` | `production` or `development` |
| `WISSKI_PACKAGES_VERSION` | `3.3.0` | Semver manifest path for production builds |
| `WISSKI_PACKAGES_LINE` | `3.x` | Major-line manifest path for development builds |
| `IIPSRV_VERSION` | `iipsrv-1.3` | IIPImage server git tag |

### Environment File

Copy and modify the example environment file for local testing or compose stacks:

```bash
cp example-env .env
# Edit .env with your settings
```

This repository does not include a `docker-compose.yml`; use it together with a stack definition (e.g. [wisski-base-stack](https://github.com/soda-collections-objects-data-literacy/wisski-base-stack)) or your own compose file.

### Extending the Image

Because the codebase is baked at build time, custom modules should be added in a derived Dockerfile **before** the image is used in production:

```dockerfile
FROM ghcr.io/soda-collections-objects-data-literacy/wisski-base-image-production:3.3.0

# Re-bake with additional packages from your own composer manifest,
# or copy custom configuration into /var/configs/.
```

For runtime-only configuration, mount volumes for `web/sites` and private files, and pass environment variables.

## Performance Tuning

### PHP Configuration

The image ships tuned PHP settings (`zz-wisski-recommended.ini`):

- Memory limit: 1 GB
- Max execution time: 300 seconds
- Upload/post size: 512 MB
- OPcache enabled (production settings by default)

### Redis Caching

When `REDIS_HOST` is set, the entrypoint includes `/var/configs/redis.settings.php` in `settings.php` and enables the Redis module. Redis is used as the default cache backend (form bin stays on the database). See the [Drupal Redis documentation](https://project.pages.drupalcode.org/redis/) for advanced tuning.

### Database Optimization

For production use, consider:

- Increasing database memory allocation
- Using read replicas for heavy read workloads
- Placing Varnish or another HTTP cache in front of the container (page cache max-age is set to 5 minutes on install)

## Security Considerations

- Change default passwords before production use
- Use strong database and triplestore credentials
- Configure HTTPS at the reverse proxy; set `DRUPAL_PROXY_ADDRESSES` when behind Traefik or similar
- Keep images updated — package versions are pinned per release tag
- Implement proper backup strategies for the database and `web/sites` volume
- Monitor container and application logs

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE.md](LICENSE.md) for details.

## Support and Contributing

### Getting Help

- [WissKI documentation](https://wiss-ki.eu/)
- Container logs for error messages
- Drupal and WissKI community forums

### Contributing

- Report issues through the [GitHub issue tracker](https://github.com/soda-collections-objects-data-literacy/wisski-base-image/issues)
- Submit pull requests for improvements
- See [CHANGELOG.md](CHANGELOG.md) for release history

### Versioning

This project follows semantic versioning. Stable releases are tagged (e.g. `3.3.0`). The `3.x` branch receives ongoing development builds.

---

**Note**: Production deployments should use the `wisski-base-image-production` image with pinned semver tags, HTTPS at the edge, and secrets managed outside the image.
