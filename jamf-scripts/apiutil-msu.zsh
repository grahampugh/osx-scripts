#!/bin/zsh
# shellcheck shell=bash

DOCSTRING=<<DOC
apiutil-msu.zsh

A script for getting the status of Jamf Pro MSU plans and updates.
This script requires https://github.com/Jamf-Concepts/apiutil/wiki to be installed and in your PATH. You also need to have added at least one Jamf Pro server to your apiutil config.
DOC

# preset variables
temp_file="/tmp/jamf_api_output.txt"

usage() {
    echo "
$DOCSTRING

Usage: apiutil-msu.zsh [--target TARGETNAME] [-p|--plan] [-s|--status] [--dir DIRECTORY]
Options:
    -t, --target    Specify a target server. Must be a valid entry in your apiutil config.
                    Not required if only one server has been configured in API Utility.
    -p, --plan      Fetch MSU plans.
    -o, --open      Open the output CSV file in the default application.
    -e, --event     Include event details in the output CSV file.
                    This will add additional columns for plan events.
    -s, --status    Fetch MSU update statuses.
    -d, --dir       Specify a directory to save the output CSV file. Default is /Users/Shared/APIUtilScripts/MSUPlanStatus.

    Note that only one of -p or -s can be used at a time.
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

create_csv_dir() {
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
        csv_dir="/Users/Shared/APIUtilScripts/MSURequests"
    fi
    if [[ ! -d "$csv_dir" ]]; then
        echo "Creating directory: $csv_dir"
        mkdir -p "$csv_dir"
    fi
}

process_plan_output() {
    # create a CSV file to store the output. The name of the file includes the date, time, and subdomain of the JSS instance
    create_csv_dir
    csv_file_name="msu_plans${jss_subdomain}_${current_datetime}.csv"

    # compile the results into a CSV file
    if [[ "$events" == "true" ]]; then
        echo "Device ID,Device Name,Device Type,Device Model,Plan UUID,Update Action,Version Type,Specific Version,Max Deferrals,Force Install Local DateTime,State,Error Reasons,Plan Created,Plan Accepted,Plan Started,Declarative Command Queued,DDM Plan Scheduled,Plan Rejected" > "$csv_dir/$csv_file_name"
    else
        echo "Device ID,Device Name,Device Type,Device Model,Plan UUID,Update Action,Version Type,Specific Version,Max Deferrals,Force Install Local DateTime,State,Error Reasons" > "$csv_dir/$csv_file_name"
    fi
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
        if [[ "$events" == "true" ]]; then
            # get the event details if events are enabled
            get_event "$plan_uuid"
            echo "$device_id,$device_name,$(tr '[:upper:]' '[:lower:]' <<< "$object_type"),$device_model,$plan_uuid,$update_action,$version_type,$specific_version,$max_deferrals,$force_install_local_datetime,$state,$error_reasons,$plan_created_event,$plan_accepted_event,$start_plan_event,$queue_declarative_command,$ddm_plan_scheduled_event,$plan_rejected_event" >> "$csv_dir/$csv_file_name"
        fi
        echo "$device_id,$device_name,$(tr '[:upper:]' '[:lower:]' <<< "$object_type"),$device_model,$plan_uuid,$update_action,$version_type,$specific_version,$max_deferrals,$force_install_local_datetime,$state,$error_reasons" >> "$csv_dir/$csv_file_name"
    done

    echo "   [msu_plan_status] CSV file outputted to: $csv_dir/$csv_file_name"
}

get_event() {
    # if an event UUID is provided, search for the event in the temp_file and use the api/v1/managed-software-updates/plans/$plan_uuid/events endpoint to get the event details (currently commented out because jamfapi is not successfully returning events)
    local event="$1"
    if [[ "$events" == "true" ]]; then
        echo "Searching for event UUID: $event"
        # now run the command and output the results to a file
        endpoint="/api/v1/managed-software-updates/plans"
        "$jamfapi" --path "$endpoint/$event/events" "${args[@]}" > "$temp_file"
    fi
    if [[ -s "$temp_file" ]]; then
        # parse the event details from the temp_file
        event_details=$(jq -r .events "$temp_file")
        if [[ -n "$event_details" ]]; then
            # echo "Event Store: $event_details" # TEMP
            # using jq, parse the event details to get the types and their associated eventReceivedEpoch
            # convert the eventReceivedEpoch to a human-readable format
            plan_created_event=""
            plan_accepted_event=""
            start_plan_event=""
            queue_declarative_command=""
            ddm_plan_scheduled_event=""
            plan_rejected_event=""
            echo "Event Details:"
            # using jq to format the output
            jq -r '.events[] | "\(.type): \(.eventReceivedEpoch)"' <<< "$event_details" | while read -r line; do
                event_type=$(echo "$line" | cut -d':' -f1)
                event_epoch=$(echo "$line" | cut -d':' -f2 | xargs) # xargs to trim whitespace
                if [[ "$event_epoch" == "null" ]]; then
                    event_date="None"
                else
                    event_date=$(date -r $((event_epoch/1000)) +"%Y-%m-%d %H:%M:%S")
                fi
                # echo "${event_type/\./}: $event_date"
                case "$event_type" in
                    ".PlanCreatedEvent")
                        echo "Plan Created: $event_date"
                        plan_created_event="$event_date"
                        ;;
                    ".PlanAcceptedEvent")
                        echo "Plan Accepted: $event_date"
                        plan_accepted_event="$event_date"
                        ;;
                    ".StartPlanEvent")
                        echo "Plan Started: $event_date"
                        start_plan_event="$event_date"
                        ;;
                    ".QueueDeclarativeCommand")
                        echo "Declarative Command Queued: $event_date"
                        queue_declarative_command="$event_date"
                        ;;
                    ".DDMPlanScheduledEvent")
                        echo "DDM Plan Scheduled: $event_date"
                        ddm_plan_scheduled_event="$event_date"
                        ;;
                    ".PlanRejectedEvent")
                        echo "Plan Rejected: $event_date"
                        plan_rejected_event="$event_date"
                        ;;
                    *)
                        echo "Event Type $event_type: $event_date"
                        ;;
                esac
            done
        fi
    else
        echo "No event found with UUID: $event"
    fi
}

process_status_output() {
    create_csv_dir
    csv_file_name="msu_statuses${jss_subdomain}_${current_datetime}.csv"

    # compile the results into a CSV file
    echo "Device ID,Device Name,Device Type,Device Model,Downloaded,Percent Complete,Product Key,Status,Max Deferrals,Next Scheduled Install" > "$csv_dir/$csv_file_name"
    /usr/bin/jq -c '.results[]' "$temp_file" | while IFS= read -r item; do
        device_id=$(echo "$item" | /usr/bin/jq -r '.device.deviceId')
        object_type=$(echo "$item" | /usr/bin/jq -r '.device.objectType')
        max_deferrals=$(echo "$item" | /usr/bin/jq -r '.maxDeferrals')
        next_scheduled_install=$(echo "$item" | /usr/bin/jq -r '.nextScheduledInstall')
        downloaded=$(echo "$item" | /usr/bin/jq -r '.downloaded')
        percent_complete=$(echo "$item" | /usr/bin/jq -r '.downloadPercentComplete')
        product_key=$(echo "$item" | /usr/bin/jq -r '.productKey')
        status=$(echo "$item" | /usr/bin/jq -r '.status')
    
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

        echo "Downloaded: $downloaded"
        echo "Percent Complete: $percent_complete"
        echo "Product Key: $product_key"
        echo "Status: $status"
        echo "Max Deferrals: $max_deferrals"
        echo "Next Scheduled Install: $next_scheduled_install"
        echo
        # append the output to a csv file
        echo "$device_id,$device_name,$(tr '[:upper:]' '[:lower:]' <<< "$object_type"),$device_model,$downloaded,$percent_complete,$product_key,$status,$max_deferrals,$next_scheduled_install" >> "$csv_dir/$csv_file_name"
    done
    echo "   [msu_statuses] CSV file outputted to: $csv_dir/$csv_file_name"
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
        -p|plan)
            option="plan"
            ;;
        -s|status)
            option="status"
            ;;
        -o|--open)
            open_csv=true
            ;;
        -e|--event)
            events="true"
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

if [[ -z "$option" ]]; then
    echo "No option specified. Please use -p for plan or -s for status."
    usage
    exit 1
fi

if [[ "$option" == "plan" ]]; then
    echo "Fetching MSU plans..."
    endpoint="/api/v1/managed-software-updates/plans"
elif [[ "$option" == "status" ]]; then
    echo "Fetching MSU update statuses..."
    endpoint="/api/v1/managed-software-updates/update-statuses"
else
    echo "Invalid option specified. Please use -p for plan or -s for status."
    usage
    exit 1
fi
# now run the command and output the results to a file
"$jamfapi" --path "$endpoint" "${args[@]}" > "$temp_file"

# now process the output
if [[ ! -s "$temp_file" || "$(cat "$temp_file")" == "no objects" ]]; then
    echo "No results found or the output file is empty."
    exit 0
fi

if [[ "$option" == "plan" ]]; then
    process_plan_output
elif [[ "$option" == "status" ]]; then
    process_status_output
fi

# open the CSV file in the default application
if [[ -f "$csv_dir/$csv_file_name" ]]; then
    if [[ "$open_csv" == "true" ]]; then
        echo "Opening CSV file: $csv_dir/$csv_file_name"
        open "$csv_dir/$csv_file_name"
    else
        echo "CSV file created: $csv_dir/$csv_file_name"
    fi
else
    echo "CSV file not found: $csv_dir/$csv_file_name"
fi
# clean up temporary files
# rm -f "$temp_file" 
