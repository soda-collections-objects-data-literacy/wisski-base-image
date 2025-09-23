#!/bin/bash
# Exit on error
set -e

# Enable debug mode if DEBUG environment variable is set
if [ "${DEBUG}" = "true" ]; then
  set -x
fi

# Set Environment variables

# Set Composer home directory
export COMPOSER_HOME=/var/composer-home

# Define the path to the settings.php file
SETTINGS_FILE="/var/www/html/sites/default/settings.php"

# Define the path to the private files directory
PRIVATE_FILES_DIR="/var/private-files"

# Install WissKI Environment
echo -e "\n \n \n"
echo -e "\033[38;5;208mWW      WW   iii   sss   sss   KK   KK   III\033[0m"
echo -e "\033[38;5;208mWW      WW   iii   sss   sss   KK  KK    III\033[0m"
echo -e "\033[38;5;208mWW      WW   iii  ss    ss     KK KK     III\033[0m"
echo -e "\033[38;5;208m WW WW WW    iii   sss   sss   KKKK      III\033[0m"
echo -e "\033[38;5;208m WW WW WW    iii     ss    ss  KK KK     III\033[0m"
echo -e "\033[38;5;208m  WW  WW     iii   sss   sss   KK  KK    III\033[0m"
echo -e "\033[38;5;208m  WW  WW     iii   sss   sss   KK   KK   III\033[0m"
echo -e "\n"

echo -e "\033[0;32m+-------------------------------------+\033[0m"
echo -e "\033[0;32m|THIS INSTALLS WISSKI DEV ENVIRONMENT!|\033[0m"
echo -e "\033[0;32m+-------------------------------------+\033[0m"
echo -e "\n"

echo "USER: $(whoami)"
echo "PWD: $(pwd)"

# Validate required environment variables
echo -e "\033[0;33mVALIDATING ENVIRONMENT VARIABLES...\033[0m"

REQUIRED_VARS=(
  "DB_DRIVER"
  "DB_HOST"
  "DB_NAME"
  "DB_PASSWORD"
  "DB_PORT"
  "DB_USER"
  "DRUPAL_PASSWORD"
  "SITE_NAME"
  "USER_GROUPS"
)

MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    MISSING_VARS+=("$var")
  fi
done

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
  echo -e "\033[0;31mERROR: Missing required environment variables:\033[0m"
  for var in "${MISSING_VARS[@]}"; do
    echo -e "\033[0;31m  - $var\033[0m"
  done
  exit 1
fi

echo -e "\033[0;32mALL REQUIRED ENVIRONMENT VARIABLES ARE SET.\033[0m\n"

# Check if Drupal is already installed
if [ -f "$SETTINGS_FILE" ]; then
  echo -e "\033[0;32mDRUPAL IS ALREADY INSTALLED.\033[0m\n"
else

  # Set groups

  # Add groups to www-data user
  echo -e "\033[0;33mADD GROUPS TO WWW-DATA USER.\033[0m"

  if [ -n "${USER_GROUPS}" ]; then
    for group in $(echo ${USER_GROUPS} | tr ',' ' '); do
      groupadd -g ${group} g_${group}
      echo -e "\033[0;32mGROUP ${group} ADDED.\033[0m"
      adduser www-data g_${group}
      echo -e "\033[0;32mWWW-DATA USER ADDED TO GROUP ${group}.\033[0m"
    done
  fi

  echo -e "\033[0;32mGROUPS ADDED TO WWW-DATA USER.\033[0m\n"

  # Switch to www-data user
  echo -e "\033[0;33mSWITCHING TO WWW-DATA USER.\033[0m"
  su www-data
  echo "USER: $(whoami)"  
  echo "PWD: $(pwd)"
  echo -e "\033[0;32mSWITCHED TO WWW-DATA USER.\033[0m\n"

  # Check database connection first
  echo -e "\033[0;33mCHECKING DATABASE CONNECTION...\033[0m"

  # Wait for database to be ready with timeout
  DB_READY=false
  MAX_ATTEMPTS=30
  ATTEMPT=0

  while [ $ATTEMPT -lt $MAX_ATTEMPTS ] && [ "$DB_READY" = false ]; do
    if mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" -p"${DB_PASSWORD}" -e "SELECT 1;" "${DB_NAME}" &>/dev/null; then
      DB_READY=true
      echo -e "\033[0;32mDATABASE CONNECTION SUCCESSFUL.\033[0m"
    else
      echo -e "\033[0;33mWaiting for database... (attempt $((ATTEMPT + 1))/$MAX_ATTEMPTS)\033[0m"
      sleep 2
      ATTEMPT=$((ATTEMPT + 1))
    fi
  done

  if [ "$DB_READY" = false ]; then
    echo -e "\033[0;31mERROR: Could not connect to database after $MAX_ATTEMPTS attempts.\033[0m"
    echo -e "\033[0;31mDB_HOST: ${DB_HOST}\033[0m"
    echo -e "\033[0;31mDB_PORT: ${DB_PORT}\033[0m"
    echo -e "\033[0;31mDB_USER: ${DB_USER}\033[0m"
    echo -e "\033[0;31mDB_NAME: ${DB_NAME}\033[0m"
    exit 1
  fi

  # Install the site with timeout
  echo -e "\033[0;33mINSTALLING DRUPAL SITE...\033[0m"

  if timeout 300 drush si \
    --db-url="${DB_DRIVER}://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}" \
    --site-name="${SITE_NAME}" \
    --account-name="admin" \
    --account-pass="${DRUPAL_PASSWORD}" \
    --yes 2>&1; then
    echo -e "\033[0;32mDRUPAL SITE \"${SITE_NAME}\" INSTALLED.\033[0m\n"
  else
    echo -e "\033[0;31mERROR: Drupal installation failed or timed out after 5 minutes.\033[0m"
    echo -e "\033[0;31mCheck database connection and credentials.\033[0m"
    exit 1
  fi

  # Make settings.php writable for configuration updates
  echo -e "\033[0;33mMAKING SETTINGS.PHP WRITABLE...\033[0m"
  chmod 664 ${SETTINGS_FILE}
  echo -e "\033[0;32mSETTINGS.PHP IS NOW WRITABLE.\033[0m\n"

  # Set trusted host settings
  echo -e "\033[0;33mSETTING TRUSTED HOST SETTINGS...\033[0m"
  {
    echo '$settings["trusted_host_patterns"] = [
      "^".getenv("DRUPAL_TRUSTED_HOST")."$",
    ];' >> ${SETTINGS_FILE}
  } 1> /dev/null
  echo -e "\033[0;32mTRUSTED HOST SETTINGS SET.\033[0m\n"

  # Set private files directory
  echo -e "\033[0;33mSETTING PRIVATE FILES DIRECTORY...\033[0m"
  {
    echo "\$settings[\"file_private_path\"] = \"$PRIVATE_FILES_DIR\";" >> ${SETTINGS_FILE}
  } 1> /dev/null
  echo -e "\033[0;32mPRIVATE FILES DIRECTORY SET.\033[0m\n"

  # Set Package Manager Extension
  echo -e "\033[0;33mSETTING PACKAGE MANAGER EXTENSION...\033[0m"
  {
    echo "\$settings['testing_package_manager'] = TRUE;" >> ${SETTINGS_FILE}
  } 1> /dev/null
  echo -e "\033[0;32mPACKAGE MANAGER EXTENSION SET.\033[0m\n"

  # Restrict permissions of settings.php
  echo -e "\033[0;33mRESTRICTING PERMISSIONS OF SETTINGS.PHP...\033[0m"
  {
    chmod 644 ${SETTINGS_FILE}
  } 1> /dev/null
  echo -e "\033[0;32mSETTINGS.PHP CLOSED.\033[0m\n"

  # Lets get dirty with composer
  echo -e "\033[0;33mSET COMPOSER MINIMUM STABILITY.\033[0m"
  composer clear-cache
  composer config minimum-stability dev > /dev/null
  echo -e "\033[0;32mCOMPOSER MINIMUM STABILITY SET.\033[0m\n"

  # Allow composer to unpack recipes
  echo -e "\033[0;33mALLOW COMPOSER TO UNPACK RECIPES.\033[0m"
  {
    composer config allow-plugins.drupal/core-recipe-unpack true
    composer require drupal/core-recipe-unpack
  } 1> /dev/null
  echo -e "\033[0;32mCOMPOSER ALLOWED TO UNPACK RECIPES.\033[0m\n"

  # Install development modules
  echo -e "\033[0;33mINSTALL DEVELOPMENT MODULES.\033[0m"
  {
    # Drush command for openid_connect is not implement in main branch yet, so we have to use the fork.
    # Use the fork of openid_connect with drush commands implementation
    # Need WissKI User Administration module, to check if keycloak groups are matching.
    composer config repositories.openid_connect-3516375 vcs https://git.drupalcode.org/issue/openid_connect-3516375.git

    composer require 'drupal/automatic_updates:^4.0@alpha' drupal/devel drupal/health_check 'drupal/project_browser:^2.0@alpha' 'drupal/redis:^1.9' 'drupal/sso_bouncer:1.x-dev'
    composer require 'drupal/openid_connect:dev-3516375-implement-drush-commands' --prefer-source
    drush en devel health_check project_browser automatic_updates openid_connect sso_bouncer -y

  } 1> /dev/null
  echo -e "\033[0;32mDEVELOPMENT MODULES INSTALLED.\033[0m\n"

  # Create WissKI User Role
  echo -e "\033[0;33mCREATE WISSKI USER ROLE.\033[0m"
  {
    drush role:create 'wisski_user' 'WissKI User' -y
  } 1> /dev/null
  echo -e "\033[0;32mWISSKI USER GROUP CREATED.\033[0m\n"

  if [ "${OPENID_CONNECT_CLIENT_SECRET}" != "" ]; then
    # Set OpenID Connect settings
    echo -e "\033[0;33mSET OPENID CONNECT SETTINGS.\033[0m"
    {
      drush openid-connect:create-client "SCS SSO" "SODA SCS Client" generic \
    --client-id=${SITE_NAME} \
    --client-secret=${OPENID_CONNECT_CLIENT_SECRET} \
    --allowed-domains=* \
    --use-well-known=0 \
    --authorization-endpoint=https://auth.sammlungen.io/realms/${KEYCLOAK_REALM}/protocol/openid-connect/auth \
    --token-endpoint=https://auth.sammlungen.io/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token \
    --userinfo-endpoint=https://auth.sammlungen.io/realms/${KEYCLOAK_REALM}/protocol/openid-connect/userinfo \
    --end-session-endpoint=https://auth.sammlungen.io/realms/${KEYCLOAK_REALM}/protocol/openid-connect/logout \
    --scopes=openid,email,profile
    } 1> /dev/null
    echo -e "\033[0;33mSET OPENID CONNECT SETTINGS.\033[0m"
    {
      drush config-set openid_connect.settings user_login_display above
      drush config-set openid_connect.settings override_registration_settings 1
    } 1> /dev/null
    echo -e "\033[0;32mOPENID CONNECT SETTINGS SET.\033[0m\n"

    echo -e "\033[0;33mSET OPENID CONNECT ROLE MAPPINGS.\033[0m"
    {
      drush config-set --input-format=yaml openid_connect.settings role_mappings.administrator [${KEYCLOAK_ADMIN_GROUP}] -y
      drush config-set --input-format=yaml openid_connect.settings role_mappings.wisski_user [${KEYCLOAK_USER_GROUP}] -y
    } 1> /dev/null
    echo -e "\033[0;32mOPENID CONNECT ROLE MAPPINGS SET.\033[0m\n"

    echo -e "\033[0;32mOPENID CONNECT SETTINGS SET.\033[0m\n"

    echo -e "\033[0;33mENABLE SSO BOUNCER.\033[0m"
    {
      drush sso_bouncer:enable ${SITE_NAME}
    } 1> /dev/null
    echo -e "\033[0;32mSSO BOUNCER ENABLED.\033[0m\n"
  fi

  # Apply WissKI Starter recipe
  echo -e "\033[0;33mAPPLY WISSKI STARTER RECIPE.\033[0m"
    composer require 'drupal/wisski_starter:^1.0'
    drush cr
    drush recipe ../recipes/wisski_starter
    drush cr
  echo -e "\033[0;32mWISSKI STARTER RECIPE APPLIED.\033[0m\n"

  # Install default adapter
  echo -e "\033[0;33mINSTALL DEFAULT TRIPLESTORE ADAPTER.\033[0m"
    drush wisski-salz:create-adapter \
      --type="sparql11_with_pb" \
      --adapter_label="Default" \
      --adapter_machine_name="default" \
      --description="Default SALZ adapter" \
      --ts_machine_name=${TS_REPOSITORY} \
      --ts_user=${TS_USERNAME} \
      --ts_password=${TS_PASSWORD} \
      --ts_use_token=1 \
      --ts_token=${TS_TOKEN} \
      --writable=1 \
      --preferred=1  \
      --read_url=${TS_READ_URL} \
      --write_url=${TS_WRITE_URL} \
      --federatable=0 \
      --default_graph=${DEFAULT_GRAPH} \
      --same_as="http://www.w3.org/2002/07/owl#sameAs" 1> /dev/null
    drush cr
  echo -e "\033[0;32mDEFAULT TRIPLESTORE ADAPTER INSTALLED.\033[0m\n"

  echo -e "\033[0;33mIMPORT WISSKI DEFAULT ONTOLOGY.\033[0m"
  drush wisski-core:import-ontology --store="default" --ontology_url="https://wiss-ki.eu/ontology/default/2.0.0/" --reasoning
  echo -e "\033[0;32mWISSKI DEFAULT ONTOLOGY IMPORTED.\033[0m\n"

  # Apply WissKI Default Data Model recipe
  echo -e "\033[0;33mAPPLY WISSKI DATA DEFAULT MODEL RECIPE.\033[0m"
 # {
    composer config repositories.1 git https://git.drupalcode.org/issue/conditional_fields-3495402.git
    composer require 'drupal/wisski_default_data_model:1.0.x-dev'
    drush cr
    drush recipe ../recipes/wisski_default_data_model
    drush wisski-core:recreate-menus
    drush cr
  #} 1> /dev/null
  echo -e "\033[0;32mWISSKI DEFAULT DATA MODEL RECIPE APPLIED.\033[0m\n"

  for FLAVOUR in ${WISSKI_FLAVOURS}; do
    # Apply WissKI flavour recipe
    echo -e "\033[0;33mAPPLY WISSKI ${FLAVOUR} RECIPE.\033[0m"
    {
      composer require soda-collection-objects-data-literacy/wisski_${FLAVOUR}:dev-main
      drush cr
      drush recipe ../recipes/wisski_${FLAVOUR}
      drush wisski-core:recreate-menus
      drush cr
    } 1> /dev/null
    echo -e "\033[0;32mWISSKI ${FLAVOUR} RECIPE APPLIED.\033[0m\n"

    # Set IIP server config
    if [ "${FLAVOUR}" == "fruity" ]; then
      echo -e "\033[0;33mDownload Mirador integration library.\033[0m"
      drush wisski-mirador:wisski-mirador-integration
      echo -e "\033[0;32mMirador integration library downloaded.\033[0m\n"
      echo -e "\033[0;33mDownload Colorbox integration library.\033[0m"
      drush colorbox:plugin
      echo -e "\033[0;32mColorbox integration library downloaded.\033[0m\n"
      echo -e "\033[0;33mDownload DomPurify integration library.\033[0m"
      drush colorbox:dompurify
      echo -e "\033[0;32mDomPurify integration library downloaded.\033[0m\n"
      echo -e "\033[0;33mSet IIIF configs.\033[0m"
      drush config-set wisski_iip_image.wisski_iiif_settings iiif_server "${DOMAIN}/fcgi-bin/iipsrv.fcgi?IIIF="
      echo -e "\033[0;32mIIIF configs set.\033[0m\n"
    fi
  done

  # Unpack recipes
  echo -e "\033[0;33mUNPACK RECIPES.\033[0m"
  composer drupal:recipe-unpack >> /dev/null
  echo -e "\033[0;32mRECIPES UNPACKED.\033[0m\n"

  # change to root user
  echo -e "\033[0;33mCHANGE TO ROOT USER.\033[0m"
  su root
  echo "USER: $(whoami)"
  echo "PWD: $(pwd)"
  echo -e "\033[0;32mCHANGED TO ROOT USER.\033[0m\n"

  # Set permissions of web directory
  echo -e "\033[0;33mSET PERMISSIONS OF WEB DIRECTORY.\033[0m"
  chown -R www-data:www-data /var/www/html
  chmod -R 775 /var/www/html
  echo -e "\033[0;32mPERMISSIONS OF WEB DIRECTORY SET.\033[0m\n"
  

fi
echo -e "\033[0;32m+---------------------------+\033[0m"
echo -e "\033[0;32m|FINISHED INSTALLING DRUPAL.|\033[0m"
echo -e "\033[0;32m+---------------------------+\033[0m"

echo -e "\n"


# Keep the container running
/usr/sbin/apache2ctl -D FOREGROUND
