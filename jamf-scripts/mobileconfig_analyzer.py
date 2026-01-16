#!/usr/bin/env python3
"""
Mobile Configuration Profile Analyzer

This script analyzes a mobile configuration profile (.mobileconfig) and extracts
preference domain settings that differ from Apple's documented defaults.
It creates separate PLIST files for each domain containing only non-default values.

Usage:
    python3 mobileconfig_analyzer.py <path_to_mobileconfig_file>

Requirements:
    - plistlib (built-in)
    - requests
    - pyyaml

This script was created with help from the Claude AI assistant.
"""

import argparse
import os
import plistlib
import sys
import traceback
from typing import Dict, Any, List, Optional

try:
    import requests
    import yaml
except ImportError:
    print("Error: Required packages not installed.")
    print("Install with: pip install requests pyyaml")
    sys.exit(1)


class MDMSchemaFetcher:
    """Fetches and parses Apple's MDM schema documentation from GitHub."""

    BASE_URL = "https://raw.githubusercontent.com/apple/device-management/release/mdm/profiles/"

    def __init__(self):
        self.session = requests.Session()
        self.schema_cache = {}

    def fetch_schema(self, domain: str) -> Optional[Dict[str, Any]]:
        """Fetch schema for a specific preference domain."""
        if domain in self.schema_cache:
            return self.schema_cache[domain]

        schema_url = f"{self.BASE_URL}{domain}.yaml"

        try:
            response = self.session.get(schema_url, timeout=10)
            response.raise_for_status()

            schema_data = yaml.safe_load(response.text)
            self.schema_cache[domain] = schema_data

            print(f"Fetched schema for {domain}")
            return schema_data

        except requests.RequestException as e:
            print(f"WARNING: Could not fetch schema for {domain}: {e}")
            return None
        except yaml.YAMLError as e:
            print(f"WARNING: Could not parse YAML for {domain}: {e}")
            return None

    def get_default_values(self, domain: str) -> Dict[str, Any]:
        """Extract default values from schema for a domain."""
        schema = self.fetch_schema(domain)
        if not schema:
            return {}

        defaults = {}
        payload_keys = schema.get("payloadkeys", [])

        for key_info in payload_keys:
            key_name = key_info.get("key")
            default_value = key_info.get("default")

            if key_name and default_value is not None:
                defaults[key_name] = default_value

        return defaults


class MobileConfigAnalyzer:
    """Analyzes mobile configuration profiles and extracts non-default settings."""

    def __init__(self):
        self.schema_fetcher = MDMSchemaFetcher()

    def read_mobileconfig(self, file_path: str) -> Dict[str, Any]:
        """Read and parse a mobile configuration file."""
        try:
            with open(file_path, "rb") as f:
                return plistlib.load(f)
        except Exception as e:
            raise ValueError(f"Could not read mobile config file: {e}") from e

    def extract_payloads_by_domain(
        self, config_data: Dict[str, Any]
    ) -> Dict[str, Dict[str, Any]]:
        """Extract payload data organized by preference domain."""
        domain_payloads = {}

        payload_content = config_data.get("PayloadContent", [])

        for payload in payload_content:
            payload_type = payload.get("PayloadType")

            if not payload_type or payload_type == "Configuration":
                continue

            # Extract preference keys (excluding standard payload metadata)
            preference_keys = {}
            excluded_keys = {
                "PayloadDescription",
                "PayloadDisplayName",
                "PayloadEnabled",
                "PayloadIdentifier",
                "PayloadOrganization",
                "PayloadType",
                "PayloadUUID",
                "PayloadVersion",
            }

            for key, value in payload.items():
                if key not in excluded_keys:
                    preference_keys[key] = value

            if preference_keys:
                if payload_type in domain_payloads:
                    domain_payloads[payload_type].update(preference_keys)
                else:
                    domain_payloads[payload_type] = preference_keys

        return domain_payloads

    def filter_non_defaults(
        self, domain: str, payload_data: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Filter out values that match documented defaults."""
        defaults = self.schema_fetcher.get_default_values(domain)
        non_defaults = {}

        for key, value in payload_data.items():
            default_value = defaults.get(key)

            # If we don't have a documented default, skip the value
            if default_value is None:
                print(
                    f"  SKIPPED: {key}: No documented default found, omitting from output"
                )

            # If value differs from default, include it
            elif value != default_value:
                non_defaults[key] = value
                print(f"  {key}: {value} (default: {default_value})")

            # If value matches default, skip it
            else:
                print(f"  - {key}: matches default ({default_value})")

        return non_defaults

    def create_plist_file(
        self, domain: str, data: Dict[str, Any], output_dir: str
    ) -> str:
        """Create a PLIST file for a preference domain."""
        filename = f"{domain}.plist"
        file_path = os.path.join(output_dir, filename)

        try:
            with open(file_path, "wb") as f:
                plistlib.dump(data, f)
            return file_path
        except Exception as e:
            raise ValueError(f"Could not write PLIST file {filename}: {e}") from e

    def analyze_and_extract(self, mobileconfig_path: str) -> List[str]:
        """Main analysis workflow."""
        print(f"Analyzing mobile configuration: {mobileconfig_path}")

        # Read the mobile config file
        config_data = self.read_mobileconfig(mobileconfig_path)

        # Extract payloads by domain
        domain_payloads = self.extract_payloads_by_domain(config_data)

        if not domain_payloads:
            print("ERROR: No preference domains found in the configuration.")
            return []

        print(f"Found {len(domain_payloads)} preference domains")

        # Determine output directory
        output_dir = os.path.dirname(os.path.abspath(mobileconfig_path))
        created_files = []

        # Process each domain
        for domain, payload_data in domain_payloads.items():
            print(f"\nProcessing domain: {domain}")

            # Filter non-default values
            non_defaults = self.filter_non_defaults(domain, payload_data)

            if non_defaults:
                # Create PLIST file
                file_path = self.create_plist_file(domain, non_defaults, output_dir)
                created_files.append(file_path)
                print(f"  Created: {os.path.basename(file_path)}")
            else:
                print("  All values match defaults, no file created")

        return created_files


def main():
    """Main entry point for the mobile configuration analyzer."""
    parser = argparse.ArgumentParser(
        description="Analyze mobile configuration profiles and extract non-default preferences"
    )
    parser.add_argument(
        "mobileconfig_path",
        help="Path to the mobile configuration (.mobileconfig) file",
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Enable verbose output"
    )

    args = parser.parse_args()

    # Validate input file
    if not os.path.exists(args.mobileconfig_path):
        print(f"ERROR: File not found: {args.mobileconfig_path}")
        sys.exit(1)

    if not args.mobileconfig_path.lower().endswith(".mobileconfig"):
        print("WARNING: File does not have .mobileconfig extension")

    try:
        analyzer = MobileConfigAnalyzer()
        created_files = analyzer.analyze_and_extract(args.mobileconfig_path)

        if created_files:
            print(
                f"\nAnalysis complete! Created {len(created_files)} preference files:"
            )
            for file_path in created_files:
                print(f"   • {os.path.basename(file_path)}")
        else:
            print("\nAnalysis complete! No non-default preferences found.")

    except (ValueError, OSError, plistlib.InvalidFileException) as e:
        print(f"ERROR: Error during analysis: {e}")
        if args.verbose:
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
