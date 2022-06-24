#!/bin/zsh
# shellcheck shell=bash

DOCSTRING=<<DOC
jamf-mdm-commands.zsh

A script for running various MDM commands in Jamf Pro. Currently supports:
- Redeploying the MDM profile
- Setting (or clearing) the Recovery Lock password

Actions:
- Checks if we already have a token
- Grabs a new token if required using basic auth
- Works out the Jamf Pro version, quits if too old for the required command
- Posts the MDM command request
DOC

# preset variables
temp_file="/tmp/jamf_api_output.txt"
token_file="/tmp/jamf_api_token.txt"
server_check_file="/tmp/jamf_server_check.txt"
user_check_file="/tmp/jamf_user_check.txt"


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


# ljt section
: <<-LICENSE_BLOCK
ljt.min - Little JSON Tool (https://github.com/brunerd/ljt) Copyright (c) 2022 Joel Bruner (https://github.com/brunerd). Licensed under the MIT License. Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
LICENSE_BLOCK

#v1.0.3 - use the minified function below to embed ljt into your shell script
ljt() ( 
	[ -n "${-//[^x]/}" ] && set +x; read -r -d '' JSCode <<-'EOT'
	try {var query=decodeURIComponent(escape(arguments[0]));var file=decodeURIComponent(escape(arguments[1]));if (query[0]==='/'){ query = query.split('/').slice(1).map(function (f){return "["+JSON.stringify(f)+"]"}).join('')}if(/[^A-Za-z_$\d\.\[\]'"]/.test(query.split('').reverse().join('').replace(/(["'])(.*?)\1(?!\\)/g, ""))){throw new Error("Invalid path: "+ query)};if(query[0]==="$"){query=query.slice(1,query.length)};var data=JSON.parse(readFile(file));var result=eval("(data)"+query)}catch(e){printErr(e);quit()};if(result !==undefined){result!==null&&result.constructor===String?print(result): print(JSON.stringify(result,null,2))}else{printErr("Node not found.")}
	EOT
	queryArg="${1}"; fileArg="${2}";jsc=$(find "/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/" -name 'jsc');[ -z "${jsc}" ] && jsc=$(which jsc);{ [ -f "${queryArg}" ] && [ -z "${fileArg}" ]; } && fileArg="${queryArg}" && unset queryArg;if [ -f "${fileArg:=/dev/stdin}" ]; then { errOut=$( { { "${jsc}" -e "${JSCode}" -- "${queryArg}" "${fileArg}"; } 1>&3 ; } 2>&1); } 3>&1;else { errOut=$( { { "${jsc}" -e "${JSCode}" -- "${queryArg}" "/dev/stdin" <<< "$(cat)"; } 1>&3 ; } 2>&1); } 3>&1; fi;if [ -n "${errOut}" ]; then /bin/echo "$errOut" >&2; return 1; fi
)


get_new_token() {
    if [[ ! $pass ]]; then
        printf '%s ' "Enter password for $user : "
        read -r -s pass
        if [[ ! $pass ]]; then
            echo "No password entered. Quitting."
            exit 1
        fi
    fi

    # generate a b64 hash of the credentials
    credentials=$(printf "%s" "$user:$pass" | iconv -t ISO-8859-1 | base64 -i -)

    # request the token
    curl --location --silent \
        --request POST \
        --header "authorization: Basic $credentials" \
        --url "$url/api/v1/auth/token" \
        --header 'Accept: application/json' \
        -o "$token_file"
    echo "$url" > "$server_check_file"
    echo "$user" > "$user_check_file"
}


check_token() {
    # is there a token file
    if [[ -f "$token_file" ]]; then
        # check we are still querying the same server and with the same account
        server_check=$( cat "$server_check_file" )
        user_check=$( cat "$user_check_file" )
        if [[ "$server_check" == "$url" && "$user_check" == "$user" ]]; then
            token=$(plutil -extract token raw "$token_file")
            expires=$(plutil -extract expires raw "$token_file")

            now=$(date -u +"%Y-%m-%dT%H:%M:%S")
            echo
            if [[ $expires < $now ]]; then
                echo "token expired or invalid ($expires v $now). Grabbing a new one"
                get_new_token
            else
                echo "Existing token still valid"
            fi
        else
            echo "Token does not match current URL or user. Grabbing a new one."
            get_new_token
        fi
    else
        echo "No token found. Grabbing a new one"
        get_new_token
    fi

    token=$(plutil -extract token raw "$token_file")
}


jamf_version_ok() {
    # check the Jamf Pro version

    min_version_for_command=$1

    curl --location --silent \
        --request GET \
        --header "authorization: Bearer $token" \
        --url "$url/api/v1/jamf-pro-version" \
        --header 'Accept: application/json' \
        -o "$temp_file"

    jss_version_raw=$(plutil -extract version raw "$temp_file")

    rm "$temp_file"

    # remove timestamp from Jamf Pro version
    jss_version="${jss_version_raw%%"-t"*}"

    # remove beta stamp from Jamf Pro version
    jss_version="${jss_version_raw%%"-b"*}"

    echo
    echo "Jamf Pro Version = $jss_version"

    # split the version string into an array of major, minor and patch version
    IFS=.
    read -r -A version_array <<<"$jss_version"
    IFS=''

    if [[ ${version_array[1]} -lt 10 || (${version_array[1]} -eq 10 && ${version_array[2]} -lt $min_version_for_command) ]]; then
        echo "$endpoint requires Jamf Pro 10.$min_version_for_command or greater. Quitting."
        exit 1
    fi
}


redeploy_mdm() {
    # check jamf version
    jamf_version_ok 36

    # redeploy MDM profile
    endpoint="api/v1/jamf-management-framework/redeploy"
    http_response=$(
        curl --location --silent \
            --request POST \
            --header "authorization: Bearer $token" \
            --header 'Accept: application/json' \
            "$url/$endpoint/$id"
    )
    echo
    echo "HTTP response: $http_response"
}


set_recovery_lock() {
    # check jamf version
    jamf_version_ok 32
    
    # to set the recovery lock, we need to find out the management id
    # The Jamf Pro API returns a list of all computers.
    endpoint="api/preview/computers"
    url_filter="?page=0&page-size=1000&sort=id"
    curl --location  --silent \
        --request GET \
        --header "authorization: Bearer $token" \
        --header 'Accept: application/json' \
        "$url/$endpoint/$url_filter" \
        -o "$temp_file"
        
    # we have to loop through this to find the ID we want :-/
    results=$( ljt /results < "$temp_file" )
    # how big should the loop be?
    loopsize=$( grep -c '"id"' <<< "$results" )
    # now loop through and find the correct ID
    i=0
    while [[ $i -lt $loopsize ]]; do
        id_in_list=$( ljt /$i/id <<< "$results" )
        # echo "ID being checked: $id_in_list (vs. $id)"
        if [[ $id_in_list -eq $id ]]; then
            computer_name=$( ljt /$i/name <<< "$results" )
            management_id=$( ljt /$i/managementId <<< "$results" )
            break
        fi
        i=$((i+1))
    done

    if [[ $management_id ]]; then
        echo "Management ID found: $management_id"
    else
        echo "Management ID not found :-("
        # echo
        # echo "$results"
        echo
        exit 1
    fi

    # we need to set the recovery loack password if not already set
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
    endpoint="api/preview/mdm/commands"
    http_response=$(
        curl --location --silent \
            --request POST \
            --header "authorization: Bearer $token" \
            --header 'Content-Type: application/json' \
            --data-raw '{
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
            }' \
            "$url/$endpoint" 
    )
    echo
    echo "HTTP response: $http_response"
}


## Main Body
mdm_command=""
recovery_lock_password=""

# read inputs
while test $# -gt 0 ; do
    case "$1" in
        -s|--jss|--url)
            shift
            jss="$1"
            ;;
        -u|--user)
            shift
            user="$1"
            ;;
        -p|--pass)
            shift
            pass="$1"
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

# ask for any missing inputs
if [[ ! $jss ]]; then
    printf '%s ' "Enter URL : "
    read -r jss
    if [[ ! $jss ]]; then
        echo "No URL entered. Quitting."
        exit 1
    fi
fi

if [[ ! $id ]]; then
    printf '%s ' "Enter Computer ID : "
    read -r id
    if [[ ! $id ]]; then
        echo "No Computer ID entered. Quitting."
        exit 1
    fi
fi

if [[ ! $user ]]; then
    printf '%s ' "Enter username for $jss : "
    read -r user
    if [[ ! $user ]]; then
        echo "No username entered. Quitting."
        exit 1
    fi
fi

# build a valid URL
if [[ "$url" != "https://"* ]]; then
    url="https://$jss"
else
    url="$jss"
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

# get a valid token
check_token

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

