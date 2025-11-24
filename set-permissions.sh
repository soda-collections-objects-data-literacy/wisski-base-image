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
MODE="${PERMISSIONS_MODE:-development}"

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

if [ "${MODE}" = "production" ]; then
  # PRODUCTION MODE
  # Code owned by root, www-data can only read.
  # Only files directories are writable by www-data.

  echo -e "\033[0;33m1. Setting ownership: root:${WEB_GROUP} for code directories...\033[0m"
  chown -R root:${WEB_GROUP} "${DRUPAL_ROOT}"

  echo -e "\033[0;33m2. Setting restrictive base permissions (755/644)...\033[0m"
  find "${DRUPAL_ROOT}" -type d -exec chmod 755 {} \;
  find "${DRUPAL_ROOT}" -type f -exec chmod 644 {} \;

  echo -e "\033[0;33m3. Locking down critical configuration files (444)...\033[0m"
  if [ -f "${WEB_ROOT}/sites/default/settings.php" ]; then
    chmod 444 "${WEB_ROOT}/sites/default/settings.php"
    echo -e "   - settings.php: 444 (read-only for all)"
  fi

  if [ -f "${WEB_ROOT}/sites/default/services.yml" ]; then
    chmod 444 "${WEB_ROOT}/sites/default/services.yml"
    echo -e "   - services.yml: 444 (read-only for all)"
  fi

  if [ -f "${WEB_ROOT}/sites/default/settings.local.php" ]; then
    chmod 444 "${WEB_ROOT}/sites/default/settings.local.php"
    echo -e "   - settings.local.php: 444 (read-only for all)"
  fi

  echo -e "\033[0;33m4. Protecting .htaccess files (444)...\033[0m"
  find "${WEB_ROOT}" -name ".htaccess" -exec chmod 444 {} \;

  if [ -f "${WEB_ROOT}/robots.txt" ]; then
    chmod 444 "${WEB_ROOT}/robots.txt"
  fi

  echo -e "\033[0;33m5. Making files directory writable for ${WEB_USER} (775/664)...\033[0m"
  if [ -d "${WEB_ROOT}/sites/default/files" ]; then
    chown -R ${WEB_USER}:${WEB_GROUP} "${WEB_ROOT}/sites/default/files"
    find "${WEB_ROOT}/sites/default/files" -type d -exec chmod 775 {} \;
    find "${WEB_ROOT}/sites/default/files" -type f -exec chmod 664 {} \;
    echo -e "   - ${WEB_ROOT}/sites/default/files: ${WEB_USER}:${WEB_GROUP} 775/664"
  fi

  echo -e "\033[0;33m6. Securing private files directory (770/660)...\033[0m"
  if [ -d "${PRIVATE_FILES_DIR}" ]; then
    chown -R ${WEB_USER}:${WEB_GROUP} "${PRIVATE_FILES_DIR}"
    chmod 770 "${PRIVATE_FILES_DIR}"
    find "${PRIVATE_FILES_DIR}" -type d -exec chmod 770 {} \;
    find "${PRIVATE_FILES_DIR}" -type f -exec chmod 660 {} \;
    echo -e "   - ${PRIVATE_FILES_DIR}: ${WEB_USER}:${WEB_GROUP} 770/660 (not web accessible)"
  fi

else
  # DEVELOPMENT MODE
  # www-data owns everything for Composer access.
  # More permissive but still follows Drupal security guidelines.

  echo -e "\033[0;33m1. Setting ownership: ${WEB_USER}:${WEB_GROUP} (for Composer access)...\033[0m"
  chown -R ${WEB_USER}:${WEB_GROUP} "${DRUPAL_ROOT}"

  echo -e "\033[0;33m2. Setting secure base permissions (755/644)...\033[0m"
  find "${DRUPAL_ROOT}" -type d -exec chmod 755 {} \;
  find "${DRUPAL_ROOT}" -type f -exec chmod 644 {} \;

  echo -e "\033[0;33m3. Locking down settings.php (444)...\033[0m"
  if [ -f "${WEB_ROOT}/sites/default/settings.php" ]; then
    chmod 444 "${WEB_ROOT}/sites/default/settings.php"
    echo -e "   - settings.php: 444 (read-only, even for ${WEB_USER})"
  fi

  if [ -f "${WEB_ROOT}/sites/default/services.yml" ]; then
    chmod 444 "${WEB_ROOT}/sites/default/services.yml"
    echo -e "   - services.yml: 444 (read-only)"
  fi

  echo -e "\033[0;33m4. Protecting .htaccess files (444)...\033[0m"
  find "${WEB_ROOT}" -name ".htaccess" -exec chmod 444 {} \;

  if [ -f "${WEB_ROOT}/robots.txt" ]; then
    chmod 444 "${WEB_ROOT}/robots.txt"
  fi

  echo -e "\033[0;33m5. Making files directory fully writable (775/664)...\033[0m"
  if [ -d "${WEB_ROOT}/sites/default/files" ]; then
    find "${WEB_ROOT}/sites/default/files" -type d -exec chmod 775 {} \;
    find "${WEB_ROOT}/sites/default/files" -type f -exec chmod 664 {} \;
    echo -e "   - ${WEB_ROOT}/sites/default/files: 775/664"
  fi

  echo -e "\033[0;33m6. Securing private files directory (770/660)...\033[0m"
  if [ -d "${PRIVATE_FILES_DIR}" ]; then
    chown -R ${WEB_USER}:${WEB_GROUP} "${PRIVATE_FILES_DIR}"
    chmod 770 "${PRIVATE_FILES_DIR}"
    find "${PRIVATE_FILES_DIR}" -type d -exec chmod 770 {} \;
    find "${PRIVATE_FILES_DIR}" -type f -exec chmod 660 {} \;
    echo -e "   - ${PRIVATE_FILES_DIR}: 770/660 (not web accessible)"
  fi

fi

echo -e "\033[0;32m========================================\033[0m"
echo -e "\033[0;32mSECURE PERMISSIONS SET SUCCESSFULLY!\033[0m"
echo -e "\033[0;32m========================================\033[0m"
echo ""
echo -e "Summary (${MODE} mode):"
if [ "${MODE}" = "production" ]; then
  echo "  - Code directories: root:${WEB_GROUP} 755"
  echo "  - Code files: root:${WEB_GROUP} 644"
else
  echo "  - Code directories: ${WEB_USER}:${WEB_GROUP} 755"
  echo "  - Code files: ${WEB_USER}:${WEB_GROUP} 644"
fi
echo "  - settings.php: 444 (read-only for all)"
echo "  - .htaccess files: 444 (protected)"
echo "  - files directory: ${WEB_USER}:${WEB_GROUP} 775/664 (writable)"
echo "  - private files: ${WEB_USER}:${WEB_GROUP} 770/660 (writable, not web accessible)"
echo ""

