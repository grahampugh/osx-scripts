#!/bin/zsh
# shellcheck shell=bash

DOCSTRING=<<DOC
jamf-mdm-commands.zsh

A script for running various MDM commands in Jamf Pro. Currently supports:
- Redeploying the MDM profile
- Setting (or clearing) the Recovery Lock password

This script requires https://github.com/Jamf-Concepts/apiutil/wiki to be installed and in your PATH. You also need to have added at least one Jamf Pro server to your apiutil config.
DOC

# preset variables
temp_file="/tmp/jamf_api_output.txt"

usage() {
    echo "
$DOCSTRING

Usage: jamf-mdm-commands.zsh --jss SERVERURL --user USERNAME --pass PASSWORD --id ID
Options:
    --redeploy      Redeploy the MDM profile
    --recovery      Set the recovery lock password - supplied with:
                    --recovery-lock-password PASSWORD

https:// is optional, it will be added if absent.

SERVERURL, ID, USERNAME, PASSWORD and the option will be asked for if not supplied.
Recovery lock password will be random unless set with --recovery-lock-password.
You can clear the recovery lock password with --clear-recovery-lock-password
"
}

check_environment() {
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
}

redeploy_mdm() {
    # redeploy MDM profile

    # now run the command and output the results to a file
    endpoint="/api/v1/jamf-management-framework/redeploy"
    "$jamfapi" --path "$endpoint/$id" "${args[@]}" > "$temp_file"
    
    echo
    echo "HTTP response: $(cat "$temp_file")"
}

get_computer_list() {
    # get a list of computers from the JSS
    # now run the command and output the results to a file
    endpoint="/api/preview/computers"
    "$jamfapi" --path "$endpoint" "${args[@]}" > "$temp_file"

    # create a variable containing the json output from $curl_output_file
    computer_results=$(cat "$temp_file")
    echo "$computer_results" > /tmp/computer_results.json # TEMP
}

set_recovery_lock() {
    # to set the recovery lock, we need to find out the management id
    # The Jamf Pro API returns a list of all computers.

    if [[ ! $id ]]; then
        echo "No ID supplied, please provide a computer ID:"
        read -r id
        if [[ ! $id ]]; then
            echo "No ID supplied, exiting..."
            exit 1
        fi
    fi

    get_computer_list
    # how big should the loop be?
    loopsize=$( jq .totalCount <<< "$computer_results" )
    echo "Total computers found: $loopsize"
    if [[ $loopsize -eq 0 ]]; then
        echo "No computers found in the JSS!"
        exit 1
    fi

    computer_name=$(jq -r --arg id "$id" '.results.[] | select(.id == $id) | .name' <<< "$computer_results")
    if [[ ! $computer_name ]]; then
        echo "No computer found with ID $id"
        exit 1
    fi
    echo "Computer name: $computer_name"
    # now we need to find the management ID for the computer
    management_id=$(jq -r --arg id "$id" '.results.[] | select(.id == $id) | .managementId' <<< "$computer_results")

    if [[ $management_id ]]; then
        echo "Management ID found: $management_id"
    else
        echo "Management ID not found :-("
        echo
        exit 1
    fi

    # we need to set the recovery lock password if not already set
    if [[ ! $recovery_lock_password ]]; then
        # random or set a specific password?
        printf 'Select [R] for random password, [C] to clear the current password, or enter a specific password : '
        read -r -s action_question
        case "$action_question" in
            C|c)
                recovery_lock_password=""
                ;;
            R|r)
                recovery_lock_password=$( base64 < /dev/urandom  | tr -dc '[:alpha:]' | fold -w ${1:-20} | head -n 1 )
                ;;
            *)
                recovery_lock_password="$action_question"
                ;;
        esac
        echo
    elif [[ "$recovery_lock_password" == "RANDOM" ]]; then
        recovery_lock_password=$( base64 < /dev/urandom  | tr -dc '[:alpha:]' | fold -w ${1:-20} | head -n 1 )
    fi
    if [[ ! $recovery_lock_password || $recovery_lock_password == "NA" ]]; then
        echo "Recovery lock will be removed..."
    else
        echo "Recovery password: $recovery_lock_password"
    fi

    # now issue the recovery lock

    # now run the command and output the results to a file
    endpoint="/api/v2/mdm/commands"
    args+=("--method" "POST")
    args+=("--data")
    args+=('{
        "clientData": [
            {
                "managementId": "'$management_id'",
                "clientType": "COMPUTER"
            }
        ],
        "commandData": {
            "commandType": "SET_RECOVERY_LOCK",
            "newPassword": "'$recovery_lock_password'"
        }
    }')
    "$jamfapi" --path "$endpoint" "${args[@]}" > "$temp_file"
    echo
    echo "HTTP response: $(cat "$temp_file")"
}


## Main Body

check_environment

mdm_command=""

# read inputs
while test $# -gt 0 ; do
    case "$1" in
        -t|--target)
            shift
            target="$1"
            ;;
        -i|--id)
            shift
            id="$1"
            ;;
        --redeploy|--redeploy-mdm)
            mdm_command="redeploy"
            ;;
        --recovery|--recovery-lock)
            mdm_command="recovery"
            ;;
        --recovery-lock-password)
            shift
            recovery_lock_password="$1"
            ;;
        --random|--random-lock-password)
            recovery_lock_password="RANDOM"
            ;;
        --clear-recovery-lock-password)
            recovery_lock_password="NA"
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

if [[ ! $mdm_command ]]; then
    echo
    printf 'Select from [M] Redeploy MDM profile, or [R] Set Recovery Lock : '
    read -r action_question

    case "$action_question" in
        M|m)
            mdm_command="redeploy"
            ;;
        R|r)
            mdm_command="recovery"
            ;;
        *)
            echo
            echo "No valid action chosen!"
            exit 1
            ;;
    esac
fi

echo

# the following section depends on the chosen MDM command
case "$mdm_command" in
    redeploy)
        echo "Redeploying MDM profile"
        redeploy_mdm
        ;;
    recovery)
        echo "Setting recovery lock"
        set_recovery_lock
        ;;
esac

