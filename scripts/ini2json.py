#!/usr/bin/env python3
"""Convert openclaw.ini sections into a JSON patch for openclaw.json.

Reads the ini file, maps sections to config paths, and outputs a JSON object
that can be deep-merged into the existing config.
"""
import json
import sys
from configparser import ConfigParser
from pathlib import Path


def set_nested(obj: dict, dotted_key: str, value):
    """Set a value in a nested dict using a dotted key path."""
    parts = dotted_key.split(".")
    for part in parts[:-1]:
        obj = obj.setdefault(part, {})
    obj[parts[-1]] = value


def parse_value(raw: str):
    """Parse a string value into its JSON type."""
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return raw


def build_patch(ini_path: str) -> dict:
    cp = ConfigParser()
    cp.optionxform = str  # preserve case
    cp.read(ini_path)
    patch = {}

    section_prefixes = {
        "gateway": "gateway",
        "tools": "tools",
        "agents": "agents.defaults",
        "logging": "logging",
        "discovery": "discovery",
    }

    for section, prefix in section_prefixes.items():
        if not cp.has_section(section):
            continue
        for key, raw_value in cp.items(section):
            set_nested(patch, f"{prefix}.{key}", parse_value(raw_value))

    if cp.has_section("hooks"):
        enable = cp.get("hooks", "enable", fallback="")
        if enable:
            for hook in enable.split(","):
                hook = hook.strip()
                if hook:
                    set_nested(patch, f"hooks.internal.entries.{hook}.enabled", True)
            set_nested(patch, "hooks.internal.enabled", True)

    return patch


if __name__ == "__main__":
    ini_path = sys.argv[1] if len(sys.argv) > 1 else "openclaw.ini"
    if not Path(ini_path).exists():
        print(f"Error: {ini_path} not found", file=sys.stderr)
        sys.exit(1)
    print(json.dumps(build_patch(ini_path), indent=2))
