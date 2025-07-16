# WissKI Base Image

A containerized WissKI (Wissenschaftliche KommunikationsInfrastruktur) environment built on Drupal with integrated triplestore connectivity and semantic web capabilities.

## Prerequisites

- Triplestore with repository (i.e. [OpenGDB](https://github.com/FAU-CDI/open_gdb), [GraphDB](https://graphdb.ontotext.com/) or [Blazegraph](https://blazegraph.com/))
- Database (i.e. MariaDB)

## Overview

This Docker image provides a complete WissKI installation with:
- **Base image**: Tested with `drupal:11.2.2-php8.3-apache-bookworm`
- **WissKI**: Digital humanities platform for managing scholarly data
- **Triplestore integration**: Ready-to-connect SPARQL endpoint support
- **Development tools**: Drush, debugging modules, and development utilities
- **Security**: OpenID Connect SSO integration support
- **Performance**: Optimized PHP configuration for WissKI workloads

## Features

### Core Components
- Drupal 11.2.2 with PHP 8.3 and Apache
- WissKI modules and dependencies
- SPARQL 1.1 triplestore adapter
- Redis caching support
- ImageMagick and VIPS for image processing
- IIPServer for high-resolution image serving

### Development & Administration
- Drush command-line tool
- Development modules (Devel, Health Check)
- Package Manager for module updates
- Automatic Updates support
- Project Browser integration

### Security & Authentication
- OpenID Connect integration
- SSO Bouncer for seamless authentication
- Configurable user roles and permissions
- Trusted host pattern protection

## Configuration

This image can be configured using the following environment variables:

### Database Settings
- `DB_DRIVER`: The database management system (e.g., `mysql`, `mariadb`, `postgres`)
- `DB_HOST`: Database server hostname (e.g., `localhost`, `db`)
- `DB_PORT`: Database server port (default: `3306` for MySQL, `5432` for PostgreSQL)
- `DB_NAME`: Name of the database
- `DB_USER`: Database username
- `DB_PASSWORD`: Database password

### Drupal Settings
- `DOMAIN`: Domain of the WissKI instance (e.g., `localhost`, `wisski.example.com`)
- `DRUPAL_TRUSTED_HOST`: Trusted host pattern for security (typically same as `DOMAIN`)
- `SITE_NAME`: Display name of the site (e.g., `"My WissKI Collection"`)
- `DRUPAL_USER`: Administrative username (will be created on initial startup)
- `DRUPAL_PASSWORD`: Password for the administrative user

### WissKI Settings
- `WISSKI_FLAVOURS`: Space-separated list of WissKI flavours to install (e.g., `"flavour1 flavour2"`)
- `DEFAULT_GRAPH`: Full URI of the default graph for storing WissKI data (e.g., `http://my.institution.edu/data/`)

### Triplestore Settings
- `TS_READ_URL`: SPARQL query endpoint URL (e.g., `http://triplestore:8080/repositories/default`)
- `TS_WRITE_URL`: SPARQL update endpoint URL (e.g., `http://triplestore:8080/repositories/default/statements`)
- `TS_REPOSITORY`: Name of the triplestore repository (e.g., `default`)
- `TS_USERNAME`: Triplestore authentication username
- `TS_PASSWORD`: Triplestore authentication password
- `TS_TOKEN`: Authentication token (if using token-based authentication)

### Optional SSO Settings
- `OPENID_CONNECT_CLIENT_SECRET`: OAuth2 client secret for OpenID Connect
- `KEYCLOAK_REALM`: Keycloak realm name
- `KEYCLOAK_ADMIN_GROUP`: Keycloak group for admin access
- `KEYCLOAK_USER_GROUP`: Keycloak group for regular user access

## Initial Setup Process

On first startup, the container will:

1. **Install Drupal**: Create the database schema and initial configuration
2. **Configure Security**: Set trusted host patterns and private files directory
3. **Install WissKI**: Apply WissKI starter recipe and default data model
4. **Setup Triplestore**: Create SPARQL adapter and import default ontology
5. **Configure Authentication**: Set up OpenID Connect if credentials provided
6. **Apply Flavours**: Install any specified WissKI flavours

This process may take several minutes depending on your system and network speed.

## Health Checks

The image includes health check endpoints:
- `/health`: Basic health status
- `/admin/reports/status`: Detailed system status (requires authentication)

## Troubleshooting

### Common Issues

**Container won't start**
- Check database connectivity and credentials
- Verify triplestore is accessible
- Review container logs: `docker logs <container-name>`

**Permission errors**
- Ensure mounted volumes (if any) have correct ownership (`33:33` for www-data)

**Slow startup**
- Initial installation downloads and installs many dependencies
- Subsequent startups are much faster
- Monitor progress with: `docker logs -f <container-name>`

**Database connection issues**
- Verify database server is running and accessible
- Check network connectivity between containers
- Confirm database credentials and permissions

### Debugging

Enable development mode:
```bash
docker exec -it <container-name> drush config-set system.logging error_level verbose
```

Access container shell:
```bash
docker exec -it <container-name> bash
```

Check system status:
```bash
docker exec -it <container-name> drush status
```

## Development

### Building the Image

```bash
git clone <repository-url>
cd wisski-base-image
docker build -t wisski-base-image .
```

It can also be built with a debugging variant:

```bash
git clone <repository-url>
cd wisski-base-image
docker build --build-arg WITH_XDEBUG=1 --build-arg WITH_OPCACHE=0 -t wisski-devel-image .
```

This adds [xbdebug](https://xdebug.org) to the image and disables opcache. 

### Environment File

Copy and modify the example environment file:
```bash
cp example-env .env
# Edit .env with your settings
docker-compose --env-file .env up
```

### Extending the Image

Create a custom Dockerfile:
```dockerfile
FROM your-registry/wisski-base-image:latest

# Add your customizations
RUN composer require your/custom-module
COPY custom-config.php /var/configs/

# Run additional setup
USER root
RUN your-custom-setup-script.sh
USER www-data
```

## Performance Tuning

### PHP Configuration

The image includes optimized PHP settings for WissKI:
- Memory limit: 1GB
- Max execution time: 300 seconds
- Upload size: 512MB
- OPcache enabled with optimized settings

### Database Optimization

For production use, consider:
- Increasing database memory allocation
- Optimizing database queries through caching
- Using read replicas for heavy read workloads

### Caching

@todo Make proper Redis caching configuration.

## Security Considerations

- Change default passwords before production use
- Use strong database credentials
- Configure HTTPS in production
- Regular security updates of base image
- Implement proper backup strategies
- Monitor system logs for security events

## License

This project is licensed under the GNU General Public License v3.0. See the [LICENSE.md](LICENSE.md) file for details.

## Support and Contributing

### Getting Help
- Check the [WissKI documentation](https://wiss-ki.eu/)
- Review container logs for error messages
- Consult Drupal and WissKI community forums

### Contributing
- Report issues through the project issue tracker
- Submit pull requests for improvements
- Follow the project's coding standards
- Include tests for new features

### Versioning
This project follows semantic versioning. See tags for stable releases.

---

**Note**: This image is designed for development and testing. For production deployments, additional security hardening and performance optimization may be required.
