# Changelog

## 3.x 
### Added
- reverse proxy: optional `DRUPAL_PROXY_ADDRESSES=auto` detects trusted proxy CIDRs from container network interfaces on install and on every boot (syncs `settings.php` for existing sites).
- `config/drupal/sync-reverse-proxy.sh` and `config/drupal/lib/reverse-proxy.py` (installed to `/usr/local/bin/` and `/usr/local/lib/wisski/`); entrypoint delegates to the script.

### Changed
- reverse proxy is opt-in: unset/`none` skips configuration (default in the image); stacks behind Traefik set `DRUPAL_PROXY_ADDRESSES=auto` explicitly (e.g. wisski-base-stack).
- `none` removes an existing reverse proxy block from `settings.php` on boot.
- development images resolve packages from `wisski_base/development/<line>/composer.json` (e.g. `3.x`) via `composer update` without a committed lock file; production still uses semver manifests with lock files under `wisski_base/production/<version>/`.
- add `WISSKI_PACKAGES_LINE` build arg for development builds; CI derives the line from the git branch name or major version of release tags.

### Files Modified
- `Dockerfile`: split production (`composer install` + lock) and development (`composer update`, installed.json hash in `.wisski-packages-version`) manifest resolution.
- `.github/workflows/build-image.yml`: pass `WISSKI_PACKAGES_LINE` for development matrix builds.

## 3.0.0 [2026-06-10]

### Changed
- rename Dockerfile build arg `DRUPAL_VERSION` to `DRUPAL_BASE_IMAGE_TAG` to avoid confusion with the upstream Drupal image `ENV DRUPAL_VERSION` (core semver).
- change CI image tagging: `latest` is published only when building the highest semver git release tag; branch pushes publish an image tag matching the git branch name (e.g. `3.x`, `2.x`).
- remove duplicate `DRUPAL_VERSION` and `DEFAULT_PACKAGES_VERSION` from CI; branch builds rely on Dockerfile `ARG` defaults, tag builds pass `WISSKI_PACKAGES_VERSION` from the git tag.

### Added
- enable `sophron_guesser` on install and on every boot for existing sites so imagemagick uses Sophron MIME type guessing instead of Drupal core defaults.
- add `WISSKI_PACKAGES_VERSION` build arg: the whole Drupal codebase (core, modules, recipes, drush) is baked at build time from the versioned composer.json/composer.lock in the drupal_packages repo (`wisski_base/<mode>/<version>`); the image version mirrors the manifest version.
- add automatic `drush updatedb` on boot when the baked package set version differs from the version recorded in the sites volume.

### Changed
- change codebase to immutable: remove all runtime composer calls from the entrypoint (`composer require`, recipe-unpack, minimum-stability); modules are only enabled via `drush en` and recipes applied from the baked `recipes/` directory. `WISSKI_STARTER_VERSION` and `WISSKI_DEFAULT_DATA_MODEL_VERSION` now act as apply flags only.
- change volume layout (breaking): only `web/sites` and private files persist; the `drupal-root` volume of 2.x is no longer compatible (fresh installs, or manually migrate `web/sites` and private files into the new volumes).
- move private files outside the web root to `/opt/drupal/private-files` (default for `DRUPAL_PRIVATE_FILES_DIR`); replaces `/var/private-files`.
- move install marker files into the sites volume so they survive container recreation.
- move `USER_GROUPS` group setup out of the install-once gate so groups are re-created on every boot (`/etc/group` is ephemeral).
- remove `testing_package_manager` and `package_manager_rsync_path` settings (instances do not manage packages).
- add graceful shutdown in entrypoint: trap SIGTERM/SIGINT, quit nginx, then stop php-fpm (SIGQUIT), memcached, and iipsrv before exit.
- add `STOPSIGNAL SIGTERM` and explicit `curl` package for the health check in the runtime image.

### Changed
- change Dockerfile to a two-stage build: compile PHP extensions and iipsrv in `builder`, copy only binaries and runtime libraries into the final image (drops autoconf, lib*-dev, and other toolchain packages).
- pin `DRUPAL_VERSION` default to `11.3-php8.3-fpm-bookworm` (was floating `php8.3-fpm-bookworm`); CI passes the same tag via `build-image.yml`.
- move xdebug compile to the builder stage; runtime only copies the ini when `MODE=development`.

### Fixed
- fix duplicate APCu load warning by not enabling apcu twice (pecl only in builder; zz-apcu-custom.ini enables it at runtime).