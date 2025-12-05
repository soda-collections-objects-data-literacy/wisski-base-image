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
MODE="${MODE:-production}"

# Determine web user (www-data for Debian/Ubuntu).
WEB_USER="www-data"
WEB_GROUP="www-data"

echo -e "\033[0;33m========================================\033[0m"
echo -e "\033[0;33mSETTING SECURE DRUPAL PERMISSIONS\033[0m"
echo -e "\033[0;33mMode: ${MODE}\033[0m"
echo -e "\033[0;33m========================================\033[0m"

# Validate that Drupal root exists.
if [ ! -d "${DRUPAL_ROOT}" ]; then
  echo -e "\033[0;31mERROR: Drupal root not found at ${DRUPAL_ROOT}\033[0m"
  exit 1
fi

# Set ownership based on mode
if [ "${MODE}" = "production" ]; then
  # PRODUCTION MODE: Code owned by root, www-data can only read.
  echo -e "\033[0;33m1. Setting ownership: root:${WEB_GROUP} for code directories...\033[0m"
  chown -R root:${WEB_GROUP} "${DRUPAL_ROOT}"
else
  # DEVELOPMENT MODE: www-data owns everything for Composer access.
  echo -e "\033[0;33m1. Setting ownership: ${WEB_USER}:${WEB_GROUP} (for Composer access)...\033[0m"
  chown -R ${WEB_USER}:${WEB_GROUP} "${DRUPAL_ROOT}"
fi

# Common: Set base permissions (same for both modes)
echo -e "\033[0;33m2. Setting base permissions (755/644)...\033[0m"
find "${DRUPAL_ROOT}" -type d -exec chmod 755 {} \;
find "${DRUPAL_ROOT}" -type f -exec chmod 644 {} \;

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
  if [ "${MODE}" = "production" ]; then
    chown -R ${WEB_USER}:${WEB_GROUP} "${WEB_ROOT}/sites/default/files"
  fi
  find "${WEB_ROOT}/sites/default/files" -type d -exec chmod 775 {} \;
  find "${WEB_ROOT}/sites/default/files" -type f -exec chmod 664 {} \;
  echo -e "   - ${WEB_ROOT}/sites/default/files: 775/664"
fi

# Common: Secure private files directory
# NOTE: Private files ownership permissions are managed by an external service.
# Expected permissions for groups to have full access:
# - Directories: 770 (owner and group: read, write, execute; others: no access)
# - Files: 770 (owner and group: read, write; others: no access)
# echo -e "\033[0;33m6. Securing private files directory (770/770)...\033[0m"
# if [ -d "${PRIVATE_FILES_DIR}" ]; then
#   chmod 770 "${PRIVATE_FILES_DIR}"
#   find "${PRIVATE_FILES_DIR}" -type d -exec chmod 770 {} \;
#   find "${PRIVATE_FILES_DIR}" -type f -exec chmod 770 {} \;
#   echo -e "   - ${PRIVATE_FILES_DIR}: ${WEB_USER}:${WEB_GROUP} 770/770 (groups have full access)"
# fi

# Common: Make xdebug log directory writable
echo -e "\033[0;33m7. Making xdebug log directory writable (775/664)...\033[0m"
if [ -d "/var/log/xdebug" ]; then
  chown -R ${WEB_USER}:${WEB_GROUP} "/var/log/xdebug"
  chmod 775 "/var/log/xdebug"
  find "/var/log/xdebug" -type f -exec chmod 664 {} \;
  echo -e "   - /var/log/xdebug: ${WEB_USER}:${WEB_GROUP} 775/664"
fi

echo -e "\033[0;32m========================================\033[0m"
echo -e "\033[0;32mSECURE PERMISSIONS SET SUCCESSFULLY!\033[0m"
echo -e "\033[0;32m========================================\033[0m"
