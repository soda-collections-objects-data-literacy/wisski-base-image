# Changelog

## [Unreleased]

## [4.0.0]

### Changed
- **Breaking:** build from `php:8.3-fpm-bookworm` instead of `drupal:11.3-php8.3-fpm-bookworm`; the Drupal codebase was already fully baked from the drupal_packages manifest, so the drupal base only provided PHP tooling. Build arg `DRUPAL_BASE_IMAGE_TAG` is renamed to `PHP_BASE_IMAGE_TAG` (default `8.3-fpm-bookworm`). The upstream `drupal:11.3-php8.3-*` tag is no longer maintained; pinning the php image directly removes that dead coupling.
- restructure the Dockerfile into four stages: `ext-builder` (PHP extensions), `iipsrv-builder` (compiles in parallel, independent of PHP), `codebase` (bakes `/opt/drupal`), and the runtime image.
- bake `/opt/drupal` as `www-data` with umask 022 in the `codebase` stage: every file is born with correct ownership and modes (dirs 755, files 644, vendor executables preserved by composer). Removes the recursive `chown -R`, the whole-tree `find … chmod`, and the vendor shebang scan (~5 min of build time), and ships `/opt/drupal` in a single layer (image ~700 MB smaller).
- use a BuildKit cache mount for the composer cache instead of `composer clear-cache`; local rebuilds reuse downloaded packages.
- entrypoint privilege separation: all `drush`/`composer` install and update steps run as `www-data` (via `runuser`); root only handles `USER_GROUPS` setup, guarded non-recursive first-boot chown of the volume mount points, and service startup. Install-time files (`settings.php`, `sites/default/files`) are created www-data-owned by construction.
- `set-permissions.sh` shrinks to chmod-only on fixed paths (`settings.php` 444, `sites/default` 555); no recursive `chown`/`find` walks. The per-boot recursive `chown -R`/`chmod -R` on `COMPOSER_HOME` is replaced by a guarded top-level check.
- php-fpm pool tuning (`pm.max_children = 15`) now applies to development images too (renamed `zz-wisski-production.conf` → `zz-wisski-pool.conf`), so staging instances show production-like concurrency instead of capping at 5 workers.
- PHP session store host is no longer hardcoded: `session.save_path` uses `${REDIS_HOST}:${REDIS_PORT}` (ini env substitution), aligning sessions with the cache backend configuration in `redis.settings.php`.

### Added
- explicit `docker-php-ext-install pdo_mysql pdo_pgsql zip` and `libicu-dev`/`libicu72` (previously inherited from the drupal base image); `iproute2` and `python3` are installed explicitly for `sync-reverse-proxy.sh`.
- build-time sanity layer: fails the build if a PHP extension is missing or an extension shared-library dependency is unresolved (`ldd` check).
- `config/php-fpm/zzz-wisski-socket.conf`: php-fpm UNIX socket configuration as a dedicated override file.

### Fixed
- php-fpm listened on TCP 9000 instead of the UNIX socket (nginx 502 on `/health`): the old `sed` targeted `zz-docker.conf`, but current php images define `listen = 9000` in a different file, so it silently matched nothing. The socket is now set by `zzz-wisski-socket.conf`, which sorts last and always wins.
- image healthcheck sends `Host: ${DRUPAL_DOMAIN}` (falls back to `localhost`), so standalone containers no longer report unhealthy due to the trusted-host 400.
- pre-create `/var/log/xdebug/xdebug.log` as `www-data:www-data 664`: the root-run php-fpm master otherwise created it root-owned and the workers logged "File could not be opened" on every debug-triggered request.

### Removed
- `config/mysqli/zz-mysqli-recommended.ini`: the `mysqli` extension is not installed (Drupal uses `pdo_mysql`), so the settings were silently ignored.
- `config/apache/`: leftovers from the 2.x Apache era; the image is nginx-only.
- inert `opcache.preload_user` from both opcache profiles (meaningless without `opcache.preload`).

### Files Modified
- `Dockerfile`: four-stage build on the php base image; www-data codebase bake; sanity checks; healthcheck Host header.
- `entrypoint.sh`: `runuser`-based privilege drop for drush/composer; guarded non-recursive mount-point ownership fixes.
- `config/drupal/set-permissions.sh`: chmod-only lockdown of generated settings files.
- `config/php-fpm/zzz-wisski-socket.conf`, `config/php-fpm/zz-wisski-pool.conf` (renamed): new/renamed.
- `config/redis/zz-redis-custom.ini`: env-driven session store, documented lock timings (5 ms retry wait, not 5 s).
- `config/opcache/zz-opcache-recommended-{dev,prod}.ini`: drop inert preload_user.

## [3.8.0]

### Fixed
- `WISSKI_8X_4X_DEVELOPMENT`: replace the baked WissKI module via `git clone` of `8.x-4.x` (optional `WISSKI_8X_4X_BRANCH`) instead of `composer require`, which fails against the canonical VCS repo and `wisski_starter`'s `dev-scs_base` pin.

## [3.7.2]

### Changed
- Revert to `DRUPAL_BASE_IMAGE_TAG=11.3-php8.3-fpm-bookworm` and packages manifest `3.5.1` (Drupal 11.3 / PHP 8.3); WissKI is not ready for PHP 8.4 and Drupal 11.4 has no official PHP 8.3 image.

## [3.7.1]

### Fixed
- Use `11.4-php8.4-fpm-bookworm` base image; `11.4-php8.3-fpm-bookworm` does not exist on Docker Hub (Drupal 11.4 ships with PHP 8.4).

## [3.7.0]

### Changed
- Pin `DRUPAL_BASE_IMAGE_TAG` to `11.4-php8.4-fpm-bookworm`
- Bump baked package manifest to `wisski_base/production/3.5.0` (Drupal 11.4)

## [3.6.1]
### Fixed
- take package version from image or env not from image tag.

## [3.6.0]

### Added
- Nginx blocks for common vulnerability scanner paths (WordPress probes, `.env`, etc.) before requests reach Drupal/PHP; protects the `raw.*` Traefik bypass path.

## 3.5.0

### Changed
- production images ship `config/php-fpm/zz-wisski-production.conf` (`pm.max_children = 15`, dynamic pool sizing, `request_terminate_timeout = 300`) so concurrent WissKI entity views are not capped at the default pool of five workers; omitted from development images.

## 3.4.1

### Changed
- bump baked package manifest to `wisski_base/production/3.4.1`.

## 3.4.0

### Changed
- bump baked package manifest to `wisski_base/production/3.4.0`.

## 3.3.3

### Changed
- bake Colorbox from [TurbojetTechnologies/colorbox](https://github.com/TurbojetTechnologies/colorbox) release `1.7.0` instead of `jackmoore/colorbox` `master`.

## 3.3.2

### Fixed
- set `IIIF_VERSION=2` for iipsrv (nginx `fastcgi_param`, Apache `FcgidInitialEnv`, and the standalone iipsrv process) so IIIF `info.json` matches WissKI Presentation 2 manifests; fixes blank Mirador canvases when Mirador 3 requests v3 image URLs.
- pre-create `/var/composer-home/cache` owned by `www-data` and re-apply ownership on every boot so `composer show --latest` via docker exec works.

### Changed
- bump baked package manifest to `wisski_base/production/3.3.2`.

## 3.3.1

### Fixed
- fix vendor executable permissions in the build-time chmod step: the shebang scan used `read -d ''`, which `/bin/sh` (dash) does not support in `RUN` instructions, so launchers such as `vendor/drush/drush/drush` stayed at 644 and Drush failed with "Permission denied" on first install.

### Changed
- bake static permissions for the immutable codebase at build time (directories 755, files 644, vendor executables 755, `.htaccess`/`robots.txt` 444); `set-permissions.sh` no longer walks the whole tree on first boot, only the writable state dirs and generated settings files, cutting install time.


## 3.3.0
### Added
- bake WissKI Mirador integration, Colorbox, DOMPurify, and DFG 3D Viewer JS libraries into the image at build time under `web/libraries/`.
- development images install the DFG 3D Viewer library from the `1.x` branch zip in the JS library repository; production images use the latest GitLab release.

### Changed
- move IIIF server config (`wisski_iip_image.wisski_iiif_settings`) earlier in the default data model recipe flow (before additional library setup).
- remove runtime `drush` library downloads from the entrypoint; libraries are part of the immutable baked codebase.
- enable `dfg_3dviewer` before running `drush dfg-3dviewer:configure` in the default data model recipe.


### Files Modified
- `Dockerfile`: download and unpack Mirador, Colorbox, DOMPurify, and DFG 3D Viewer libraries after the composer bake step; add a build-time step that sets static codebase permissions and drop the blanket `chmod -R 775 /opt/drupal`.
- `entrypoint.sh`: remove `INSTALL ADDITIONAL LIBRARIES` block; keep `drush dfg-3dviewer:configure` and IIIF config in the recipe.
- `config/drupal/set-permissions.sh`: drop the recursive whole-tree `chown`/`chmod` and vendor shebang scan; only lock down generated settings and fix the writable directories (files, private-files, xdebug log, Composer home).

## 3.2.1
### Changed
- new Drupal package version 3.2.1

## 3.2.0

### Changed
- development builds record package set version from `installed.json` hash (not `composer.lock`) in `.wisski-packages-version`, since dev manifests have no lock file.
- install recipe flow: run `wisski-core:recreate-menus` after locale and translation import (not before); import start page and default menu items after menu recreation.

### Files Modified
- `Dockerfile`: hash `vendor/composer/installed.json` for development `.wisski-packages-version`.
- `entrypoint.sh`: reorder menu recreation, content import, and menu-link disable steps in the default data model recipe.

## 3.1.2 [2026-06-17]

### Changed
- bump baked package manifest to `wisski_base/production/3.1.2`.

## 3.1.1 [2026-06-15]

### Added
- reverse proxy: optional `DRUPAL_PROXY_ADDRESSES=auto` detects trusted proxy CIDRs from container network interfaces on install and on every boot (syncs `settings.php` for existing sites).
- `config/drupal/sync-reverse-proxy.sh` and `config/drupal/lib/reverse-proxy.py` (installed to `/usr/local/bin/` and `/usr/local/lib/wisski/`); entrypoint delegates to the script.

### Changed
- reverse proxy is opt-in: unset/`none` skips configuration (default in the image); stacks behind Traefik set `DRUPAL_PROXY_ADDRESSES=auto` explicitly (e.g. wisski-base-stack).
- `none` removes an existing reverse proxy block from `settings.php` on boot.
- replace inline reverse-proxy heredoc in `entrypoint.sh` with `sync-reverse-proxy.sh` (also runs on boot for existing sites).
- bump baked package manifest to `wisski_base/production/3.1.1`.

### Files Modified
- `Dockerfile`: install reverse-proxy scripts; default `WISSKI_PACKAGES_VERSION=3.1.1`.
- `config/drupal/sync-reverse-proxy.sh`, `config/drupal/lib/reverse-proxy.py`: new.
- `entrypoint.sh`: call `sync-reverse-proxy.sh` on install and boot; remove legacy inline proxy block.
- `example-env`: document `DRUPAL_PROXY_ADDRESSES` values (`none`, `auto`, explicit CIDRs).

## 3.1.0 [2026-06-14]

### Changed
- development images resolve packages from `wisski_base/development/<line>/composer.json` (e.g. `3.x`) via `composer update` without a committed lock file; production still uses semver manifests with lock files under `wisski_base/production/<version>/`.
- add `WISSKI_PACKAGES_LINE` build arg for development builds; CI derives the line from the git branch name or major version of release tags.
- bump baked package manifest to `wisski_base/production/3.1.0`.

### Files Modified
- `Dockerfile`: split production (`composer install` + lock) and development (`composer update`, lock hash in `.wisski-packages-version`) manifest resolution.
- `.github/workflows/build-image.yml`: pass `WISSKI_PACKAGES_LINE` for development matrix builds.
- `entrypoint.sh`: clarify comments for production vs development manifest resolution.

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
