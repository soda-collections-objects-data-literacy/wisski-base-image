#!/bin/bash
# Secure file permissions script following Drupal security guidelines.
# See: https://www.drupal.org/docs/administering-a-drupal-site/security-in-drupal/securing-file-permissions-and-ownership
#
# Strategy:
# The immutable codebase (core, modules, vendor, libraries) already has its
# static ownership and permissions baked at build time in the Dockerfile
# (directories 755, files 644, vendor executables 755, .htaccess/robots 444).
# This script therefore only handles the paths that change at install/runtime:
# 1. Lock down the generated settings files and sites/default for security.
# 2. Make the writable state directories (files, private-files, logs) writable.
#
# Exit on error.
set -e

# Enable debug mode if DEBUG environment variable is set.
if [ "${DEBUG}" = "true" ]; then
  set -x
fi

# Configuration.
DRUPAL_ROOT="${DRUPAL_ROOT:-/opt/drupal}"
WEB_ROOT="${WEB_ROOT:-${DRUPAL_ROOT}/web}"
PRIVATE_FILES_DIR="${PRIVATE_FILES_DIR:-${DRUPAL_PRIVATE_FILES_DIR:-/opt/drupal/private-files}}"

# Determine web user (www-data for Debian/Ubuntu).
WEB_USER="www-data"
WEB_GROUP="www-data"

echo -e "\033[0;33m========================================\033[0m"
echo -e "\033[0;33mSETTING SECURE DRUPAL PERMISSIONS\033[0m"
echo -e "\033[0;33m========================================\033[0m"

# Validate that Drupal root exists.
if [ ! -d "${DRUPAL_ROOT}" ]; then
  echo -e "\033[0;31mERROR: Drupal root not found at ${DRUPAL_ROOT}\033[0m"
  exit 1
fi

# Lock down the generated settings files and sites/default directory.
# These are created at install time (by root), so fix ownership before mode.
echo -e "\033[0;33m1. Locking down critical configuration files (444) and sites/default (555)...\033[0m"
if [ -d "${WEB_ROOT}/sites/default" ]; then
  chown ${WEB_USER}:${WEB_GROUP} "${WEB_ROOT}/sites/default"
  for file in settings.php services.yml settings.local.php; do
    if [ -f "${WEB_ROOT}/sites/default/${file}" ]; then
      chown ${WEB_USER}:${WEB_GROUP} "${WEB_ROOT}/sites/default/${file}"
      chmod 444 "${WEB_ROOT}/sites/default/${file}"
      echo -e "   - ${file}: 444 (read-only)"
    fi
  done
  chmod 555 "${WEB_ROOT}/sites/default"
  echo -e "   - sites/default: 555 (read-only)"
fi

# Make the public files directory writable.
echo -e "\033[0;33m2. Making files directory writable (775/664)...\033[0m"
if [ -d "${WEB_ROOT}/sites/default/files" ]; then
  chown -R ${WEB_USER}:${WEB_GROUP} "${WEB_ROOT}/sites/default/files"
  find "${WEB_ROOT}/sites/default/files" -type d -exec chmod 775 {} +
  find "${WEB_ROOT}/sites/default/files" -type f -exec chmod 664 {} +
  echo -e "   - ${WEB_ROOT}/sites/default/files: 775/664"
fi

# Make the private files directory writable (lives outside the web root).
echo -e "\033[0;33m3. Making private files directory writable (775/664)...\033[0m"
if [ -d "${PRIVATE_FILES_DIR}" ]; then
  chown -R ${WEB_USER}:${WEB_GROUP} "${PRIVATE_FILES_DIR}"
  find "${PRIVATE_FILES_DIR}" -type d -exec chmod 775 {} +
  find "${PRIVATE_FILES_DIR}" -type f -exec chmod 664 {} +
  echo -e "   - ${PRIVATE_FILES_DIR}: 775/664"
fi

# Make the xdebug log directory writable.
echo -e "\033[0;33m4. Making xdebug log directory writable (775/664)...\033[0m"
if [ -d "/var/log/xdebug" ]; then
  chown -R ${WEB_USER}:${WEB_GROUP} "/var/log/xdebug"
  chmod 775 "/var/log/xdebug"
  find "/var/log/xdebug" -type f -exec chmod 664 {} +
  echo -e "   - /var/log/xdebug: ${WEB_USER}:${WEB_GROUP} 775/664"
fi

# Ensure the Composer home directory is writable.
echo -e "\033[0;33m5. Ensuring Composer home directory is writable (775)...\033[0m"
mkdir -p "${COMPOSER_HOME:-/var/composer-home}"
chown -R ${WEB_USER}:${WEB_GROUP} "${COMPOSER_HOME:-/var/composer-home}"
chmod -R 775 "${COMPOSER_HOME:-/var/composer-home}"
echo -e "   - ${COMPOSER_HOME:-/var/composer-home}: ${WEB_USER}:${WEB_GROUP} 775"

echo -e "\033[0;32m========================================\033[0m"
echo -e "\033[0;32mSECURE PERMISSIONS SET SUCCESSFULLY!\033[0m"
echo -e "\033[0;32m========================================\033[0m"
