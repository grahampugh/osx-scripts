#!/bin/bash

# --------------------------------------------------------------------------------
# Standalone Script for analyzing configuration profiles from Jamf Pro
# Identifies duplicate key assignments across configuration profiles.
# 
# By Graham Pugh (@grahampugh)
# Claude Sonnet 4 was used to assist in development.
# --------------------------------------------------------------------------------

# --------------------------------------------------------------------------------
# CONSTANTS
# --------------------------------------------------------------------------------

temp_output_dir="/tmp/profile-analysis"
default_csv_output="$HOME/Desktop/profile-conflicts.csv"
output_dir="/Users/Shared/Jamf/JamfUploader"

# --------------------------------------------------------------------------------
# FUNCTIONS
# --------------------------------------------------------------------------------

usage() {
    cat <<USAGE
Usage: ./analyze-profile-conflicts.sh [options]

Required:
      --url URL                    Jamf Pro server URL (e.g., https://instance.jamfcloud.com)
      --username USERNAME          Jamf Pro API username
      --password PASSWORD          Jamf Pro API password

Optional:
      --output PATH                Path to output CSV file (default: ~/Desktop/profile-conflicts.csv).
      --existing-output-dir PATH   Use existing downloaded profiles from this directory (skips download step).
                                   Should point to the directory containing the mobileconfig files with AutoPkg naming convention:
                                   subdomain-os_x_configuration_profiles-ProfileName.mobileconfig
      --domain DOMAIN              Filter analysis to specific payload domain (e.g., com.apple.applicationaccess).
                                   If omitted, all domains are analyzed.
      --get-defaults               Fetch actual default values from Apple's MDM schema (slower, requires pyyaml).
                                   If omitted, 'No default' will be shown for all keys.
      --tcc                        Include TCC, notifications, and system extension settings domains in
                                   analysis.
                                   By default, com.apple.TCC.configuration-profile-policy,
                                   com.apple.notificationsettings, and com.apple.system-extension-policy
                                   are excluded.
      -v, --verbose                Enable verbose output from AutoPkg

Description:
  This script downloads all configuration profiles from the specified Jamf Pro instance,
  analyzes payload keys across profiles, and generates a CSV report showing keys that
  appear in multiple profiles. The report includes profile name, domain, key name,
  assigned value, and optionally, Apple's default value for comparison.
USAGE
}

run_analysis() {
    # Create temporary directory for analysis
    mkdir -p "$temp_output_dir"
    
    # Set environment variables for AutoPkg
    local autopkg_cmd=(
        autopkg run "$VERBOSE"
        com.github.grahampugh.recipes.jamf.Helper-DownloadAllObjects
        --key OBJECT_TYPE="os_x_configuration_profile"
        --key OUTPUT_DIR="$output_dir"
        --key JSS_URL="$JAMF_URL"
        --key API_USERNAME="$JAMF_USERNAME"
        --key API_PASSWORD="$JAMF_PASSWORD"
        --key "DO_NOT_FAIL_RECIPES_WITHOUT_TRUST_INFO=true"
    )
    
    echo "Downloading all profiles from $JAMF_URL..."
    if ! "${autopkg_cmd[@]}"; then
        echo "ERROR: AutoPkg download failed."
        return 1
    fi

    echo "Download complete."
    return 0
}

parse_mobileconfig_files() {
    # Extract subdomain from instance URL for filename matching
    # e.g., https://example.jamfcloud.com -> example
    local instance_subdomain
    instance_subdomain=$(echo "$JAMF_URL" | sed -E 's|https?://([^.]+)\..*|\1|')
    
    # Files are saved directly in output_dir with prefix: subdomain-os_x_configuration_profiles-Name.mobileconfig
    local search_dir="$output_dir"
    
    if [[ ! -d "$search_dir" ]]; then
        echo "ERROR: Output directory not found at $search_dir" >&2
        return 1
    fi

    echo "Analyzing mobileconfig files from $search_dir..." >&2
    echo "Looking for files matching: ${instance_subdomain}-os_x_configuration_profiles-*.mobileconfig" >&2
    
    # Find all mobileconfig files matching this instance
    local mobileconfig_files=()
    while IFS= read -r -d '' file; do
        mobileconfig_files+=("$file")
    done < <(find "$search_dir" -maxdepth 1 -name "${instance_subdomain}-os_x_configuration_profiles-*.mobileconfig" -type f -print0)
    
    if [[ ${#mobileconfig_files[@]} -eq 0 ]]; then
        echo "No mobileconfig files found." >&2
        return 1
    fi
    
    echo "Found ${#mobileconfig_files[@]} mobileconfig file(s) to analyze." >&2
    echo "" >&2
    
    # Create JSON structure to track all key occurrences
    local temp_json
    temp_json=$(mktemp /tmp/profile-data.XXXXXX)
    
    if [[ -z "$temp_json" ]]; then
        echo "ERROR: Failed to create temporary file" >&2
        return 1
    fi
    
    # Initialize JSON array
    echo "[]" > "$temp_json"
    
    local file_counter=0
    local total_payloads=0
    
    # Process each mobileconfig file
    for mobileconfig in "${mobileconfig_files[@]}"; do
        ((file_counter++))
        local profile_name
        local full_name
        full_name=$(basename "$mobileconfig" .mobileconfig)
        
        # Extract profile name by removing instance-os_x_configuration_profiles- prefix
        # Format: instance-os_x_configuration_profiles-PROFILE_NAME.mobileconfig
        profile_name=$(echo "$full_name" | sed -E 's/^[^-]+-os_x_configuration_profiles-//')
        
        echo "  [$file_counter/${#mobileconfig_files[@]}] Processing: $profile_name" >&2
        
        # Convert mobileconfig to JSON and extract PayloadContent
        # Use plutil to convert plist to JSON, then jq to process
        local payload_count=0
        
        # Build jq filter based on --tcc flag
        local jq_filter
        if [[ $INCLUDE_TCC ]]; then
            jq_filter='.PayloadContent[]? | select(.PayloadType != "com.apple.ManagedClient.preferences")'
        else
            jq_filter='.PayloadContent[]? | select(.PayloadType != "com.apple.ManagedClient.preferences" and .PayloadType != "com.apple.TCC.configuration-profile-policy" and .PayloadType != "com.apple.notificationsettings" and .PayloadType != "com.apple.system-extension-policy")'
        fi
        
        if /usr/bin/plutil -convert json -o - "$mobileconfig" 2>/dev/null | \
            jq -c --arg pname "$profile_name" --arg instance "$JAMF_URL" "$jq_filter | {
                    profile_name: \$pname,
                    domain: .PayloadType,
                    instance: \$instance,
                    payload: .
                }" >> "$temp_json.tmp" 2>/dev/null; then
            # Count payloads extracted from this profile
            payload_count=$(grep -c "profile_name" "$temp_json.tmp" 2>/dev/null || echo 0)
            if [[ $payload_count -gt 0 ]]; then
                echo "       Extracted $payload_count payload(s)" >&2
                ((total_payloads += payload_count))
            else
                echo "       No payloads to extract" >&2
            fi
        else
            echo "       Warning: Could not parse $mobileconfig" >&2
        fi
    done
    
    echo "" >&2
    echo "Extraction complete: $total_payloads total payload(s) from $file_counter profile(s)" >&2
    echo "" >&2
    
    # Combine all payload data into a proper JSON array
    if [[ -f "$temp_json.tmp" && -s "$temp_json.tmp" ]]; then
        echo "Consolidating payload data..." >&2
        jq -s '.' "$temp_json.tmp" > "$temp_json"
        rm -f "$temp_json.tmp"
        echo "Payload data consolidated" >&2
    else
        echo "Warning: No payload data was extracted" >&2
        # Return empty array
        echo "[]" > "$temp_json"
    fi
    
    echo "$temp_json"
}

parse_analysis_results() {
    local payload_data_file="$1"
    
    if [[ ! -f "$payload_data_file" ]]; then
        echo "ERROR: Payload data file not found."
        return 1
    fi

    # Parse payload data to extract all keys and identify duplicates
    local temp_result
    temp_result=$(mktemp /tmp/profile-conflicts.XXXXXX)
    
    echo "  Analyzing key assignments..." >&2
    
    # Use jq to extract all keys from payloads and identify duplicates
    jq '
        # Extract all keys from each payload
        [.[] | 
            . as $entry |
            .payload | 
            to_entries[] |
            select(.key != "PayloadType" and 
                   .key != "PayloadVersion" and 
                   .key != "PayloadIdentifier" and 
                   .key != "PayloadUUID" and 
                   .key != "PayloadEnabled" and
                   .key != "PayloadDisplayName" and
                   .key != "PayloadDescription" and
                   .key != "PayloadOrganization") |
            {
                profile_name: $entry.profile_name,
                domain: $entry.domain,
                key: .key,
                value: (.value | tostring),
                instance: $entry.instance,
                key_id: "\($entry.domain)::\(.key)"
            }
        ] |
        # Group by key_id to find keys appearing in multiple profiles
        group_by(.key_id) |
        # Only keep groups with more than one occurrence
        map(select(length > 1)) |
        # Flatten back to array of occurrences
        flatten |
        # Remove the temporary key_id field
        map(del(.key_id))
    ' "$payload_data_file" > "$temp_result"
    
    # Apply domain filter if specified
    if [[ $FILTER_DOMAIN ]]; then
        local filtered_result
        filtered_result=$(mktemp /tmp/profile-conflicts-filtered.XXXXXX)
        jq --arg domain "$FILTER_DOMAIN" '[.[] | select(.domain == $domain)]' "$temp_result" > "$filtered_result"
        mv "$filtered_result" "$temp_result"
    fi
    
    echo "$temp_result"
}

generate_csv_report() {
    local all_results=()
    
    echo "Generating CSV report..."
    
    # Get script directory for get_mdm_default.py
    local script_dir
    script_dir=$(cd "$(dirname "$0")" && pwd)
    
    # Skip download if using existing output directory
    if [[ -n "$EXISTING_OUTPUT_DIR" ]]; then
        echo "Using existing output directory: $EXISTING_OUTPUT_DIR"
        # Temporarily override output_dir for parsing
        local original_output_dir="$output_dir"
        output_dir="$EXISTING_OUTPUT_DIR"
        
        local payload_data_file
        payload_data_file=$(parse_mobileconfig_files)
        
        # Restore original output_dir
        output_dir="$original_output_dir"
        
        if [[ -f "$payload_data_file" ]]; then
            local result_file
            result_file=$(parse_analysis_results "$payload_data_file")
            
            if [[ -f "$result_file" ]]; then
                all_results+=("$result_file")
            fi
        fi
    else
        # Normal flow: download then parse
        if run_analysis; then
            echo "Analyzing downloaded profiles from: $output_dir"
            local payload_data_file
            payload_data_file=$(parse_mobileconfig_files)
            
            if [[ -f "$payload_data_file" ]]; then
                local result_file
                result_file=$(parse_analysis_results "$payload_data_file")
                
                if [[ -f "$result_file" ]]; then
                    all_results+=("$result_file")
                fi
            fi
        else
            echo "ERROR: Analysis failed."
            return 1
        fi
    fi

    # Combine all results into CSV
    if [[ ${#all_results[@]} -eq 0 ]]; then
        echo "No conflicts found."
        return 1
    fi

    # Use jq to combine all JSON results and convert to CSV
    if [[ $GET_DEFAULTS ]]; then
        echo "Fetching default values from Apple MDM schema..." >&2
    fi
    
    # Ensure temp directory exists
    mkdir -p "$temp_output_dir"
    
    {
        # Write CSV header
        echo "Instance,Profile Name,Domain,Key,Assigned Value,Default Value"
        
        # Process each result file and convert to CSV rows
        for result_file in "${all_results[@]}"; do
            # Read the JSON and look up defaults for each row
            jq -r '.[] | [.instance, .profile_name, .domain, .key, .value] | @tsv' "$result_file" > "$temp_output_dir/tsv_rows.txt"
            while IFS=$'\t' read -r instance profile_name domain key value; do
                # Look up default value if --get-defaults flag is set
                if [[ $GET_DEFAULTS ]]; then
                    if default_value=$(python3 "$script_dir/get_mdm_default.py" "$domain" "$key" 2>/dev/null); then
                        :
                    else
                        default_value="Error fetching default"
                    fi
                else
                    default_value=""
                fi

                # Output as CSV (properly escape fields with commas/quotes)
                printf '%s,%s,%s,%s,%s,%s\n' \
                    "$(echo "$instance" | sed 's/"/""/g' | awk '{print "\"" $0 "\""}')" \
                    "$(echo "$profile_name" | sed 's/"/""/g' | awk '{print "\"" $0 "\""}')" \
                    "$(echo "$domain" | sed 's/"/""/g' | awk '{print "\"" $0 "\""}')" \
                    "$(echo "$key" | sed 's/"/""/g' | awk '{print "\"" $0 "\""}')" \
                    "$(echo "$value" | sed 's/"/""/g' | awk '{print "\"" $0 "\""}')" \
                    "$(echo "$default_value" | sed 's/"/""/g' | awk '{print "\"" $0 "\""}')"
            done < "$temp_output_dir/tsv_rows.txt"
        done
    } > "$CSV_OUTPUT"

    if [[ $? -eq 0 ]] && [[ -f "$CSV_OUTPUT" ]]; then
        # Check if CSV has more than just the header
        local line_count
        line_count=$(wc -l < "$CSV_OUTPUT")
        if [[ $line_count -gt 1 ]]; then
            echo "CSV report written to: $CSV_OUTPUT"
            return 0
        else
            echo "No conflicts to write."
            return 1
        fi
    else
        echo "ERROR: Failed to generate CSV report."
        return 1
    fi
}

# --------------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------------

while [[ "$#" -gt 0 ]]; do
    key="$1"
    case $key in
        --url)
            shift
            JAMF_URL="$1"
            ;;
        --username)
            shift
            JAMF_USERNAME="$1"
            ;;
        --password)
            shift
            JAMF_PASSWORD="$1"
            ;;
        -v|--verbose)
            VERBOSE=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --output)
            shift
            CSV_OUTPUT="$1"
            ;;
        --existing-output-dir)
            shift
            EXISTING_OUTPUT_DIR="$1"
            ;;
        --domain)
            shift
            FILTER_DOMAIN="$1"
            ;;
        --get-defaults)
            GET_DEFAULTS=1
            ;;
        --tcc)
            INCLUDE_TCC=1
            ;;
        -v*)
            VERBOSE="$1"
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

CSV_OUTPUT="${CSV_OUTPUT:-$default_csv_output}"

# Validate required parameters (unless using existing output directory)
if [[ -z "$EXISTING_OUTPUT_DIR" ]]; then
    # Prompt for URL if not provided
    if [[ -z "$JAMF_URL" ]]; then
        read -r -p "Jamf Pro URL (e.g., https://instance.jamfcloud.com): " JAMF_URL
        if [[ -z "$JAMF_URL" ]]; then
            echo "ERROR: URL is required"
            exit 1
        fi
    fi

    # Prompt for username if not provided
    if [[ -z "$JAMF_USERNAME" ]]; then
        read -r -p "Jamf Pro API Username: " JAMF_USERNAME
        if [[ -z "$JAMF_USERNAME" ]]; then
            echo "ERROR: Username is required"
            exit 1
        fi
    fi

    # Prompt for password if not provided
    if [[ -z "$JAMF_PASSWORD" ]]; then
        read -r -s -p "Jamf Pro API Password: " JAMF_PASSWORD
        echo  # New line after password input
        if [[ -z "$JAMF_PASSWORD" ]]; then
            echo "ERROR: Password is required"
            exit 1
        fi
    fi
fi

# Ensure CSV output directory exists
csv_output_dir=$(dirname "$CSV_OUTPUT")
if [[ ! -d "$csv_output_dir" ]]; then
    mkdir -p "$csv_output_dir"
fi

echo "Running analysis on instance: $JAMF_URL"

generate_csv_report

# Cleanup
rm -rf "$temp_output_dir"

echo
echo "Finished"
echo
