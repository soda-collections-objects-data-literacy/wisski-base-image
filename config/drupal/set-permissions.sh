#!/bin/bash
# Secure file permissions script following Drupal security guidelines.
# See: https://www.drupal.org/docs/administering-a-drupal-site/security-in-drupal/securing-file-permissions-and-ownership
#
# Strategy:
# The immutable codebase (core, modules, vendor, libraries) is baked as
# www-data with correct static permissions at build time (directories 755,
# files 644, vendor executables 755, .htaccess/robots 444). Install-time
# files (settings.php, sites/default/files) are also created by www-data
# because the entrypoint runs drush unprivileged. This script therefore only
# locks down the generated settings files and sites/default — a handful of
# fixed paths, no recursive chown/find walks.
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

echo -e "\033[0;33m========================================\033[0m"
echo -e "\033[0;33mSETTING SECURE DRUPAL PERMISSIONS\033[0m"
echo -e "\033[0;33m========================================\033[0m"

# Validate that Drupal root exists.
if [ ! -d "${DRUPAL_ROOT}" ]; then
  echo -e "\033[0;31mERROR: Drupal root not found at ${DRUPAL_ROOT}\033[0m"
  exit 1
fi

# Lock down the generated settings files and sites/default directory.
# The files are already www-data-owned (created by unprivileged drush),
# so only the modes need tightening.
echo -e "\033[0;33mLocking down critical configuration files (444) and sites/default (555)...\033[0m"
if [ -d "${WEB_ROOT}/sites/default" ]; then
  for file in settings.php services.yml settings.local.php; do
    if [ -f "${WEB_ROOT}/sites/default/${file}" ]; then
      chmod 444 "${WEB_ROOT}/sites/default/${file}"
      echo -e "   - ${file}: 444 (read-only)"
    fi
  done
  chmod 555 "${WEB_ROOT}/sites/default"
  echo -e "   - sites/default: 555 (read-only)"
fi

echo -e "\033[0;32m========================================\033[0m"
echo -e "\033[0;32mSECURE PERMISSIONS SET SUCCESSFULLY!\033[0m"
echo -e "\033[0;32m========================================\033[0m"
