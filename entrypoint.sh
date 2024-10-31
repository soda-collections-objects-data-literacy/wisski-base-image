#!/bin/bash
# Exit on error
set -e

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

# Define the path to the settings.php file
SETTINGS_FILE="/opt/drupal/web/sites/default/settings.php"

# Check if Drupal is already installed
if [ -f "$SETTINGS_FILE" ]; then
  echo -e "\033[0;32mDRUPAL IS ALREADY INSTALLED.\033[0m\n"
else
  # Install the site
  echo -e "\033[0;33mINSTALLING DRUPAL SITE...\033[0m"
  { drush si \
    --db-url="${DB_DRIVER}://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:3306/${DB_NAME}" \
    --site-name="${SITE_NAME}" \
    --account-name="${DRUPAL_USER}" \
    --account-pass="${DRUPAL_PASSWORD}"
  } 1> /dev/null
  echo -e "\033[0;32mDRUPAL SITE \"${SITE_NAME}\" INSTALLED.\033[0m\n"

  # Lets get dirty with composer
  echo -e "\033[0;33mSET COMPOSER MINIMUM STABILITY.\033[0m"
  composer config minimum-stability dev > /dev/null
  echo -e "\033[0;32mCOMPOSER MINIMUM STABILITY SET.\033[0m\n"
  # Install development modules
  echo -e "\033[0;33mINSTALL DEVELOPMENT MODULES.\033[0m"
  {
    composer require drupal/devel
    drush en devel -y
  } 1> /dev/null
  echo -e "\033[0;32mDEVELOPMENT MODULES INSTALLED.\033[0m\n"

  # Add Drupal Recipe Composer plugin
  echo -e "\033[0;33mINSTALL RECIPE COMPOSER PLUGIN.\033[0m"
  {
    composer config repositories.ewdev vcs https://gitlab.ewdev.ca/yonas.legesse/drupal-recipe-unpack.git
    composer config allow-plugins.ewcomposer/unpack true
    composer require ewcomposer/unpack:dev-master
  } 1> /dev/null
  echo -e "\033[0;32mRECIPE COMPOSER PLUGIN INSTALLED.\033[0m\n"

  # Apply WissKI Base recipe
  echo -e "\033[0;33mAPPLY WISSKI BASE ENVIRONMENT RECIPE.\033[0m"
  {
    composer require soda-collection-objects-data-literacy/wisski_grain_yeast_water:${WISSKI_GRAIN_YEAST_WATER_VERSION}
    drush recipe ../recipes/wisski_grain_yeast_water
    composer unpack soda-collection-objects-data-literacy/wisski_grain_yeast_water
    drush cr
  } 1> /dev/null
  echo -e "\033[0;32mWISSKI DEV RECIPE APPLIED.\033[0m\n"

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
    --writable=1 \
    --preferred=1  \
    --read_url=${TS_READ_URL} \
    --write_url=${TS_WRITE_URL} \
    --federatable=0 \
    --default_graph=${DEFAULT_GRAPH} \
    --same_as="http://www.w3.org/2002/07/owl#sameAs" 1> /dev/null
  drush cr
  echo -e "\033[0;32mDEFAULT TRIPLESTORE ADAPTER INSTALLED.\033[0m\n"

  for FLAVOUR in ${WISSKI_FLAVOURS}; do
    # Apply WissKI flavour recipe
    echo -e "\033[0;33mAPPLY WISSKI ${FLAVOUR} RECIPE.\033[0m"
    {
      echo -e "\033[0;33mIMPORT WISSKI DEFAULT ONTOLOGY.\033[0m"
      drush wisski-core:import-ontology --store="default" --ontology_url="http://wiss-ki.eu/ontology/1.2.0/" --reasoning
      echo -e "\033[0;32mWISSKI DEFAULT ONTOLOGY IMPORTED.\033[0m\n"
      composer require soda-collection-objects-data-literacy/wisski_${FLAVOUR}:dev-main
      drush recipe ../recipes/wisski_${FLAVOUR}
      composer unpack soda-collection-objects-data-literacy/wisski_${FLAVOUR}
      drush wisski-core:recreate-menus
      drush cr
    } 1> /dev/null
    echo -e "\033[0;32mWISSKI ${FLAVOUR} RECIPE APPLIED.\033[0m\n"
  done


  # Set permissions
  echo -e "\033[0;33mSET PERMISSIONS.\033[0m"
  {
    chown -R www-data:www-data /opt/drupal
    chmod -R 775 /opt/drupal
  } 1> /dev/null
  echo -e "\033[0;32mPERMISSIONS SET.\033[0m\n"
fi
echo -e "\033[0;32m+---------------------------+\033[0m"
echo -e "\033[0;32m|FINISHED INSTALLING DRUPAL.|\033[0m"
echo -e "\033[0;32m+---------------------------+\033[0m"

echo -e "\n"

# Keep the container running
/usr/sbin/apache2ctl -D FOREGROUND
