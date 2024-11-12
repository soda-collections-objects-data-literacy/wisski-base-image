# WissKI Base image
- Base image: drupal:11.0.1-php8.3-apache-bookworm
- WissKI base recipe with version through env

## Configuration
This image can be configured using the following environment variables:

### Database settings
- `DB_DRIVER`: The used DBMS (e.g. mysql, mariadb, postgres)
- `DB_HOST`: Hostname where the DB is running (e.g. `localhost`)
- `DB_PORT`: Port on which DB is running
- `DB_NAME`: Name of the database (will be created)
- `DB_USER`: Name of the DB user (will be created)
- `DB_PASSWORD`: Password for `DB_USER` (will be set)

### Drupal settings
- `DOMAIN`: Domain of the WissKI (e.g. `localhost`)
- `DRUPAL_TRUSTED_HOST`: TODO: (e.g. `localhost`)
- `SITE_NAME`: Name of the site (e.g. `My WissKI`)
- `DRUPAL_USER`: Username for the Drupal user (will be created)
- `DRUPAL_PASSWORD`: Password for `DRUPAL_USER` (will be set)

### WissKI settings
# For a full list of versions see: 
- `WISSKI_GRAIN_YEAST_WATER_VERSION`: Version of the wisski grain and water recepie. Look [here](https://packagist.org/packages/soda-collection-objects-data-literacy/wisski_grain_yeast_water) for available versions.
- `WISSKI_FLAVOURS`: List of flavours. TODO: how do you have to specify them here and where is a list of available flavours?
- `DEFAULT_GRAPH`: Full graph URI where WissKI data should be stored (e.g. `http://my.graph.uri/`)

### Triplestore settings
- `TS_READ_URL`: URL of the read endpoint of the triplestore (e.g. `http://public.graph.database/repositories/default`)
- `TS_WRITE_URL`: URL of the read endpoint of the triplestore (e.g. `http://public.graph.database/repositories/default/statements`)
- `TS_REPOSITORY`: Name of the repository (will be created)
- `TS_USERNAME`: Username for the Triplestore user (will be created)
- `TS_PASSWORD`: Password for `TS_USERNAME` (will be set)
