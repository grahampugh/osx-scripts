#!/usr/bin/env python3
"""
Helper script to fetch default values from Apple's MDM schema.
Used by analyze-profile-conflicts.sh to populate default values in CSV report.

Usage:
    python3 get_mdm_default.py <domain> <key>

Requirements:
    - requests
    - pyyaml

Output:
    Prints the default value if found, or "No default" if not documented.
"""

import sys
import json
import subprocess
from typing import Dict, Any, Optional

try:
    import requests
    import yaml
except ImportError:
    try:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "requests", "pyyaml"]
        )
    except subprocess.CalledProcessError:
        print("No default")
        sys.exit(0)


class MDMSchemaFetcher:
    """Fetches and parses Apple's MDM schema documentation from GitHub."""

    BASE_URL = "https://raw.githubusercontent.com/apple/device-management/release/mdm/profiles/"

    def __init__(self):
        self.session = requests.Session()
        self.schema_cache = {}

    def fetch_schema(self, payload_domain: str) -> Optional[Dict[str, Any]]:
        """Fetch schema for a specific preference domain."""
        if payload_domain in self.schema_cache:
            return self.schema_cache[payload_domain]

        schema_url = f"{self.BASE_URL}{payload_domain}.yaml"

        try:
            response = self.session.get(schema_url, timeout=10)
            response.raise_for_status()

            schema_data = yaml.safe_load(response.text)
            self.schema_cache[payload_domain] = schema_data

            return schema_data

        except requests.RequestException:
            return None
        except yaml.YAMLError:
            return None

    def get_default_value(self, payload_domain: str, payload_key: str) -> str:
        """Extract default value for a specific key in a domain."""
        schema = self.fetch_schema(payload_domain)
        if not schema:
            return "Undefined"

        payload_keys = schema.get("payloadkeys", [])

        for key_info in payload_keys:
            key_name = key_info.get("key")
            payload_default_value = key_info.get("default")

            if key_name == payload_key and payload_default_value is not None:
                # Convert to string for CSV output
                if isinstance(payload_default_value, bool):
                    return str(payload_default_value).lower()
                elif isinstance(payload_default_value, (list, dict)):
                    return json.dumps(payload_default_value)
                else:
                    return str(payload_default_value)

        return "No default"


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("No default")
        sys.exit(0)

    domain = sys.argv[1]
    key = sys.argv[2]

    fetcher = MDMSchemaFetcher()
    default_value = fetcher.get_default_value(domain, key)
    print(default_value)
