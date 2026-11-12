# Changelog

## [Unreleased]

### Changed

- `WISSKI_DEFAULT_DATA_MODEL_VERSION` is optional. When it is empty, the site
  starts as a plain Drupal/WissKI site without the ontology and the default
  data model. The default triplestore adapter is installed on every new site.
- The `wisski_user` role gets its permissions on every new site, not only
  with the default data model. Permissions of modules that are not installed
  are skipped and listed in the container log.

## [5.8.0] - 2026-11-09

### Changed

- WissKI Package Version 4.6.3: WissKI default data model recipe 3.1.0. All dates go through the EDTF time model (`P4_has_time-span` to a time expression), the date period and date bundles are gone, the views of the dated bundles sort and filter by date, the title patterns no longer print stray separators, and `wisski_core.settings` takes the values of the development site. Dates stored as date periods are not migrated.
- Recipe 3.1.0 also drops a dangling dependency of the image file form display that made the recipe config import fail since recipe 2.3.0. On sites where it failed so far, the next container start applies the whole current data model config at once, `wisski_core.settings` included. Set `WISSKI_RECIPE_CONFIG_UPDATE=0` on a site that should keep its config.

## [5.7.1] - 2026-11-09

### Fixed

- Recipe config import on a package-set change: the entrypoint now first installs the modules the WissKI starter and default data model recipes list, so that config shipped for a newly added module (such as `wisski_date_field_extractor.settings` in recipe 3.0.2) no longer makes the whole import fail. Before, nothing was imported on such sites, including the viewfield blocks like "(Claimed) Ownership".
- The site's package-set version is only recorded when the recipe config import went through, so a failed import is retried on the next container start instead of being skipped for good.

## [5.7.0] - 2026-11-09

### Removed

- `WISSKI_8X_4X_DEVELOPMENT` and `WISSKI_8X_4X_BRANCH`: the entrypoint no longer replaces the baked WissKI module with a `git clone` of `8.x-4.x`. The development image already ships WissKI 8.x-4.x, and the SCS Manager no longer sets the variable.

## [5.6.1] - 2026-11-09

### Changed

- WissKI Package Version 4.6.2: WissKI default data model recipe 3.0.2, which ships the date field extractor mapping for the time model (`wisski_date_field_extractor.settings`). New installations get the mapping; existing sites get it through the recipe config import on the package-set change, then run `drush wisski:edtf-reparse` to write the time-spans of existing dates.

## [5.6.0] - 2026-11-09

### Changed

- WissKI Package Version 4.6.1: WissKI default data model recipe 3.0.1, which restores the viewfield blocks such as "(Claimed) Ownership" and drops a dangling `custom_label` dependency that made config imports fail.
- Production images record the package set as `<version>-<md5 of installed.json>`, like development images do. A changed lock file under the same package version now also triggers `drush updatedb` on existing sites.
- When the package set changes, existing sites that got the WissKI default data model at install time also import its config (`drush config:import --partial`, plus the German overrides and a WissKI menu sync). This creates new and updates changed data-model config, deletes nothing, and overwrites local changes to that config. Set `WISSKI_RECIPE_CONFIG_UPDATE=0` to skip it. A failed import is logged and does not stop the container.
- New build argument `DRUPAL_PACKAGES_REF` (default `main`) selects the branch, tag or commit of `drupal_packages` to read the manifests from, e.g. to build before the raw.githubusercontent.com cache has caught up.

## [5.5.1] - 2026-11-08

### Fixed

- New installations sync the WissKI menus with `BundleMenu::syncAll()` instead of `drush wisski-core:recreate-menus`. Recreating deleted and regenerated the views named after each bundle, so the views shipped by the WissKI default data model recipe lost their block displays (e.g. the "(Claimed) Ownership" viewfield block). Existing installations restore them with `drush config:import --partial --source=../recipes/wisski_default_data_model/config`.

## [5.5.0] - 2026-11-08

### Changed

- **Breaking:** the rolling development line moves from branch `5.x` to `main`, so the rolling images are tagged `:main` instead of `:5.x`. Stable releases stay plain version tags (`5.5.0`, `5.5`, `5`, `latest`). A `X.x` branch is only cut from a release tag to maintain an older major and then builds `:X.x`.
- The rolling development image is rebuilt nightly, so it follows new commits on the floating WissKI package lines.
- `drupal/nextcloud_webdav_mount` 2.1.0 (via WissKI Package Version 4.6.0): the admin settings get their own Nextcloud group under Configuration, and the Navigation sidebar gets a top-level Nextcloud entry.
- WissKI Package Version 4.6.0: WissKI default data model recipe 3.0.0, WissKI starter recipe 2.3.0, upstream `drupal/openid_connect` 3.0.0-alpha9 instead of the fork, Drush 13.8.
- New installations create the OpenID Connect client with plain `drush config:set` instead of the `openid-connect:create-client` command from the forked module, so the image works with upstream `drupal/openid_connect`. The client machine name is now `scs_sso` (was `SCS SSO`); existing installations keep their client.

## [5.4.0] - 2026-11-08

### Changed

- Enable core `search` module on new installations (Drupal 11.4's Standard profile no longer installs it).
- Skip `drush language-add de` when the recipe already enabled German.
- Warn about ignored Nextcloud settings in external mode only when credentials are set; `NEXTCLOUD_BASE_URL` is always passed by the SCS Manager.
- In external Nextcloud mode, store `NEXTCLOUD_BASE_URL` as the module's `server_url` on every boot, so the Navigation entry links to the Nextcloud Files app ("Remote drive").

### Removed

- `content:import` of `content.zip`; start page and menu links ship as core default content in the default data model recipe and are imported by `drush recipe`.

## [5.3.1] - 2026-10-29

### Changed

- External Nextcloud mount path is `private://project_files` (`${DRUPAL_PRIVATE_FILES_DIR}/project_files`). Existing external installs are updated to that path on boot.

## [5.3.0] - 2026-10-22

### Changed

- WissKI Package Version 4.5.0
- New installations import the WissKI default ontology `2.7.0` (was `2.5.0`).
- New installations with the default data model use `/wisski_home` as front page (was `/home`), set right after the start page content is imported.
- New installations that apply the default data model set the OpenID Connect login and logout redirects to `/wisski_home` (was `home`). Without that model the redirects stay on `home`.
- Enable `navigation_extra_tools` together with `devel` in development mode.
- install `wisski-mirador-integration` from the release pinned in `MiradorLibrary.php` (checksum checked). That bundle is already built in `rnsrk/wisski-mirador-integration` and contains Mirador 4. Older WissKI builds without that pin still get the main-branch archive.
- Library downloads retry (`--retry 5 --retry-all-errors`) and copy without archive ownership; they run as one heredoc `RUN` step instead of a backslash-continued one.

### Fixed
- `settings.php` sets `$settings['enable_html5_validation'] = FALSE;` (the Drupal 12 default), which turns off browser-side HTML5 form validation and clears the status report warning. Added on every boot when missing, so existing sites get it too.
- The default triplestore adapter sends `TS_TOKEN` with the `Token ` scheme prefix the auth proxy expects; a value that already carries the prefix is not doubled.
- Fetch `dfg_3dviewer` from its `main` branch (the `standalone` branch is gone, which broke the build); drop `dist/dev`, `dist/prod` and `dist/test`, since the module loads only `dist/drupal/main`.

## [5.1.1] - 2026-10-06

### Fixed
- Enable and configure IMCE during installation when the module is available; skip the setup when it is absent.
- Pin Redis PECL to version `6.3.0` instead of the invalid `8.10.2` version.

### [5.1.0]

### Changed
- PHP base image `8.3-fpm-bookworm` → `8.5-fpm-bookworm`.
- WissKI packages manifest `4.0.2` → `4.2.0`.
- Pin Redis PECL (`6.1.0` → `8.10.2`) and Xdebug (`3.4.3` → `3.5.3`) via global ARGs; `IIPSRV_VERSION` uses the same before-`FROM` default and is redeclared without a value in `iipsrv-builder`.

### [5.0.0]

### Added
- `NEXTCLOUD_MOUNT_MODE` (`external` \| `sync` \| `none`) for Nextcloud WebDAV mount setup; `external` enables the module with `operation_mode=external` and `external_mount_path=private://nextcloud` without credentials.
- Idempotent every-boot upgrade that switches existing installs to `external` when `NEXTCLOUD_MOUNT_MODE=external`.
- `mkdir -p` of `${DRUPAL_PRIVATE_FILES_DIR}/nextcloud` after private-files setup (no recursive chown/chmod).

### Changed
- Unset `NEXTCLOUD_MOUNT_MODE` with all three `NEXTCLOUD_*` credentials still enables sync mode (backward compatible); without credentials the module stays disabled.
- `MODE`, `WISSKI_PACKAGES_VERSION`, and `WISSKI_PACKAGES_LINE` have one default, declared before the first `FROM`. Stages redeclare the names without a value so they inherit it. Image labels follow the baked codebase (`4.0.0` / `4.x`) instead of the stale runtime defaults `3.5.1` / `3.x`.
- README / `example-env`: document the three mount modes; credential trio is sync-only.
- WissKI Package Version 4.0.2

### Fixed
- Grant `wisski_user` the `access navigation` permission. Drupal 11.3's Standard profile ships the Navigation module instead of Toolbar, so `access toolbar` does not exist and `set -e` aborted first install.

### Removed
- `fuse3` from the runtime image (mount belongs in the sidecar for `external` mode; rclone remains for `sync`).

## [4.1.0]

- Drupal packages version to 3.6.0

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
- CI: bump Actions to Node 24 majors (`actions/checkout@v5`, `docker/metadata-action@v6`, `docker/setup-qemu-action@v4`, `docker/setup-buildx-action@v4`, `docker/login-action@v4`, `docker/build-push-action@v7`) and trigger builds on the `4.x` branch.
- CI: stop deriving `WISSKI_PACKAGES_LINE` from the git tag/branch; builds use the Dockerfile `ARG` defaults (`WISSKI_PACKAGES_LINE=3.x`, `WISSKI_PACKAGES_VERSION=3.5.1`) so the image major can diverge from the packages line.

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

[unreleased]: https://github.com/soda-collections-objects-data-literacy/wisski-base-image/compare/v5.3.0...HEAD
[5.3.0]: https://github.com/soda-collections-objects-data-literacy/wisski-base-image/compare/v5.1.1...v5.3.0
[5.1.1]: https://github.com/soda-collections-objects-data-literacy/wisski-base-image/compare/5.1.0...v5.1.1
