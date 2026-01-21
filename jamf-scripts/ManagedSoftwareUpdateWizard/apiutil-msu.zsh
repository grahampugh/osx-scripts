#!/bin/zsh
# shellcheck shell=bash

DOCSTRING=<<DOC
apiutil-msu.zsh

A script for getting the status of Jamf Pro MSU plans and updates.
This script requires https://github.com/Jamf-Concepts/apiutil/wiki to be installed and in your PATH. You also need to have added at least one Jamf Pro server to your apiutil config.
DOC

# preset variables
temp_file="/tmp/jamf_api_output.txt"
log_file="/tmp/jamf_api_log.txt"

usage() {
    echo "
$DOCSTRING

Usage: apiutil-msu.zsh [--target TARGETNAME] [-p|--plan] [-s|--status] [--dir DIRECTORY]
Options:
    -t, --target            Specify a target server. 
                            Must be a valid entry in your apiutil config.
                            Not required if only one server has been configured in API Utility.
    -c, --create            Create a new MSU plan. Requires -g, -v, and -f options. 
                            Note: Only a scheduled install plan can be created with this script.
    -d, --device-type
                            Specify the device type to create a plan for. Options are COMPUTER, MOBILE_DEVICE, or APPLE_TV.
                            Default is COMPUTER.
    -g, --group             Specify the computer or mobile device group name to create a plan for. 
                            Required for creating a plan.
    -v, --version-type
                            Specify the version type for the plan. Options are LATEST_ANY, LATEST_MAJOR, LATEST_MINOR, or SPECIFIC_VERSION.
    -sv, --specific-version
                            Specify the specific version for the plan. Required if version type is SPECIFIC_VERSION.
    -i, --days-until-force-install
                            Specify the number of days until the force install local date/time. 
                            Default is 7 days from now.
                            This will be used to schedule the install.
    -p, --plan              Fetch MSU plans.
    -o, --open              Open the output CSV file in the default application.
    -e, --events            Include event details in the output CSV file.
                            This will add additional columns for plan events.
    -s, --status            Fetch MSU update statuses.
    -d, --dir               Specify a directory to save the output CSV file. 
                            Default is /Users/Shared/APIUtilScripts/MSUPlanStatus.
    --toggle                Toggle Software Update Plan Feature
                            This will toggle the feature on or off, clearing any plans
                                  that may be set. 

    Note that only one of -c, -p or -s can be used at a time.
"
}

get_computer_list() {
    # get a list of computers from the JSS
    # now run the command and output the results to a file
    endpoint="/api/preview/computers"
    "$jamfapi" --path "$endpoint" "${args[@]}" 2>&1 | grep -v '^\[retrieve\]' > "$temp_file"

    # create a variable containing the json output from $curl_output_file
    computer_results=$(/usr/bin/jq -s '[.[].results[]]' "$temp_file" 2>/dev/null)
    echo "$computer_results" > /tmp/computer_results.json # TEMP
}

get_mobile_device_list() {
    # get a list of mobile devices from the JSS
    # now run the command and output the results to a file
    endpoint="/api/v2/mobile-devices"
    "$jamfapi" --path "$endpoint" "${args[@]}" 2>&1 | grep -v '^\[retrieve\]' > "$temp_file"

    # create a variable containing the json output from $curl_output_file
    mobile_device_results=$(/usr/bin/jq -s '[.[].results[]]' "$temp_file" 2>/dev/null)
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
    /usr/bin/jq -c '.results[]' "$temp_file" 2>/dev/null | while IFS= read -r item; do
        device_id=$(echo "$item" | /usr/bin/jq -r '.device.deviceId' 2>/dev/null)
        object_type=$(echo "$item" | /usr/bin/jq -r '.device.objectType' 2>/dev/null)
        plan_uuid=$(echo "$item" | /usr/bin/jq -r '.planUuid' 2>/dev/null)
        update_action=$(echo "$item" | /usr/bin/jq -r '.updateAction' 2>/dev/null)
        version_type=$(echo "$item" | /usr/bin/jq -r '.versionType' 2>/dev/null)
        specific_version=$(echo "$item" | /usr/bin/jq -r '.specificVersion' 2>/dev/null)
        max_deferrals=$(echo "$item" | /usr/bin/jq -r '.maxDeferrals' 2>/dev/null)
        force_install_local_datetime=$(echo "$item" | /usr/bin/jq -r '.forceInstallLocalDateTime' 2>/dev/null)
        state=$(echo "$item" | /usr/bin/jq -r '.status.state' 2>/dev/null)
        error_reasons=$(echo "$item" | /usr/bin/jq -r '.status.errorReasons | join("|")' 2>/dev/null)

        if [[ "$object_type" == "COMPUTER" ]]; then
            echo "Computer ID: $device_id"
            device_name=$(jq -r --arg id "$device_id" '.[] | select(.id == $id) | .name' <<< "$computer_results" 2>/dev/null)
            echo "Computer Name: $device_name"
        elif [[ "$object_type" == "MOBILE_DEVICE" ]]; then
            echo "Device ID: $device_id"
            device_name=$(jq -r --arg id "$device_id" '.[] | select(.id == $id) | .name' <<< "$mobile_device_results" 2>/dev/null)
            device_model=$(jq -r --arg id "$device_id" '.[] | select(.id == $id) | .model' <<< "$mobile_device_results" 2>/dev/null)
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
        else
            echo "$device_id,$device_name,$(tr '[:upper:]' '[:lower:]' <<< "$object_type"),$device_model,$plan_uuid,$update_action,$version_type,$specific_version,$max_deferrals,$force_install_local_datetime,$state,$error_reasons" >> "$csv_dir/$csv_file_name"
        fi
    done

    echo "CSV file outputted to: $csv_dir/$csv_file_name" | tee "$log_file"
}

get_event() {
    # if an event UUID is provided, search for the event in the temp_file and use the api/v1/managed-software-updates/plans/$plan_uuid/events endpoint to get the event details (currently commented out because jamfapi is not successfully returning events)
    local event="$1"
    if [[ "$events" == "true" ]]; then
        echo "Searching for event UUID: $event"
        # now run the command and output the results to a file
        endpoint="/api/v1/managed-software-updates/plans"
        "$jamfapi" --path "$endpoint/$event/events" "${args[@]}" 2>&1 | grep -v '^\[retrieve\]' > "$temp_file"
    fi
    if [[ -s "$temp_file" ]]; then
        # parse the event details from the temp_file
        event_details=$(jq -r .events "$temp_file" 2>/dev/null)
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
            while read -r line; do
                event_type=$(echo "$line" | cut -d':' -f1)
                event_received_epoch=$(echo "$line" | cut -d':' -f2) 
                event_sent_epoch=$(echo "$line" | cut -d':' -f3) 
                # events have a received epoch
                if [[ "$event_received_epoch" == "null" ]]; then
                    event_received_date=""
                else
                    event_received_date=$(date -r $((event_received_epoch/1000)) +"%Y-%m-%d %H:%M:%S")
                fi
                # commands have a sent epoch
                if [[ "$event_sent_epoch" == "null" ]]; then
                    event_sent_date=""
                else
                    event_sent_date=$(date -r $((event_sent_epoch/1000)) +"%Y-%m-%d %H:%M:%S")
                fi
                case "$event_type" in
                    ".PlanCreatedEvent")
                        echo "Plan Created: $event_received_date"
                        plan_created_event="$event_received_date"
                        ;;
                    ".PlanAcceptedEvent")
                        echo "Plan Accepted: $event_received_date"
                        plan_accepted_event="$event_received_date"
                        ;;
                    ".StartPlanEvent")
                        echo "Plan Started: $event_received_date"
                        start_plan_event="$event_received_date"
                        ;;
                    ".QueueDeclarativeCommand")
                        echo "Declarative Command Queued: $event_sent_date"
                        queue_declarative_command="$event_sent_date"
                        ;;
                    ".DDMPlanScheduledEvent")
                        echo "DDM Plan Scheduled: $event_received_date"
                        ddm_plan_scheduled_event="$event_received_date"
                        ;;
                    ".PlanRejectedEvent")
                        echo "Plan Rejected: $event_received_date"
                        plan_rejected_event="$event_received_date"
                        ;;
                    *"Event")
                        echo "Event Type $event_type: $event_received_date"
                        ;;
                    *"Command")
                        echo "Command Type $event_type: $event_sent_date"
                        ;;
                    *)
                        echo "Unknown Event Type: $event_type"
                        ;;
                esac
            done < <(jq -r '.events[] | "\(.type):\(.eventReceivedEpoch):\(.eventSentEpoch)"' <<< "$event_details" 2>/dev/null)
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
    /usr/bin/jq -c '.results[]' "$temp_file" 2>/dev/null | while IFS= read -r item; do
        device_id=$(echo "$item" | /usr/bin/jq -r '.device.deviceId' 2>/dev/null)
        object_type=$(echo "$item" | /usr/bin/jq -r '.device.objectType' 2>/dev/null)
        max_deferrals=$(echo "$item" | /usr/bin/jq -r '.maxDeferrals' 2>/dev/null)
        next_scheduled_install=$(echo "$item" | /usr/bin/jq -r '.nextScheduledInstall' 2>/dev/null)
        downloaded=$(echo "$item" | /usr/bin/jq -r '.downloaded' 2>/dev/null)
        percent_complete=$(echo "$item" | /usr/bin/jq -r '.downloadPercentComplete' 2>/dev/null)
        product_key=$(echo "$item" | /usr/bin/jq -r '.productKey' 2>/dev/null)
        status=$(echo "$item" | /usr/bin/jq -r '.status' 2>/dev/null)
    
        if [[ "$object_type" == "COMPUTER" ]]; then
            echo "Computer ID: $device_id"
            device_name=$(jq -r --arg id "$device_id" '.[] | select(.id == $id) | .name' <<< "$computer_results" 2>/dev/null)
            echo "Computer Name: $device_name"
        elif [[ "$object_type" == "MOBILE_DEVICE" ]]; then
            echo "Device ID: $device_id"
            device_name=$(jq -r --arg id "$device_id" '.[] | select(.id == $id) | .name' <<< "$mobile_device_results" 2>/dev/null)
            device_model=$(jq -r --arg id "$device_id" '.[] | select(.id == $id) | .model' <<< "$mobile_device_results" 2>/dev/null)
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
    echo "CSV file outputted to: $csv_dir/$csv_file_name" | tee "$log_file"
}

create_plan() {
    # create a plan for the MSU updates
    # The required inputs are the group ID, the version type, the specific version if version type is "SPECIFIC_VERSION", and the Force Install Local DateTime.
    # now run the command and output the results to a file
    device_type=$(tr '[:lower:]' '[:upper:]' <<< "$device_type")
    endpoint="/api/v1/managed-software-updates/plans/group"
    args+=("--method" "POST")
    args+=("--data")
    args+=('{
        "group": {
            "objectType": "'"$device_type"'_GROUP",
            "groupId": "'"$group_id"'"
        },
        "config": {
            "updateAction": "DOWNLOAD_INSTALL_SCHEDULE",
            "versionType": "'"$version_type"'",
            "specificVersion": "'"$specific_version"'",
            "forceInstallLocalDateTime": "'"$force_install_local_datetime"'"
        }
    }'
    )

    # show args
    echo "Creating plan with the following parameters:"
    echo "${args[*]}" # TEMP

    # check if the plan was created successfully
    if "$jamfapi" --path "$endpoint" "${args[@]}"; then
        echo "Plan created successfully." | tee "$log_file"
    else
        echo "Failed to create plan. Please check the parameters and try again." | tee "$log_file"
        exit 1
    fi
}

get_software_update_feature_status() {
    # grab current value
    local temp_toggle_file="/tmp/jamf_api_toggle.txt"
    local temp_status_file="/tmp/jamf_api_status.txt"
    
    endpoint="/api/v1/managed-software-updates/plans/feature-toggle"
    "$jamfapi" --path "$endpoint" "${args[@]}" 2>&1 | grep -v '^\[retrieve\]' > "$temp_toggle_file"
    
    toggle_value=$(jq -r '.toggle' "$temp_toggle_file" 2>/dev/null)
    
    toggle_set_value="true"
    if [[ $toggle_value == "true" ]]; then 
        toggle_set_value="false"
    fi

    echo "Current toggle value is '$toggle_value'."
    echo "Current toggle value is '$toggle_value'." > "$log_file"

    # grab current background status
    endpoint="/api/v1/managed-software-updates/plans/feature-toggle/status"
    "$jamfapi" --path "$endpoint" "${args[@]}" 2>&1 | grep -v '^\[retrieve\]' > "$temp_status_file"

    toggle_on_value=$(jq -r '.toggleOn.formattedPercentComplete' "$temp_status_file" 2>/dev/null)
    toggle_off_value=$(jq -r '.toggleOff.formattedPercentComplete' "$temp_status_file" 2>/dev/null)

    echo "Toggle on status: '$toggle_on_value'..."
    echo "Toggle off status: '$toggle_off_value'..."
}

toggle_software_update_feature() {
    # This function will toggle the "new" software update feature allowing to clear any plans

    echo
    echo "Toggling software update feature..."
    echo "This will toggle the feature on or off, clearing any plans that may be set."
    echo "This endpoint is asynchronous, the provided value will not be immediately updated."
    echo

    # toggle software update feature
    endpoint="/api/v1/managed-software-updates/plans/feature-toggle"
    args+=("--method" "PUT")
    args+=("--data")
    args+=('{"toggle": '$toggle_set_value'}'
    )
    # check if the plan was created successfully
    if "$jamfapi" --path "$endpoint" "${args[@]}"; then
        echo "Request sent successfully. Toggle is now set to '$toggle_set_value'" | tee "$log_file"
    else
        echo "Toggle request failed." | tee "$log_file"
        exit 1
    fi
}

get_list_of_computer_groups() {
    # get a list of computer groups from the JSS
    # now run the command and output the results to a file
    endpoint="/api/v1/computer-groups"
    "$jamfapi" --path "$endpoint" "${args[@]}" 2>&1 | grep -v '^\[retrieve\]' > "$temp_file"

    # create a variable containing the json output from $curl_output_file
    computer_group_results=$(/usr/bin/jq -s '[.[].results[]]' "$temp_file" 2>/dev/null)
    # cp "$temp_file" /tmp/computer_group_results.txt # TEMP
    echo "$computer_group_results" | tee /tmp/computer_group_results.json # TEMP
}

get_list_of_mobile_device_groups() {
    # get a list of mobile device groups from the JSS
    # now run the command and output the results to a file
    endpoint="/api/v1/mobile-device-groups"
    "$jamfapi" --path "$endpoint" "${args[@]}" 2>&1 | grep -v '^\[retrieve\]' > "$temp_file"

    # create a variable containing the json output from $curl_output_file
    mobile_device_group_results=$(/usr/bin/jq -s '[.[].results[]]' "$temp_file" 2>/dev/null)
    echo "$mobile_device_group_results" | tee /tmp/mobile_device_group_results.json # TEMP
}

get_computer_group_id_from_name() {
    # get the computer group ID from the name
    local group_name="$1"
    if [[ -z "$group_name" ]]; then
        echo "No group name provided."
        return 1
    fi
    get_list_of_computer_groups
    group_id=$(jq -r --arg name "$group_name" '.[] | select(.name == $name) | .id' <<< "$computer_group_results" 2>/dev/null | head -n 1)
    if [[ -z "$group_id" ]]; then
        echo "No computer group found with name: $group_name" | tee "$log_file"
        exit 1
    fi
    echo "Group ID: $group_id"
}

get_mobile_device_group_id_from_name() {
    # get the mobile device group ID from the name
    local group_name="$1"
    if [[ -z "$group_name" ]]; then
        echo "No group name provided."
        return 1
    fi
    get_list_of_mobile_device_groups
    group_id=$(jq -r --arg name "$group_name" '.[] | select(.name == $name) | .id' <<< "$mobile_device_group_results" 2>/dev/null | head -n 1)
    if [[ -z "$group_id" ]]; then
        echo "No mobile device group found with name: $group_name" | tee "$log_file"
        exit 1
    fi
    echo "Group ID: $group_id"
}

are_you_sure() {
    if [[ $i_am_sure != "true" ]]; then
        echo
        echo -n "Are you sure you want to perform the action? (Y/N) : "
        read -r sure
        case "$sure" in
            Y|y)
                return
                ;;
            *)
                echo "Action cancelled, quitting"
                exit 
                ;;
        esac
    fi
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
    echo "jq is not installed. Please run this script on macOS 15 or greater, or manually install jq." | tee "$log_file"
    exit 1
fi

# read inputs
while test $# -gt 0 ; do
    case "$1" in
        -t|--target)
            shift
            target="$1"
            ;;
        -c|--create)
            option="create"
            ;;
        -d|--device-type)
            shift
            device_type="$1"
            ;;
        -g|--group)
            shift
            group="$1"
            ;;
        -v|--version-type)
            shift
            version_type="$1"
            ;;
        -sv|--specific-version)
            shift
            specific_version="$1"
            ;;
        -i|--days-until-force-install)
            shift
            days_until_force_install="$1"
            ;;
        -p|--plan)
            option="plan"
            ;;
        -s|--status)
            option="status"
            ;;
        -o|--open)
            open_csv=true
            ;;
        -e|--events)
            events="true"
            ;;
        -d|--dir)
            shift
            csv_dir="$1"
            ;;
        --toggle)
            option="toggle"
            ;;
        --i-am-sure)
            i_am_sure="true"
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

if [[ -z "$option" ]]; then
    echo "No option specified. Please use -c to create a plan, -p for plan statuses or -s for update statuses."
    usage
    exit 1
fi

# check software feature status
get_software_update_feature_status

# first deal with the toggle option
if [[ "$option" == "toggle" ]]; then
    echo "WARNING: Do not proceed if either of the above values is less than 100%"
    are_you_sure
    echo "Toggling Software Update Plan Feature..."
    echo "Current toggle value is '$toggle_value'."
    if [[ "$toggle_value" == "true" ]]; then
        echo "Toggling off the feature..."
        toggle_set_value="false"
    else
        echo "Toggling on the feature..."
        toggle_set_value="true"
    fi
    toggle_software_update_feature
    exit 0
fi

# for the other options, do not proceed if the toggle is in progress or false
if [[ "$toggle_value" == "false" || "$toggle_value" == "in_progress" ]]; then
    echo "The action could not be performed because the Software Update toggle is disabled or in progress. Please run with --toggle to enable it first." | tee "$log_file"
    exit 1
fi

# deal with creating plans next
if [[ "$option" == "create" ]]; then
    echo "Creating MSU plan..."
    if [[ "$device_type" != "COMPUTER" && "$device_type" != "MOBILE_DEVICE" && "$device_type" != "APPLE_TV" && "$device_type" != "computer" && "$device_type" != "mobile_device" && "$device_type" != "apple_tv" ]]; then
        echo "Invalid device type specified. Please use 'COMPUTER', 'MOBILE_DEVICE', or 'APPLE_TV'."
        exit 1
    fi

    if [[ -z "$group" ]]; then
        echo "Group is required to create a plan."
        exit 1
    fi

    if [[ "$version_type" != "LATEST_ANY" && "$version_type" != "LATEST_MAJOR" && "$version_type" != "LATEST_MINOR" && "$version_type" != "SPECIFIC_VERSION" ]]; then
        echo "Invalid version type specified. Please use 'LATEST_ANY', 'LATEST_MAJOR', 'LATEST_MINOR', or 'SPECIFIC_VERSION'."
        exit 1
    fi

    if [[ -z "$specific_version" ]]; then
        if [[ "$version_type" == "SPECIFIC_VERSION" ]]; then
            echo "Specific version is required when version type is 'SPECIFIC_VERSION'." | tee "$log_file"
            exit 1
        else
            specific_version="NO_SPECIFIC_VERSION"
        fi
    fi

    # get group ID from name
    if [[ "$device_type" == "COMPUTER" ]]; then
        get_computer_group_id_from_name "$group"
    else
        get_mobile_device_group_id_from_name "$group"
    fi

    # set force install local datetime (default is 7 days from now)
    if [[ -z "$days_until_force_install" ]]; then
        # set default to 7 days from now
        force_install_local_datetime=$(date -v+7d +"%Y-%m-%dT%H:%M:%S")
    else
        force_install_local_datetime=$(date -v+${days_until_force_install}d +"%Y-%m-%dT%H:%M:%S")
    fi

    # create the plan
    create_plan
    exit 0
fi

get_computer_list
get_mobile_device_list

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
if "$jamfapi" --path "$endpoint" "${args[@]}" 2>&1 | grep -v '^\[retrieve\]' > "$temp_file"; then
    # now process the output
    if [[ ! -s "$temp_file" || "$(cat "$temp_file")" == "no objects" ]]; then
        echo "No results found or the output file is empty."
        echo "No results found or the output file is empty." > "$log_file"
        exit 1
    elif [[ $toggle_value == "false" ]]; then
        echo "The action could not be performed because the Software Update toggle is disabled " | tee "$log_file"
        exit 1
    fi
else
    if [[ $toggle_value == "false" ]]; then
        echo "The action could not be performed because the Software Update toggle is disabled " | tee "$log_file"
        exit 1
    else
        echo "There was an error performing the action." | tee "$log_file"
        exit 1
    fi
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
