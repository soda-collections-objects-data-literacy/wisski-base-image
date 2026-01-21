# Changelog

## 2.0.0
### Added
- Added `rsync` package to Dockerfile for Package Manager functionality.
- Added proper ownership and permissions configuration for `/var/configs`, `/var/private-files`, `/var/composer-home`, and `/opt/drupal` directories in Dockerfile.
- Added `package_manager_rsync_path` setting to configure Package Manager extension.
- Added automatic creation of private files directory with proper permissions if it doesn't exist during installation.
- Added comprehensive required environment variables validation including DRUPAL_DOMAIN, DRUPAL_LOCALE, DRUPAL_TRUSTED_HOST, DRUPAL_SITE_NAME, DRUPAL_PRIVATE_FILES_DIR, REDIS_HOST, REDIS_PORT, WISSKI_DEFAULT_GRAPH, WISSKI_STARTER_VERSION, WISSKI_DEFAULT_DATA_MODEL_VERSION, and triplestore-related variables.
- Added better documentation in set-permissions.sh explaining the permission strategy.

### Changed
- Changed `DRUPAL_VERSION` build argument default from specific version `11.3.1-php8.3-fpm-bookworm` to flexible `php8.3-fpm-bookworm` allowing version specification at build time.
- Refactored environment variable names for better clarity and consistency:
  - `SITE_NAME` → `DRUPAL_SITE_NAME`
  - `DEFAULT_GRAPH` → `WISSKI_DEFAULT_GRAPH`
  - `DOMAIN` → `DRUPAL_DOMAIN`
  - Added `DRUPAL_PRIVATE_FILES_DIR` to explicitly configure private files location.
- Improved trusted host pattern handling to use pipe-delimited format (e.g., `^localhost$|^127\.0\.0\.1$`) instead of requiring PHP array format.
- Simplified permission management strategy in `set-permissions.sh`: first ensure www-data ownership of entire /opt/drupal tree, then lock down only sensitive files and directories.
- Enhanced `set-permissions.sh` to lock down `sites/default` directory (555) in addition to `settings.php` (444) for better security.
- Removed unnecessary user switching between root and www-data in entrypoint.sh for cleaner execution flow and better maintainability.
- Improved Redis configuration handling with better conditional logic and error handling.
- Updated example-env with new variable names, better organization, and more comprehensive documentation.
- Consolidated Redis settings include in settings.php with improved formatting.
- Improved OpenID Connect client creation command formatting for better readability.
- Changed debug mode to use `set -ex` instead of `set -x` for better error handling.

### Fixed
- Fixed permission denied errors during recipe application by setting proper ownership and permissions immediately after Drupal installation.
- Fixed missing ownership settings for `/var/configs` and `/var/private-files` directories in Dockerfile.
- Fixed `trusted_host_patterns` configuration to use proper PHP array syntax with double quotes: `["pattern1", "pattern2"]` instead of `['pattern1','pattern2']`.
- Fixed settings.php handling by removing redundant chmod operations (now handled by set-permissions.sh at the end).
- Fixed Redis settings.php include formatting in entrypoint.sh.
- Fixed private files directory creation to ensure existence before usage.

### Removed
- Removed explicit chmod 664/644 operations on settings.php during configuration (now handled by set-permissions.sh at the end).
- Removed redundant user switching commands (`su www-data` and `su root`).

## 1.1.0
### Changed
- Updated Drupal version to 11.3.1.
- Simplified permissions for updating by reducing complexity in `set-permissions.sh` (removed 32 lines of unnecessary code).

### Fixed
- Fixed build argument configuration in GitHub workflow (corrected wrong build arg).
- Removed hardcoded version from build-image workflow for better flexibility.

## 1.0.2
### Fixed
- Set all git directories as safe directories (`git config --system --add safe.directory '*'`) to prevent dubious ownership warnings in container environments.

## 1.0.1
### Added
- Added permissions configuration for composer home directory (`/var/composer-home`).
- Added proper ownership settings in Dockerfile for composer cache directory.

### Changed
- Updated `set-permissions.sh` to include additional permission settings for composer directories.

## 1.0.0
### Added
- Initial release of WissKI base Docker image.
- Drupal installation with automated setup and configuration.
- WissKI modules and dependencies integration.
- Triplestore adapter configuration (SPARQL 1.1 with Pathbuilder).
- Automatic triplestore adapter creation with configurable parameters.
- WissKI default ontology import with reasoning support.
- Redis integration for caching (APCu and Redis module support).
- OpenID Connect support for SSO integration.
- Support for WissKI recipes and flavours.
- Configurable environment variables for Drupal, database, triplestore, and authentication.
- Automated permission management following Drupal security best practices.
- Support for both development and production modes.
- Nginx and Apache configuration for serving Drupal.
- IIPImage server support for high-resolution image serving.
- Composer integration with custom repositories.
- Automatic updates support via Project Browser.
- Health check module integration.
- Package Manager extension for automated updates.
- Custom PHP configuration (opcache, APCu, session, mysqli).
- Varnish page cache configuration.
- Trusted host patterns configuration for security.
- Private files directory configuration.
- User group assignment support for www-data user.
- Comprehensive entrypoint script for automated setup.
