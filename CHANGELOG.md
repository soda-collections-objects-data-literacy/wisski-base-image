# Changelog

## 3.x

### Added
- add graceful shutdown in entrypoint: trap SIGTERM/SIGINT, quit nginx, then stop php-fpm (SIGQUIT), memcached, and iipsrv before exit.
- add `STOPSIGNAL SIGTERM` and explicit `curl` package for the health check in the runtime image.

### Changed
- change Dockerfile to a two-stage build: compile PHP extensions and iipsrv in `builder`, copy only binaries and runtime libraries into the final image (drops autoconf, lib*-dev, and other toolchain packages).
- pin `DRUPAL_VERSION` default to `11.3-php8.3-fpm-bookworm` (was floating `php8.3-fpm-bookworm`); CI passes the same tag via `build-image.yml`.
- move xdebug compile to the builder stage; runtime only copies the ini when `MODE=development`.

### Fixed
- fix duplicate APCu load warning by not enabling apcu twice (pecl only in builder; zz-apcu-custom.ini enables it at runtime).