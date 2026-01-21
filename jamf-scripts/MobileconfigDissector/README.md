# mobileconfig_dissector.py

## Mobile Configuration Profile Dissector

This script analyzes a mobile configuration profile (`.mobileconfig`) and extracts
preference domain settings that differ from Apple's documented defaults.
It creates separate PLIST files for each domain containing only non-default values.

Usage:

    python3 mobileconfig_dissector.py <path_to_mobileconfig_file>

Requirements:

    - plistlib (built-in)
    - requests
    - pyyaml

The script will attempt to add these modules if they are missing.

This script was created with help from the Claude AI assistant.

For help:

    python3 mobileconfig_dissector.py --help
