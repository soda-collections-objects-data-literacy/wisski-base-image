#!/bin/bash
# Secure file permissions script following Drupal security guidelines.
# See: https://www.drupal.org/docs/administering-a-drupal-site/security-in-drupal/securing-file-permissions-and-ownership
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
PRIVATE_FILES_DIR="${PRIVATE_FILES_DIR:-/var/private-files}"

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

# Set ownership: www-data owns the entire Drupal tree so it can write where needed.
echo -e "\033[0;33m1. Setting ownership: ${WEB_USER}:${WEB_GROUP} for the entire Drupal tree...\033[0m"
chown -R ${WEB_USER}:${WEB_GROUP} "${DRUPAL_ROOT}"

echo -e "\033[0;33m2. Setting base permissions (775/664) so www-data can write...\033[0m"
find "${DRUPAL_ROOT}" -type d -exec chmod 775 {} \;
find "${DRUPAL_ROOT}" -type f -exec chmod 664 {} \;

# Common: Make vendor/bin executables executable
echo -e "\033[0;33m2a. Making vendor/bin executables executable (755)...\033[0m"
if [ -d "${DRUPAL_ROOT}/vendor/bin" ]; then
  # Make all files in vendor/bin executable (these are symlinks or wrappers)
  find "${DRUPAL_ROOT}/vendor/bin" -type f -exec chmod 755 {} \;
  echo -e "   - ${DRUPAL_ROOT}/vendor/bin: executables set to 755"

  # Find all actual executable files referenced by vendor/bin symlinks and make them executable
  find "${DRUPAL_ROOT}/vendor/bin" -type l | while read -r symlink; do
    target=$(readlink -f "$symlink" 2>/dev/null || true)
    if [ -n "$target" ] && [ -f "$target" ]; then
      chmod 755 "$target"
    fi
  done

  # Find all files in vendor directory that have shebang (likely executables)
  # This catches executables that might not be symlinked from vendor/bin
  find "${DRUPAL_ROOT}/vendor" -type f -print0 | while IFS= read -r -d '' file; do
    if head -n1 "$file" 2>/dev/null | grep -q "^#!"; then
      chmod 755 "$file"
    fi
  done
  echo -e "   - All vendor executables set to 755"
fi

# Common: Lock down critical configuration files
echo -e "\033[0;33m3. Locking down critical configuration files (444)...\033[0m"
if [ -f "${WEB_ROOT}/sites/default/settings.php" ]; then
  chmod 444 "${WEB_ROOT}/sites/default/settings.php"
  echo -e "   - settings.php: 444 (read-only)"
fi

if [ -f "${WEB_ROOT}/sites/default/services.yml" ]; then
  chmod 444 "${WEB_ROOT}/sites/default/services.yml"
  echo -e "   - services.yml: 444 (read-only)"
fi

if [ -f "${WEB_ROOT}/sites/default/settings.local.php" ]; then
  chmod 444 "${WEB_ROOT}/sites/default/settings.local.php"
  echo -e "   - settings.local.php: 444 (read-only)"
fi

# Common: Protect .htaccess files
echo -e "\033[0;33m4. Protecting .htaccess files (444)...\033[0m"
find "${WEB_ROOT}" -name ".htaccess" -exec chmod 444 {} \;

if [ -f "${WEB_ROOT}/robots.txt" ]; then
  chmod 444 "${WEB_ROOT}/robots.txt"
fi

# Common: Make files directory writable
echo -e "\033[0;33m5. Making files directory writable (775/664)...\033[0m"
if [ -d "${WEB_ROOT}/sites/default/files" ]; then
  chown -R ${WEB_USER}:${WEB_GROUP} "${WEB_ROOT}/sites/default/files"
  find "${WEB_ROOT}/sites/default/files" -type d -exec chmod 775 {} \;
  find "${WEB_ROOT}/sites/default/files" -type f -exec chmod 664 {} \;
  echo -e "   - ${WEB_ROOT}/sites/default/files: 775/664"
fi

# Common: Make xdebug log directory writable
echo -e "\033[0;33m7. Making xdebug log directory writable (775/664)...\033[0m"
if [ -d "/var/log/xdebug" ]; then
  chown -R ${WEB_USER}:${WEB_GROUP} "/var/log/xdebug"
  chmod 775 "/var/log/xdebug"
  find "/var/log/xdebug" -type f -exec chmod 664 {} \;
  echo -e "   - /var/log/xdebug: ${WEB_USER}:${WEB_GROUP} 775/664"
fi

# Common: Ensure Composer home directory is writable.
echo -e "\033[0;33m8. Ensuring Composer home directory is writable (775)...\033[0m"
mkdir -p "${COMPOSER_HOME:-/var/composer-home}"
chown -R ${WEB_USER}:${WEB_GROUP} "${COMPOSER_HOME:-/var/composer-home}"
chmod -R 775 "${COMPOSER_HOME:-/var/composer-home}"
echo -e "   - ${COMPOSER_HOME:-/var/composer-home}: ${WEB_USER}:${WEB_GROUP} 775"

echo -e "\033[0;32m========================================\033[0m"
echo -e "\033[0;32mSECURE PERMISSIONS SET SUCCESSFULLY!\033[0m"
echo -e "\033[0;32m========================================\033[0m"
