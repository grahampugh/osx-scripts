#!/bin/zsh
# shellcheck shell=bash

DOCSTRING=<<DOC
apiutil-msu-plan-status.zsh

A script for getting the status of a Jamf Pro MSU plan.
This script requires https://github.com/Jamf-Concepts/apiutil/wiki to be installed and in your PATH. You also need to have added at least one Jamf Pro server to your apiutil config.
DOC

# preset variables
temp_file="/tmp/jamf_api_output.txt"

usage() {
    echo "
$DOCSTRING

Usage: apiutil-msu-plan-status.zsh --target TARGETNAME
Options:
    --target        Specify a target server. Must be a valid entry in your apiutil config.
                    If not specified, it will assume it's not needed as you only have one server configured.
    --dir           Specify a directory to save the output CSV file. Default is /Users/Shared/APIUtilScripts/MSUPlanStatus.
"
}

get_computer_list() {
    # get a list of computers from the JSS
    # now run the command and output the results to a file
    endpoint="/api/preview/computers"
    "$jamfapi" --path "$endpoint" "${args[@]}" > "$temp_file"

    # create a variable containing the json output from $curl_output_file
    computer_results=$(/usr/bin/jq -s '[.[].results[]]' "$temp_file")
    echo "$computer_results" > /tmp/computer_results.json # TEMP
}

get_mobile_device_list() {
    # get a list of mobile devices from the JSS
    # now run the command and output the results to a file
    endpoint="/api/v2/mobile-devices"
    "$jamfapi" --path "$endpoint" "${args[@]}" > "$temp_file"

    # create a variable containing the json output from $curl_output_file
    mobile_device_results=$(/usr/bin/jq -s '[.[].results[]]' "$temp_file")
    echo "$mobile_device_results" > /tmp/device_results.json # TEMP
}

process_output() {
    # create a CSV file to store the output. The name of the file includes the date, time, and subdomain of the JSS instance
    if [[ "$target" ]]; then
        jss_subdomain="_$target"
    else
        jss_subdomain=""
    fi
    # read the output file
    current_datetime=$(date +"%Y-%m-%d_%H-%M-%S")

    # create a CSV file with the name msu_plan_status_<subdomain>_<date>_<time>.csv
    if [[ ! "$csv_dir" ]]; then
        csv_dir="/Users/Shared/APIUtilScripts/MSUPlanStatus"
    fi
    if [[ ! -d "$csv_dir" ]]; then
        echo "Creating directory: $csv_dir"
        mkdir -p "$csv_dir"
    fi

    csv_file_name="msu_plan_status${jss_subdomain}_${current_datetime}.csv"

    # compile the results into a CSV file
    echo "Device ID,Device Name,Device Type,Device Model,Plan UUID,Update Action,Version Type,Specific Version,Max Deferrals,Force Install Local DateTime,State,Error Reasons" > "$csv_dir/$csv_file_name"
    /usr/bin/jq -c '.results[]' "$temp_file" | while IFS= read -r item; do
        device_id=$(echo "$item" | /usr/bin/jq -r '.device.deviceId')
        object_type=$(echo "$item" | /usr/bin/jq -r '.device.objectType')
        plan_uuid=$(echo "$item" | /usr/bin/jq -r '.planUuid')
        update_action=$(echo "$item" | /usr/bin/jq -r '.updateAction')
        version_type=$(echo "$item" | /usr/bin/jq -r '.versionType')
        specific_version=$(echo "$item" | /usr/bin/jq -r '.specificVersion')
        max_deferrals=$(echo "$item" | /usr/bin/jq -r '.maxDeferrals')
        force_install_local_datetime=$(echo "$item" | /usr/bin/jq -r '.forceInstallLocalDateTime')
        state=$(echo "$item" | /usr/bin/jq -r '.status.state')
        error_reasons=$(echo "$item" | /usr/bin/jq -r '.status.errorReasons | join("|")')

        if [[ "$object_type" == "COMPUTER" ]]; then
            echo "Computer ID: $device_id"
            device_name=$(jq -r --arg id "$device_id" '.[] | select(.id == $id) | .name' <<< "$computer_results")
            echo "Computer Name: $device_name"
        elif [[ "$object_type" == "MOBILE_DEVICE" ]]; then
            echo "Device ID: $device_id"
            device_name=$(jq -r --arg id "$device_id" '.[] | select(.id == $id) | .name' <<< "$mobile_device_results")
            device_model=$(jq -r --arg id "$device_id" '.[] | select(.id == $id) | .model' <<< "$mobile_device_results")
            echo "Device Name: $device_name"
            echo "Device Model: $device_model"
        else
            echo "Unknown Object Type: $object_type"
            continue
        fi

        echo "Plan UUID: $plan_uuid"
        echo "Update Action: $update_action"
        echo "Version Type: $version_type"
        if [[ "$specific_version" != "null" ]]; then
            echo "Specific Version: $specific_version"
        fi
        echo "Max Deferrals: $max_deferrals"
        echo "Force Install Local DateTime: $force_install_local_datetime"
        echo "State: $state"
        if [[ "$state" == "PlanFailed" ]]; then
            echo "Error Reasons: $error_reasons"
        fi
        echo

        # append the output to a csv file
        echo "$device_id,$device_name,$(tr '[:upper:]' '[:lower:]' <<< "$object_type"),$device_model,$plan_uuid,$update_action,$version_type,$specific_version,$max_deferrals,$force_install_local_datetime,$state,$error_reasons" >> "$csv_dir/$csv_file_name"
    done

    echo "   [msu_plan_status] CSV file outputted to: $csv_dir/$csv_file_name"
}

## Main Body

# check if apiutil is installed
jamfapi="/Applications/API Utility.app/Contents/MacOS/apiutil"
if ! command -v "$jamfapi" &> /dev/null; then
    echo "jamfapi is not installed. Please install it from https://github.com/Jamf-Concepts/apiutil and ensure it's in your PATH."
    echo
    echo "You can add it to the PATH by running:"
    echo "sh -c \"echo '\\nalias jamfapi=\\\"/Applications/API\\ Utility.app/Contents/MacOS/apiutil\\\"' >> ~/.zshrc\""
    echo "Then restart your terminal or run 'source ~/.zshrc' to apply the changes."
    exit 1
fi
# check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Please run this script on macOS 15 or greater, or manually install jq."
    exit 1
fi

# read inputs
while test $# -gt 0 ; do
    case "$1" in
        -t|--target)
            shift
            target="$1"
            ;;
        -d|--dir)
            shift
            csv_dir="$1"
            ;;
        *)
            usage
            exit
            ;;
    esac
    shift
done

args=()
if [[ "$target" ]]; then
    args+=("--target" "$target")
fi

get_computer_list
get_mobile_device_list

# now run the command and output the results to a file
endpoint="/api/v1/managed-software-updates/plans"
"$jamfapi" --path "$endpoint" "${args[@]}" > "$temp_file"

# now process the output
if [[ ! -s "$temp_file" ]]; then
    echo "No results found or the output file is empty."
    exit 0
fi
process_output

# open the CSV file in the default application
if [[ -f "$csv_dir/$csv_file_name" ]]; then
    echo "Opening CSV file: $csv_dir/$csv_file_name"
    open "$csv_dir/$csv_file_name"
else
    echo "CSV file not found: $csv_dir/$csv_file_name"
fi
# clean up temporary files
rm -f "$temp_file" 
