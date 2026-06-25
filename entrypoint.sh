#!/bin/bash

set -e

# Enable debug mode if MODE environment variable is set to development.
if [ "${MODE}" = "development" ]; then
  echo -e "\033[0;32mDEVELOPMENT MODE ENABLED.\033[0m"
  set -ex
fi

# Set Environment variables.

# Set Composer home directory.
export COMPOSER_HOME=/var/composer-home

# Define the path to the settings.php file.
SETTINGS_FILE="/var/www/html/sites/default/settings.php"
export SETTINGS_FILE

# Marker files used to gate the install logic across container restarts.
# They live in the sites volume because the rest of /opt/drupal is an
# immutable, baked-in codebase that does not persist across recreations.
INSTALL_COMPLETE_FILE="/opt/drupal/web/sites/.wisski-install-complete"
INSTALL_IN_PROGRESS_FILE="/opt/drupal/web/sites/.wisski-install-in-progress"

# Package set version baked into the image and the version the sites volume
# was last updated to (used to trigger drush updatedb on image upgrades).
IMAGE_PACKAGES_VERSION_FILE="/opt/drupal/.wisski-packages-version"
SITE_PACKAGES_VERSION_FILE="/opt/drupal/web/sites/.wisski-packages-version"

# Private files live outside the web root and are mounted as a volume.
DRUPAL_PRIVATE_FILES_DIR="${DRUPAL_PRIVATE_FILES_DIR:-/opt/drupal/private-files}"

# Install WissKI Environment.
echo -e "\n \n \n"
echo -e "\033[38;5;208mWW      WW   iii   sss   sss   KK   KK   III\033[0m"
echo -e "\033[38;5;208mWW      WW   iii   sss   sss   KK  KK    III\033[0m"
echo -e "\033[38;5;208mWW      WW   iii  ss    ss     KK KK     III\033[0m"
echo -e "\033[38;5;208m WW WW WW    iii   sss   sss   KKKK      III\033[0m"
echo -e "\033[38;5;208m WW WW WW    iii     ss    ss  KK KK     III\033[0m"
echo -e "\033[38;5;208m  WW  WW     iii   sss   sss   KK  KK    III\033[0m"
echo -e "\033[38;5;208m  WW  WW     iii   sss   sss   KK   KK   III\033[0m"
echo -e "\n"

echo -e "\033[0;32m+------------------------------+\033[0m"
echo -e "\033[0;32m|WISSKI ENVIRONMENT ENTRYPOINT.|\033[0m"
echo -e "\033[0;32m+------------------------------+\033[0m"
echo -e "\n"

echo "USER: $(whoami)"
echo "PWD: $(pwd)"

# Validate required environment variables.
echo -e "\033[0;33mVALIDATING ENVIRONMENT VARIABLES...\033[0m"

REQUIRED_VARS=(
  "DB_DRIVER"
  "DB_HOST"
  "DB_NAME"
  "DB_PASSWORD"
  "DB_PORT"
  "DB_USER"
  "DRUPAL_DOMAIN"
  "DRUPAL_LOCALE"
  "DRUPAL_PASSWORD"
  "DRUPAL_PRIVATE_FILES_DIR"
  "DRUPAL_SITE_NAME"
  "DRUPAL_TRUSTED_HOSTS"
  "DRUPAL_USER"
  "REDIS_HOST"
  "REDIS_PORT"
  "TS_REPOSITORY"
  "TS_READ_URL"
  "TS_WRITE_URL"
  "WISSKI_DEFAULT_GRAPH"
  "WISSKI_STARTER_VERSION"
  "WISSKI_DEFAULT_DATA_MODEL_VERSION"
)

# Triplestore authentication: either TS_TOKEN or TS_USERNAME and TS_PASSWORD must be set.
if [ -z "${TS_TOKEN}" ] && { [ -z "${TS_USERNAME}" ] || [ -z "${TS_PASSWORD}" ]; }; then
  echo -e "\033[0;31mERROR: Triplestore credentials missing: set either TS_TOKEN or both TS_USERNAME and TS_PASSWORD.\033[0m"
  exit 1
fi

# Keycloak variables are only required when OpenID Connect is enabled.
if [ -n "${OPENID_CONNECT_CLIENT_SECRET}" ]; then
  REQUIRED_VARS+=(
    "KEYCLOAK_URL"
    "KEYCLOAK_REALM"
    "KEYCLOAK_ADMIN_GROUP"
    "KEYCLOAK_USER_GROUP"
  )
fi

# Note: module and recipe versions are baked into the image at build time
# from the drupal_packages composer manifest (production: pinned semver + lock;
# development: floating major line, e.g. 3.x, resolved at build time).
# WISSKI_STARTER_VERSION and WISSKI_DEFAULT_DATA_MODEL_VERSION only act as
# flags (non-empty = apply the recipe); they no longer select package versions.

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

if [ "${MODE}" = "development" ]; then
  echo -e "\033[0;33mENVIRONMENT VARIABLES:\033[0m"
  env | sort
  echo
fi

# Add groups to www-data user on every boot: /etc/group lives in the
# ephemeral container layer and does not survive container recreation.
echo -e "\033[0;33mADD GROUPS TO WWW-DATA USER.\033[0m"
if [ -n "${USER_GROUPS}" ]; then
  for group in $(echo "${USER_GROUPS}" | tr ',' ' '); do
    if getent group "g_${group}" >/dev/null 2>&1; then
      echo -e "\033[0;33mGROUP g_${group} ALREADY EXISTS; SKIPPING groupadd.\033[0m"
    else
      groupadd -g "${group}" "g_${group}"
      echo -e "\033[0;32mGROUP ${group} ADDED.\033[0m"
    fi
    if id -nG www-data | tr ' ' '\n' | grep -qFx "g_${group}"; then
      echo -e "\033[0;33mWWW-DATA ALREADY IN GROUP g_${group}; SKIPPING adduser.\033[0m"
    else
      adduser www-data "g_${group}"
      echo -e "\033[0;32mWWW-DATA USER ADDED TO GROUP ${group}.\033[0m"
    fi
  done
fi
echo -e "\033[0;32mGROUPS ADDED TO WWW-DATA USER.\033[0m\n"

# Ensure the volume mounts are writable by the runtime user.
chown www-data:www-data /opt/drupal/web/sites /opt/drupal/private-files 2>/dev/null || true
mkdir -p "${DRUPAL_PRIVATE_FILES_DIR}"
chown www-data:www-data "${DRUPAL_PRIVATE_FILES_DIR}"

# Check if Drupal is already installed.
echo -e "\033[0;33mCHECKING IF DRUPAL IS ALREADY INSTALLED.\033[0m"
if [ -f "$INSTALL_COMPLETE_FILE" ]; then
  echo -e "\033[0;32mDRUPAL IS ALREADY INSTALLED.\033[0m\n"

  # Run database updates when the image ships a newer package set than the
  # one the site was installed or last updated with.
  imagePackagesVersion="$(cat "${IMAGE_PACKAGES_VERSION_FILE}" 2>/dev/null || echo "unknown")"
  sitePackagesVersion="$(cat "${SITE_PACKAGES_VERSION_FILE}" 2>/dev/null || echo "unknown")"
  if [ "${imagePackagesVersion}" != "${sitePackagesVersion}" ]; then
    echo -e "\033[0;33mPACKAGE SET CHANGED (${sitePackagesVersion} -> ${imagePackagesVersion}); RUNNING DATABASE UPDATES...\033[0m"
    drush updatedb -y
    drush cr
    echo "${imagePackagesVersion}" > "${SITE_PACKAGES_VERSION_FILE}"
    echo -e "\033[0;32mDATABASE UPDATES APPLIED.\033[0m\n"
  fi

  /usr/local/bin/sync-reverse-proxy.sh

elif [ -f "$INSTALL_IN_PROGRESS_FILE" ]; then
  echo -e "\033[0;31mERROR: A previous installation attempt did not finish.\033[0m"
  echo -e "\033[0;31mThe site may be half-configured. Wipe the volumes (database and ${INSTALL_IN_PROGRESS_FILE%/*}) to reinstall,\033[0m"
  echo -e "\033[0;31mor finish the configuration manually and create ${INSTALL_COMPLETE_FILE} (and remove ${INSTALL_IN_PROGRESS_FILE}).\033[0m"
  exit 1

elif [ -f "$SETTINGS_FILE" ]; then
  # Legacy installation created before marker files were introduced.
  echo -e "\033[0;32mDRUPAL IS ALREADY INSTALLED (LEGACY INSTALLATION DETECTED; CREATING MARKER FILE).\033[0m\n"
  touch "$INSTALL_COMPLETE_FILE"
  /usr/local/bin/sync-reverse-proxy.sh

else
  echo -e "\033[0;32mDRUPAL IS NOT INSTALLED.\033[0m\n"
  touch "$INSTALL_IN_PROGRESS_FILE"

  # Check database connection first.
  echo -e "\033[0;33mCHECKING DATABASE CONNECTION...\033[0m"

  # Wait for database to be ready with timeout.
  DB_READY=false
  MAX_ATTEMPTS=30
  ATTEMPT=0

  while [ $ATTEMPT -lt $MAX_ATTEMPTS ] && [ "$DB_READY" = false ]; do
    # Pass the password via MYSQL_PWD to keep it out of the process list.
    if MYSQL_PWD="${DB_PASSWORD}" mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" -e "SELECT 1;" "${DB_NAME}" &>/dev/null; then
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

  # Install the site with timeout.
  echo -e "\033[0;33mINSTALLING DRUPAL SITE...\033[0m"

  if timeout 300 drush si \
    --db-url="${DB_DRIVER}://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}" \
    --site-name="${DRUPAL_SITE_NAME}" \
    --account-name="admin" \
    --account-pass="${DRUPAL_PASSWORD}" \
    --locale="${DRUPAL_LOCALE}" \
    --yes 2>&1; then
    echo -e "\033[0;32mDRUPAL SITE \"${DRUPAL_SITE_NAME}\" INSTALLED.\033[0m\n"
  else
    echo -e "\033[0;31mERROR: Drupal installation failed or timed out after 5 minutes.\033[0m"
    echo -e "\033[0;31mCheck database connection and credentials.\033[0m"
    exit 1
  fi

  if [ -n "${DRUPAL_TRUSTED_HOSTS}" ]; then
    # Convert pipe-delimited patterns to PHP array format with double quotes.
    # Input: "pattern1|pattern2|pattern3" → Output: ["pattern1", "pattern2", "pattern3"]
    PATTERNS=$(printf '%s' "${DRUPAL_TRUSTED_HOSTS}" | sed 's/|/", "/g')
    printf '%s\n' "\$settings['trusted_host_patterns'] = [\"${PATTERNS}\"];" >> "${SETTINGS_FILE}"
  fi
  echo -e "\033[0;32mTRUSTED HOST SETTINGS SET.\033[0m\n"

  # Set private files directory.
  echo -e "\033[0;33mSETTING PRIVATE FILES DIRECTORY...\033[0m"
  # Ensure the private files directory exists with proper permissions and ownership.
  if [ ! -d "$DRUPAL_PRIVATE_FILES_DIR" ]; then
    mkdir -p "${DRUPAL_PRIVATE_FILES_DIR}"
    echo -e "\033[0;32mCreated private files directory: $DRUPAL_PRIVATE_FILES_DIR\033[0m"
  fi
  {
    echo "\$settings[\"file_private_path\"] = \"$DRUPAL_PRIVATE_FILES_DIR\";" >> "${SETTINGS_FILE}"
  } 1> /dev/null
  echo -e "\033[0;32mPRIVATE FILES DIRECTORY SET.\033[0m\n"

  # Add Redis configuration to settings.php.
  if [ -n "${REDIS_HOST}" ]; then
    echo -e "\033[0;33mADDING REDIS CONFIGURATION TO SETTINGS.PHP...\033[0m"
    {
      cat >> "${SETTINGS_FILE}" << 'EOF'

/**
 * Redis cache backend configuration.
 * Auto-configured by entrypoint.
 */
if (file_exists('/var/configs/redis.settings.php')) {
  include '/var/configs/redis.settings.php';
}
EOF
    } 1> /dev/null
    echo -e "\033[0;32mREDIS CONFIGURATION ADDED TO SETTINGS.PHP.\033[0m\n"
  fi

  # Enable page cache for Varnish.
  echo -e "\033[0;33mENABLING PAGE CACHE FOR VARNISH...\033[0m"
  {
    drush config:set system.performance cache.page.max_age 300 -y
    echo -e "\033[0;32mPAGE CACHE ENABLED (5 minutes).\033[0m"
  } 1> /dev/null
  echo -e "\033[0;32mPAGE CACHE CONFIGURED.\033[0m\n"

  # Enable single content sync module (shipped in the image).
  echo -e "\033[0;33mENABLE SINGLE CONTENT SYNC MODULE.\033[0m"
  {
    drush en single_content_sync -y
  } 1> /dev/null
  echo -e "\033[0;32mSINGLE CONTENT SYNC MODULE ENABLED.\033[0m\n"

  # Enable development modules (development mode only; devel must not run in production).
  if [ "${MODE}" = "development" ]; then
    echo -e "\033[0;33mENABLE DEVELOPMENT MODULES.\033[0m"
    {
      drush en devel -y
    } 1> /dev/null
    echo -e "\033[0;32mDEVELOPMENT MODULES ENABLED.\033[0m\n"
  else
    echo -e "\033[0;33mDEVELOPMENT MODULES SKIPPED\033[0m\n"
  fi

  # Enable health check module (shipped in the image).
  echo -e "\033[0;33mENABLE HEALTH CHECK MODULE.\033[0m"
  {
    drush en health_check -y
  } 1> /dev/null
  echo -e "\033[0;32mHEALTH CHECK MODULE ENABLED.\033[0m\n"

  # Enable Sophron MIME type guesser (shipped with imagemagick dependency tree).
  echo -e "\033[0;33mENABLE SOPHRON GUESSER MODULE.\033[0m"
  {
    drush en sophron_guesser -y
  } 1> /dev/null
  echo -e "\033[0;32mSOPHRON GUESSER MODULE ENABLED.\033[0m\n"

  # Create WissKI User Role.
  echo -e "\033[0;33mCREATE WISSKI USER ROLE.\033[0m"
  {
    drush role:create 'wisski_user' 'WissKI User' -y
  } 1> /dev/null
  echo -e "\033[0;32mWISSKI USER GROUP CREATED.\033[0m\n"

  if [ "${OPENID_CONNECT_CLIENT_SECRET}" != "" ]; then
    echo -e "\033[0;33mENABLING OPENID CONNECT MODULE.\033[0m"
    {
      # The image ships the openid_connect fork with drush commands implementation.
      drush en openid_connect -y
    } 1> /dev/null
    echo -e "\033[0;32mOPENID CONNECT MODULE ENABLED.\033[0m\n"

    # Set OpenID Connect settings.
    echo -e "\033[0;33mSET OPENID CONNECT SETTINGS.\033[0m"
    {
      drush openid-connect:create-client 'SCS SSO' 'SODA SCS Client' generic --client-id="${DRUPAL_SITE_NAME}" --client-secret="${OPENID_CONNECT_CLIENT_SECRET}" --allowed-domains='*' --use-well-known=0 --authorization-endpoint="${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/auth" --token-endpoint="${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" --userinfo-endpoint="${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/userinfo" --end-session-endpoint="${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/logout" --scopes=openid,email,profile --prompt=login
    } 1> /dev/null
    echo -e "\033[0;33mSET OPENID CONNECT SETTINGS.\033[0m"
    {
      drush config-set openid_connect.settings user_login_display above
      drush config-set openid_connect.settings redirect_login home
      drush config-set openid_connect.settings redirect_logout home
      drush config-set openid_connect.settings override_registration_settings 1
    } 1> /dev/null
    echo -e "\033[0;32mOPENID CONNECT SETTINGS SET.\033[0m\n"

    echo -e "\033[0;33mSET OPENID CONNECT ROLE MAPPINGS.\033[0m"
    {
      drush config-set --input-format=yaml openid_connect.settings role_mappings.administrator "[${KEYCLOAK_ADMIN_GROUP}]" -y
      drush config-set --input-format=yaml openid_connect.settings role_mappings.wisski_user "[${KEYCLOAK_USER_GROUP}]" -y
    } 1> /dev/null
    echo -e "\033[0;32mOPENID CONNECT ROLE MAPPINGS SET.\033[0m\n"

    echo -e "\033[0;32mOPENID CONNECT SETTINGS SET.\033[0m\n"

    echo -e "\033[0;33mENABLE SSO BOUNCER.\033[0m"
    {
      drush en sso_bouncer -y
      drush sso_bouncer:enable "${DRUPAL_SITE_NAME}"
    } 1> /dev/null
    echo -e "\033[0;32mSSO BOUNCER ENABLED.\033[0m\n"

  else
    echo -e "\033[0;33mOPENID CONNECTION SKIPPED\033[0m\n"
  fi

  # Enable nextcloud webdav mount module (shipped in the image).
  if [[ -n "${NEXTCLOUD_BASE_URL}" && -n "${NEXTCLOUD_LOGIN_NAME}" && -n "${NEXTCLOUD_APP_PASSWORD}" ]]; then
    echo -e "\033[0;33mENABLE NEXTCLOUD CLIENT MODULE.\033[0m"
    {
      drush en nextcloud_webdav_mount -y
      drush nc-config --server-url="${NEXTCLOUD_BASE_URL}" --webdav-path='/remote.php/dav/files/{username}/' --operation-mode=sync --sync-direction=bisync --remote-path=SCS-Share --sync-interval=3600 --enable-log=0

    } 1> /dev/null
    echo -e "\033[0;32mNEXTCLOUD MOUNT MODULE ENABLED.\033[0m\n"
  else
    echo -e "\033[0;33mNEXTCLOUD CONNECTION SKIPPED\033[0m\n"
  fi

  # Apply WissKI Starter recipe (recipe package is shipped in the image).
  if [ -n "${WISSKI_STARTER_VERSION}" ]; then
    echo -e "\033[0;33mAPPLY WISSKI STARTER RECIPE.\033[0m"
      drush cr
      drush recipe ../recipes/wisski_starter
      drush cr
    echo -e "\033[0;32mWISSKI STARTER RECIPE APPLIED.\033[0m\n"
  else
    echo -e "\033[0;33mWISSKI STARTER RECIPE SKIPPED\033[0m\n"
  fi
  if [ -n "${WISSKI_DEFAULT_DATA_MODEL_VERSION}" ]; then
    # Install default adapter.
    echo -e "\033[0;33mINSTALL DEFAULT TRIPLESTORE ADAPTER.\033[0m"
      # Use token authentication when TS_TOKEN is set; otherwise username and password.
      TS_AUTH_ARGS=()
      if [ -n "${TS_TOKEN}" ]; then
        TS_AUTH_ARGS+=(--ts_use_token=1 --ts_token="${TS_TOKEN}")
      else
        TS_AUTH_ARGS+=(--ts_use_token=0 --ts_user="${TS_USERNAME}" --ts_password="${TS_PASSWORD}")
      fi
      drush wisski-salz:create-adapter --type='sparql11_with_pb' --adapter_label='Default' --adapter_machine_name='default' --description='Default SALZ adapter' --ts_machine_name="${TS_REPOSITORY}" "${TS_AUTH_ARGS[@]}" --writable=1 --preferred=1 --read_url="${TS_READ_URL}" --write_url="${TS_WRITE_URL}" --federatable=0 --default_graph="${WISSKI_DEFAULT_GRAPH}" --same_as='http://www.w3.org/2002/07/owl#sameAs' 1> /dev/null
      drush cr
    echo -e "\033[0;32mDEFAULT TRIPLESTORE ADAPTER INSTALLED.\033[0m\n"

    echo -e "\033[0;33mIMPORT WISSKI DEFAULT ONTOLOGY.\033[0m"
    drush wisski-core:import-ontology --store='default' --ontology_url='https://wiss-ki.eu/ontology/default/2.5.0/' --reasoning
    echo -e "\033[0;32mWISSKI DEFAULT ONTOLOGY IMPORTED.\033[0m\n"

    # Apply WissKI Default Data Model recipe (recipe package is shipped in the image).
    echo -e "\033[0;33mAPPLY WISSKI DATA DEFAULT MODEL RECIPE.\033[0m"
      drush cr
      drush recipe ../recipes/wisski_default_data_model

      echo -e "\033[0;32mAdd German language and update translations.\033[0m\n"

      # Add German language and update translations.
      drush language-add de && drush locale-check && drush locale-update
      drush php-eval "
        \$source = new \Drupal\Core\Config\FileStorage('/opt/drupal/recipes/wisski_default_data_model/config/language/de');
        \$langStorage = \Drupal::service('config.storage')->createCollection('language.de');
        foreach (\$source->listAll() as \$name) {
          \$langStorage->write(\$name, \$source->read(\$name));
        }
        "
      
      find /opt/drupal/web/modules/contrib/wisski -name '*.de.po' -type f -print0 | while IFS= read -r -d '' po; do
        drush locale:import de "$po" --type=not-customized --override=all -y
      done

      echo -e "\033[0;33mRECREATE WISSKI MAIN MENU.\033[0m\n"
        drush wisski-core:recreate-menus    
      echo -e "\033[0;32mTRANSLATIONS UPDATED.\033[0m\n"

      # Download and set WissKI logo.
      #wget https://wiss-ki.eu/sites/default/files/example/wisski_logo.png -O /opt/drupal/web/sites/default/files/wisski_logo.png
      # Import example contents.
      #curl -sSL 'https://wiss-ki.eu/example-contents' | curl -sS -w '\n%{http_code}\n' -X POST "${TS_WRITE_URL}" -H "Authorization: Token ${TS_TOKEN}" -H 'Content-Type: application/n-quads' --data-binary @-


      echo -e "\033[0;33mImport start page and default menu items.\033[0m\n"
      # Import example contents.
      drush config:set single_content_sync.settings site_uuid_check 0 -y
      drush content:import ../recipes/wisski_default_data_model/content/content.zip
      echo -e "\033[0;32mSTART PAGE AND DEFAULT MENU ITEMS IMPORTED.\033[0m\n"

      echo -e "\033[0;33mDISABLE WISSKI MAIN MENU LINKS.\033[0m\n"
      # Disable WissKI main menu links (menu: main). Config stores encoded keys (dots -> __); use the API.
      # Create  main  wisski.create_entities | Navigate  main  wisski.browse_entities | Find  main  wisski.search_entities
      drush php-eval "
        \$o = \\Drupal::service('menu_link.static.overrides');
        foreach (['wisski.create_entities', 'wisski.browse_entities', 'wisski.search_entities'] as \$id) {
          \$o->saveOverride(\$id, ['enabled' => FALSE]);
        }
        "
      echo -e "\033[0;32mWISSKI MAIN MENU LINKS DISABLED.\033[0m\n"

      echo -e "\033[0;33mSET FRONT PAGE.\033[0m\n"
      # Set front page.
      drush config:set system.site page.front /home -y
      echo -e "\033[0;32mFRONT PAGE SET.\033[0m\n"

      # Set DFG 3D Viewer settings.
      echo -e "\033[0;33mSET DFG 3D VIEWER SETTINGS.\033[0m\n"
      drush dfg-3dviewer:configure \
        --main-url=https://${DRUPAL_DOMAIN} \
        --container=DFG_3DViewer \
        --entitybundle=bd3d7baa74856d141bcff7b4193fa128 \
        --viewer-file-upload=fbf95bddee5160d515b982b3fd2e05f7 \
        --viewer-file-name=faa602a0be629324806aef22892cdbe5 \
        --lightweight=1 \
        --scale-container-x=1 \
        --scale-container-y=1.4 \
        --base-module-path=/libraries/dfg-3dviewer/assets \
        --entity-id-uri='/wisski/navigate/(.*)/view' \
        --view-entity-path=/wisski/navigate/ \
        --attribute-id=wisski_id
      echo -e "\033[0;32mDFG 3D VIEWER SETTINGS SET.\033[0m\n"

      echo -e "\033[0;33mSet IIIF configs.\033[0m"
      drush config-set wisski_iip_image.wisski_iiif_settings iiif_server "https://${DRUPAL_DOMAIN}/fcgi-bin/iipsrv.fcgi?IIIF="
      echo -e "\033[0;32mIIIF configs set.\033[0m\n"

      echo -e "\033[0;33mCLEAR CACHE.\033[0m\n"
      # Clear cache.
      drush cr
      echo -e "\033[0;32mCACHE CLEARED.\033[0m\n"

      echo -e "\033[0;32mGRANTING WISSKI USER PERMISSIONS.\033[0m\n"
      # Grant WissKI user permissions.
        drush role:perm:add 'wisski_user' 'access toolbar' -y
        drush role:perm:add 'wisski_user' 'access navigate' -y
        drush role:perm:add 'wisski_user' 'access create' -y
        drush role:perm:add 'wisski_user' 'access find' -y
        drush role:perm:add 'wisski_user' 'create any wisski content' -y
        drush role:perm:add 'wisski_user' 'view any wisski content' -y
        drush role:perm:add 'wisski_user' 'view published wisski content' -y
        drush role:perm:add 'wisski_user' 'view own unpublished wisski content' -y
        drush role:perm:add 'wisski_user' 'view other unpublished wisski content' -y
        drush role:perm:add 'wisski_user' 'view wisski revisions' -y
        drush role:perm:add 'wisski_user' 'revert wisski revisions' -y
        drush role:perm:add 'wisski_user' 'edit any wisski content' -y
        drush role:perm:add 'wisski_user' 'delete any wisski content' -y
        drush role:perm:add 'wisski_user' 'access wisski manifests' -y
        drush role:perm:add 'wisski_user' 'wisski_adapter_sparql11_pb.query' -y
      echo -e "\033[0;32mWISSKI USER PERMISSIONS GRANTED.\033[0m\n"

    echo -e "\033[0;32mWISSKI DEFAULT DATA MODEL RECIPE APPLIED.\033[0m\n"

  else
    echo -e "\033[0;33mWISSKI DEFAULT DATA MODEL RECIPE SKIPPED\033[0m\n"

  fi

  # Set IMCE profiles (after recipes, when IMCE may be installed)
  echo -e "\033[0;33mSET IMCE PROFILES.\033[0m"
  {
    drush config-set imce.settings roles_profiles.authenticated.public member -y
    drush config-set imce.settings roles_profiles.authenticated.private member -y
    drush config-set imce.settings roles_profiles.administrator.public admin -y
    drush config-set imce.settings roles_profiles.administrator.private admin -y
    drush config-set imce.settings roles_profiles.wisski_user.public member -y
    drush config-set imce.settings roles_profiles.wisski_user.private member -y
    drush config-set --input-format=yaml imce.profile.member conf.folders '[{path: "users/user[user:name]", permissions: {all: true}}]' -y
  } 1> /dev/null
  echo -e "\033[0;32mIMCE PROFILES SET.\033[0m\n"

  # Enable the Redis module (settings.php include was added above).
  if [ -n "${REDIS_HOST}" ]; then
    echo -e "\033[0;33mCONFIGURING REDIS INTEGRATION.\033[0m"
    {
      drush en redis -y
      drush cr
    } 1> /dev/null
    echo -e "\033[0;32mREDIS INTEGRATION CONFIGURED.\033[0m\n"
  else
    echo -e "\033[0;33mREDIS INTEGRATION SKIPPED\033[0m\n"
  fi

  /usr/local/bin/sync-reverse-proxy.sh

  # Set secure permissions following Drupal security guidelines.
  echo -e "\033[0;33mSET SECURE PERMISSIONS.\033[0m"
  /usr/local/bin/set-permissions.sh
  echo -e "\033[0;32mSECURE PERMISSIONS SET.\033[0m\n"

  # Record the package set version the site was installed with.
  cat "${IMAGE_PACKAGES_VERSION_FILE}" > "${SITE_PACKAGES_VERSION_FILE}" 2>/dev/null || true

  # Mark the installation as complete so restarts skip the install logic.
  rm -f "$INSTALL_IN_PROGRESS_FILE"
  touch "$INSTALL_COMPLETE_FILE"

  echo -e "\033[0;32m+---------------------------+\033[0m"
  echo -e "\033[0;32m|FINISHED INSTALLING DRUPAL.|\033[0m"
  echo -e "\033[0;32m+---------------------------+\033[0m"
fi

start_php_fpm() {
  if pgrep -x php-fpm >/dev/null 2>&1; then
    echo -e "\033[0;32mPHP-FPM already running.\033[0m"
    return
  fi
  echo -e "\033[0;33mStarting PHP-FPM...\033[0m"
  php-fpm -D
  echo -e "\033[0;32mPHP-FPM started.\033[0m"
}

start_memcached() {
  if pgrep -x memcached >/dev/null 2>&1; then
    echo -e "\033[0;32mMemcached already running.\033[0m"
    return
  fi
  echo -e "\033[0;33mStarting memcached...\033[0m"
  memcached -d -u memcache -l 127.0.0.1 -m 64
  echo -e "\033[0;32mMemcached started on 127.0.0.1:11211.\033[0m"
}

start_iipsrv() {
  if pgrep -f iipsrv.fcgi >/dev/null 2>&1; then
    echo -e "\033[0;32mIIPImage server already running.\033[0m"
    return
  fi
  echo -e "\033[0;33mStarting IIPImage server...\033[0m"
  export VERBOSITY="1"
  export LOGFILE="/var/log/iipsrv.log"
  export MAX_IMAGE_CACHE_SIZE="10"
  export JPEG_QUALITY="90"
  export MAX_CVT="5000"
  export MEMCACHED_SERVERS="localhost"
  local bindAddress="127.0.0.1"
  local bindPort="9100"
  su -s /bin/bash www-data -c "exec /fcgi-bin/iipsrv.fcgi --bind ${bindAddress}:${bindPort}" &
  echo -e "\033[0;32mIIPImage server started on ${bindAddress}:${bindPort}.\033[0m"
}

shutdownServices() {
  echo -e "\033[0;33mSHUTTING DOWN SERVICES...\033[0m"
  if [ -n "${nginxPid:-}" ] && kill -0 "${nginxPid}" 2>/dev/null; then
    nginx -s quit 2>/dev/null || kill -TERM "${nginxPid}" 2>/dev/null || true
  fi
  pkill -QUIT php-fpm 2>/dev/null || true
  pkill -TERM memcached 2>/dev/null || true
  pkill -TERM -f iipsrv.fcgi 2>/dev/null || true
  wait 2>/dev/null || true
  echo -e "\033[0;32mSERVICES STOPPED.\033[0m"
  exit 0
}

trap shutdownServices TERM INT

echo -e "\n"

start_php_fpm
start_memcached
start_iipsrv

# Run nginx in the foreground so SIGTERM can drain in-flight requests first.
nginx -g "daemon off;" &
nginxPid=$!
wait "${nginxPid}"
