#!/bin/bash
# Sync Drupal reverse proxy settings in settings.php.
# Called from the container entrypoint on install and on every boot.

set -e

SETTINGS_FILE="${SETTINGS_FILE:-/var/www/html/sites/default/settings.php}"
REVERSE_PROXY_PYTHON="${REVERSE_PROXY_PYTHON:-/usr/local/lib/wisski/reverse-proxy.py}"

auto_detect_proxy_cidrs() {
  local cidrs
  cidrs="$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | sort -u | paste -sd'|' -)"
  if [ -z "${cidrs}" ]; then
    echo -e "\033[0;33mWARNING: Could not auto-detect proxy CIDRs (no global IPv4 interfaces).\033[0m" >&2
    return 1
  fi
  printf '%s' "${cidrs}"
}

resolve_proxy_addresses() {
  # Unset or "none": no reverse proxy (standalone / local dockerWissKI without Traefik).
  # Set "auto" or explicit CIDRs when behind Traefik, Varnish+TLS edge, etc.
  local raw="${DRUPAL_PROXY_ADDRESSES:-}"
  case "${raw}" in
    ''|none|off|false|0)
      return 1
      ;;
    auto)
      auto_detect_proxy_cidrs
      ;;
    *)
      printf '%s' "${raw}"
      ;;
  esac
}

sync_reverse_proxy_settings() {
  local resolved

  if ! resolved="$(resolve_proxy_addresses)"; then
    if [ -f "${SETTINGS_FILE}" ]; then
      echo -e "\033[0;33mREMOVING REVERSE PROXY SETTINGS (DRUPAL_PROXY_ADDRESSES disabled).\033[0m"
      python3 "${REVERSE_PROXY_PYTHON}" --settings "${SETTINGS_FILE}" --remove
      echo -e "\033[0;32mREVERSE PROXY SETTINGS REMOVED.\033[0m\n"
    else
      echo -e "\033[0;33mREVERSE PROXY CONFIGURATION SKIPPED.\033[0m\n"
    fi
    return 0
  fi

  if [ ! -f "${SETTINGS_FILE}" ]; then
    echo -e "\033[0;33mREVERSE PROXY CONFIGURATION SKIPPED (settings.php not found).\033[0m\n"
    return 0
  fi

  echo -e "\033[0;33mSYNCING REVERSE PROXY SETTINGS (${resolved}).\033[0m"
  python3 "${REVERSE_PROXY_PYTHON}" --settings "${SETTINGS_FILE}" --addresses "${resolved}"
  echo -e "\033[0;32mREVERSE PROXY SETTINGS SYNCED.\033[0m\n"
}

sync_reverse_proxy_settings
