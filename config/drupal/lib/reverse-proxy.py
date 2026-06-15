#!/usr/bin/env python3
"""Sync Drupal reverse proxy settings in settings.php."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REVERSE_PROXY_BLOCK_PATTERN = re.compile(
    r"\n?/\*\*\n"
    r" \* Reverse proxy configuration\.\n"
    r" \* Auto-configured by entrypoint\.\n"
    r" \*/\n"
    r'\$settings\["reverse_proxy"\] = TRUE;\n'
    r'\$settings\["reverse_proxy_trusted_headers"\] = [^\n]+\n'
    r"\$settings\['omit_vary_cookie'\] = TRUE;\n"
    r"\$settings\[['\"]reverse_proxy_addresses['\"]\] = \[[^\]]*\];\n?",
    re.MULTILINE,
)

REVERSE_PROXY_BLOCK_TEMPLATE = """\
/**
 * Reverse proxy configuration.
 * Auto-configured by entrypoint.
 */
$settings["reverse_proxy"] = TRUE;
$settings["reverse_proxy_trusted_headers"] = \\Symfony\\Component\\HttpFoundation\\Request::HEADER_X_FORWARDED_FOR | \\Symfony\\Component\\HttpFoundation\\Request::HEADER_X_FORWARDED_HOST | \\Symfony\\Component\\HttpFoundation\\Request::HEADER_X_FORWARDED_PORT | \\Symfony\\Component\\HttpFoundation\\Request::HEADER_X_FORWARDED_PROTO;
$settings['omit_vary_cookie'] = TRUE;
$settings['reverse_proxy_addresses'] = [{addresses}];
"""


def format_addresses_pipe_separated(addresses: str) -> str:
    """Convert 172.20.0.0/16|192.168.0.0/20 to a PHP array literal."""
    parts = [part.strip() for part in addresses.split("|") if part.strip()]
    if not parts:
        raise ValueError("No proxy addresses provided.")
    return ", ".join(f'"{part}"' for part in parts)


def remove_reverse_proxy_settings(settings_path: Path) -> int:
    """Remove the reverse proxy block from settings.php if present."""
    text = settings_path.read_text(encoding="utf-8")
    text, removed = REVERSE_PROXY_BLOCK_PATTERN.subn("\n", text, count=1)
    if removed:
        settings_path.write_text(text.rstrip() + "\n", encoding="utf-8")
    return removed


def sync_reverse_proxy_settings(settings_path: Path, addresses: str) -> int:
    """
    Replace the reverse proxy block in settings.php (idempotent).

    Returns the number of removed blocks (0 or 1).
    """
    text = settings_path.read_text(encoding="utf-8")
    text, removed = REVERSE_PROXY_BLOCK_PATTERN.subn("\n", text, count=1)
    addresses_php = format_addresses_pipe_separated(addresses)
    block = "\n" + REVERSE_PROXY_BLOCK_TEMPLATE.format(addresses=addresses_php)
    settings_path.write_text(text.rstrip() + block + "\n", encoding="utf-8")
    return removed


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync Drupal reverse proxy settings in settings.php.",
    )
    parser.add_argument(
        "--settings",
        required=True,
        type=Path,
        help="Path to Drupal settings.php",
    )
    parser.add_argument(
        "--addresses",
        help="Pipe-separated list of trusted proxy CIDRs, e.g. 172.20.0.0/16|192.168.64.0/20",
    )
    parser.add_argument(
        "--remove",
        action="store_true",
        help="Remove reverse proxy settings from settings.php",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if not args.settings.is_file():
        print(f"ERROR: settings file not found: {args.settings}", file=sys.stderr)
        return 1

    if args.remove:
        removed = remove_reverse_proxy_settings(args.settings)
        print(f"reverse proxy block removed (removed_existing={removed})")
        return 0

    if not args.addresses:
        print("ERROR: --addresses is required unless --remove is set", file=sys.stderr)
        return 1

    try:
        removed = sync_reverse_proxy_settings(args.settings, args.addresses)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"reverse proxy block synced (removed_existing={removed})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
