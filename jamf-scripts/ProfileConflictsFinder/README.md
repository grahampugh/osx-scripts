# Profile Conflicts Analyzer

A bash script that analyzes configuration profiles from Jamf Pro to identify duplicate key assignments across multiple profiles. This helps identify potential conflicts where the same MDM setting is being configured in different profiles.

## Purpose

When managing macOS devices with Jamf Pro, multiple configuration profiles might inadvertently configure the same settings with different values. This can lead to:

- Unpredictable device behavior
- Conflicting settings
- Difficult troubleshooting scenarios

This script downloads all configuration profiles from your Jamf Pro instance, analyzes the payload keys, and generates a CSV report showing which keys appear in multiple profiles along with their assigned values.

## Requirements

- **AutoPkg**: Required for downloading profiles from Jamf Pro
  - Recipe: `com.github.grahampugh.recipes.jamf.Helper-DownloadAllObjects`
- **jq**: Command-line JSON processor
- **Python 3**: For fetching default values (when using `--get-defaults`)
- **pyyaml**: Python module (required when using `--get-defaults`)
- **Jamf Pro API credentials** with read access to configuration profiles

## Installation

1. Ensure AutoPkg is installed and configured
2. Install jq (not required on macOS 15+)
3. The script `get_mdm_default.py` will attempt to install `pyyaml` and `requests` if not already present.

## Usage

```bash
./analyze-profile-conflicts.sh [options]
```

### Required Options

When not using `--existing-output-dir`, the following are required:

| Option | Description |
|--------|-------------|
| `--url URL` | Jamf Pro server URL (e.g., `https://instance.jamfcloud.com`) |
| `--username USERNAME` | Jamf Pro API username |
| `--password PASSWORD` | Jamf Pro API password |

**Note:** If these options are not provided on the command line, the script will prompt you for them interactively.

### Optional Parameters

| Option | Description |
|--------|-------------|
| `--output PATH` | Path to output CSV file. Default: `~/Desktop/profile-conflicts.csv` |
| `--existing-output-dir PATH` | Use existing downloaded profiles from this directory (skips download step). Should point to the directory containing the mobileconfig files with AutoPkg naming convention: `subdomain-os_x_configuration_profiles-ProfileName.mobileconfig` |
| `--domain DOMAIN` | Filter analysis to specific payload domain (e.g., `com.apple.applicationaccess`). If omitted, all domains are analyzed. |
| `--get-defaults` | Fetch actual default values from Apple's MDM schema (slower, requires pyyaml). If omitted, 'No default' will be shown for all keys. |
| `--tcc` | Include TCC, notifications, and system extension settings domains in analysis. By default, `com.apple.TCC.configuration-profile-policy`, `com.apple.notificationsettings`, and `com.apple.system-extension-policy` are excluded. |
| `-v, --verbose` | Enable verbose output from AutoPkg |
| `-h, --help` | Display usage information |

## Examples

### Basic Usage

Download and analyze all profiles from your Jamf Pro instance:

```bash
./analyze-profile-conflicts.sh \
  --url https://yourinstance.jamfcloud.com \
  --username api_user \
  --password 'your_password'
```

### Interactive Mode

Run without parameters to be prompted for credentials:

```bash
./analyze-profile-conflicts.sh
```

### Custom Output Location

Save the report to a specific location:

```bash
./analyze-profile-conflicts.sh \
  --url https://yourinstance.jamfcloud.com \
  --username api_user \
  --password 'your_password' \
  --output /path/to/my-conflicts-report.csv
```

### Analyze Specific Domain

Focus analysis on a single payload domain:

```bash
./analyze-profile-conflicts.sh \
  --url https://yourinstance.jamfcloud.com \
  --username api_user \
  --password 'your_password' \
  --domain com.apple.applicationaccess
```

### Include Default Values

Fetch Apple's default values for comparison (slower):

```bash
./analyze-profile-conflicts.sh \
  --url https://yourinstance.jamfcloud.com \
  --username api_user \
  --password 'your_password' \
  --get-defaults
```

### Include TCC and Related Domains

By default, TCC, notification settings, and system extension policies are excluded. Include them:

```bash
./analyze-profile-conflicts.sh \
  --url https://yourinstance.jamfcloud.com \
  --username api_user \
  --password 'your_password' \
  --tcc
```

### Use Previously Downloaded Profiles

Skip the download step and analyze already-downloaded profiles:

```bash
./analyze-profile-conflicts.sh \
  --existing-output-dir /Users/Shared/Jamf/JamfUploader \
  --output ~/Desktop/reanalysis.csv
```

### Verbose Mode

Enable verbose output to see AutoPkg's detailed progress:

```bash
./analyze-profile-conflicts.sh \
  --url https://yourinstance.jamfcloud.com \
  --username api_user \
  --password 'your_password' \
  -v
```

## Output Format

The script generates a CSV file with the following columns:

| Column | Description |
|--------|-------------|
| **Instance** | The Jamf Pro URL that was analyzed |
| **Profile Name** | Name of the configuration profile |
| **Domain** | Payload domain (e.g., `com.apple.applicationaccess`) |
| **Key** | The specific setting key that appears in multiple profiles |
| **Assigned Value** | The value assigned to this key in this profile |
| **Default Value** | Apple's default value for this key (only when using `--get-defaults`) |

## How It Works

1. **Download**: Uses AutoPkg to download all configuration profiles from Jamf Pro
2. **Parse**: Converts each mobileconfig file from plist to JSON format
3. **Extract**: Extracts all payload keys (excluding standard profile metadata)
4. **Analyze**: Identifies keys that appear in multiple profiles
5. **Report**: Generates a CSV showing all duplicate key assignments
6. **Filter**: Optionally filters by domain and excludes certain payload types

## Excluded Payload Keys

The following standard profile keys are automatically excluded from analysis:

- `PayloadType`
- `PayloadVersion`
- `PayloadIdentifier`
- `PayloadUUID`
- `PayloadEnabled`
- `PayloadDisplayName`
- `PayloadDescription`
- `PayloadOrganization`

## Excluded Domains (by default)

The following domains are excluded by default (use `--tcc` to include them):

- `com.apple.TCC.configuration-profile-policy`
- `com.apple.notificationsettings`
- `com.apple.system-extension-policy`

These are excluded because they often contain app-specific configurations that are expected to be unique per profile.

## Temporary Files

The script creates temporary files in:

- `/tmp/profile-analysis/` - Working directory for analysis
- Downloaded profiles are stored in `/Users/Shared/Jamf/JamfUploader/`

All temporary files are cleaned up automatically when the script completes.

## Troubleshooting

### No conflicts found

This is good! It means each setting key appears in only one profile. The script only reports keys that appear in multiple profiles.

### "No payload data was extracted"

This can occur if:

- No profiles exist in your Jamf Pro instance
- All profiles only contain excluded payload types
- Profile parsing failed

### AutoPkg errors

Ensure AutoPkg is properly installed and the required recipe is available:

```bash
autopkg repo-add grahampugh-recipes
```

### "Error fetching default"

When using `--get-defaults`, this indicates the `get_mdm_default.py` helper script couldn't retrieve the default value. This may be due to:

- Missing `pyyaml` module
- The key doesn't exist in Apple's MDM schema
- Network connectivity issues

## Credits

By Graham Pugh ([@grahampugh](https://github.com/grahampugh))

Claude Sonnet 4 was used to assist in development.

## License

See the LICENSE file in the repository root.
