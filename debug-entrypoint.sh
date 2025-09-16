#!/bin/bash
# Debug script for WissKI Docker container issues
# This script helps diagnose common issues with the WissKI installation

set -e

echo -e "\033[0;32m==== WissKI Docker Debug Script ====\033[0m\n"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to test database connection
test_db_connection() {
    echo -e "\033[0;33mTesting database connection...\033[0m"

    if [ -z "${DB_HOST}" ] || [ -z "${DB_USER}" ] || [ -z "${DB_PASSWORD}" ] || [ -z "${DB_NAME}" ]; then
        echo -e "\033[0;31mERROR: Database environment variables not set.\033[0m"
        return 1
    fi

    if command_exists mysql; then
        if mysql -h"${DB_HOST}" -P"${DB_PORT:-3306}" -u"${DB_USER}" -p"${DB_PASSWORD}" -e "SELECT 1;" "${DB_NAME}" 2>/dev/null; then
            echo -e "\033[0;32mDatabase connection: SUCCESS\033[0m"
            return 0
        else
            echo -e "\033[0;31mDatabase connection: FAILED\033[0m"
            return 1
        fi
    else
        echo -e "\033[0;31mMySQL client not available for testing.\033[0m"
        return 1
    fi
}

# Function to check environment variables
check_env_vars() {
    echo -e "\033[0;33mChecking environment variables...\033[0m"

    local required_vars=(
        "DB_DRIVER"
        "DB_USER"
        "DB_PASSWORD"
        "DB_HOST"
        "DB_PORT"
        "DB_NAME"
        "SITE_NAME"
        "DRUPAL_PASSWORD"
    )

    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        else
            echo -e "\033[0;32m✓ $var is set\033[0m"
        fi
    done

    if [ ${#missing_vars[@]} -ne 0 ]; then
        echo -e "\033[0;31mMissing required environment variables:\033[0m"
        for var in "${missing_vars[@]}"; do
            echo -e "\033[0;31m✗ $var\033[0m"
        done
        return 1
    fi

    echo -e "\033[0;32mAll required environment variables are set.\033[0m"
    return 0
}

# Function to check disk space
check_disk_space() {
    echo -e "\033[0;33mChecking disk space...\033[0m"
    df -h /opt/drupal
    df -h /var/www/html
    df -h /tmp
}

# Function to check network connectivity
check_network() {
    echo -e "\033[0;33mChecking network connectivity...\033[0m"

    # Test DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        echo -e "\033[0;32m✓ DNS resolution works\033[0m"
    else
        echo -e "\033[0;31m✗ DNS resolution failed\033[0m"
    fi

    # Test internet connectivity
    if curl -s --connect-timeout 5 https://google.com >/dev/null; then
        echo -e "\033[0;32m✓ Internet connectivity works\033[0m"
    else
        echo -e "\033[0;31m✗ Internet connectivity failed\033[0m"
    fi
}

# Function to check Drush
check_drush() {
    echo -e "\033[0;33mChecking Drush...\033[0m"

    if command_exists drush; then
        echo -e "\033[0;32m✓ Drush is available\033[0m"
        drush --version

        # Check if we can run drush status
        if drush status --fields=bootstrap 2>/dev/null | grep -q "bootstrap"; then
            echo -e "\033[0;32m✓ Drush can access Drupal\033[0m"
        else
            echo -e "\033[0;31m✗ Drush cannot access Drupal properly\033[0m"
        fi
    else
        echo -e "\033[0;31m✗ Drush is not available\033[0m"
    fi
}

# Function to run a test Drupal installation
test_drupal_install() {
    echo -e "\033[0;33mTesting Drupal installation (dry run)...\033[0m"

    # First test database connection
    if ! test_db_connection; then
        echo -e "\033[0;31mSkipping Drupal install test due to database connection failure.\033[0m"
        return 1
    fi

    # Test drush site-install with --simulate flag
    echo -e "\033[0;33mSimulating drush site-install...\033[0m"
    if timeout 30 drush si \
        --db-url="${DB_DRIVER}://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}" \
        --site-name="${SITE_NAME}" \
        --account-name="admin" \
        --account-pass="${DRUPAL_PASSWORD}" \
        --simulate \
        --yes 2>&1; then
        echo -e "\033[0;32m✓ Drupal installation simulation successful\033[0m"
        return 0
    else
        echo -e "\033[0;31m✗ Drupal installation simulation failed\033[0m"
        return 1
    fi
}

# Main execution
main() {
    echo -e "Running diagnostics...\n"

    check_env_vars
    echo ""

    check_disk_space
    echo ""

    check_network
    echo ""

    test_db_connection
    echo ""

    check_drush
    echo ""

    test_drupal_install
    echo ""

    echo -e "\033[0;32m==== Debug script completed ====\033[0m"
}

# Run the main function
main "$@"
