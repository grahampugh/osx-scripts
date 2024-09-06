#!/bin/bash
# set -x

# Script for client side testing procedures
# Verifies the correctness of scoping groups depending on state of installation of an application 
#
# Version 1   - 2.9.2020
# Version 1.1 - 5.9.2024


DEFAULTS="/usr/bin/defaults"
JAMF_CMD="/usr/local/jamf/bin/jamf"
PREFS="/Library/Preferences/ch.ethz.id.jamf-auto-tester.plist"
tmp_folder="/private/tmp/jamf-auto-tester"
tmp_log="$tmp_folder/tmp.log"
end_log="$tmp_folder/jamf-auto-tester-final.log"
token_file="$tmp_folder/token.txt"
server_check_file="$tmp_folder/server-check.txt"
user_check_file="$tmp_folder/user-check.txt"
output_file="$tmp_folder/single-test-result.log"

### FUNCTIONS ###

usage() {
    echo
    echo "Usage:"
    echo "./app-installation-tester.sh <options>"
    echo
    echo "      APPNAME                 - Testing installation of Self Service item APPNAME"
    echo "      -a=APPNAME or -a|--app APPNAME"
    echo "                              - Testing installation of Self Service item APPNAME"
    echo
    echo "      -i|--input INPUTFILE    - Specify a file that contains all the applications to be tested "
    echo "                                (as replacement or addition to -a) "
    echo
    echo "      -o=OPTION or -o|--option OPTION     "
    echo
    echo "          OPTION s            - Current state of Self Service item APPNAMEs"
    echo "          OPTION t            - Testing installation of Self Service testing item APPNAMEs"
    echo "          OPTION p            - Testing installation of Self Service productive item APPNAMEs"
    echo "          OPTION u            - Testing uninstaller of Self Service item APPNAMEs"
    echo "          OPTION up           - Testing update of Self Service item APPNAMEs"
    echo "          OPTION testing      - Testing Self Service item APPNAMEs in Testing procedure"
    echo "          OPTION productive   - Testing Self Service item APPNAMEs in Production procedure"
    exit
}

get_credentials() {
    if [[ -f "$PREFS" ]]; then
        jss_api_user=$(${DEFAULTS} read "$PREFS" API_USERNAME)
        jss_api_password=$(${DEFAULTS} read "$PREFS" API_PASSWORD)
    fi

    if [[ ! "$jss_api_user" ]]; then
        read -r -p "Enter API User: " jss_api_user
        echo
        ${DEFAULTS} write "$PREFS" API_USERNAME "$jss_api_user"
    fi
    if [[ ! "$jss_api_password" ]]; then
        read -r -s -p "Enter API Password: " jss_api_password 
        echo
        ${DEFAULTS} write "$PREFS" API_PASSWORD "$jss_api_password"
    fi

    echo "$jss_api_user" > "$user_check_file"       
}

get_new_token() {
    # request the token
    echo "   [get_new_token] Getting token for $jss_url"
    curl_args=(
        --location
        --request POST
        --user "${jss_api_user}:${jss_api_password}"
        --header "Accept: application/json"
        --output "$token_file"
        --url "${jss_url}/api/v1/auth/token"
    )
    if [[ $verbose -ne 1 ]]; then
        curl_args+=("$curl_verbosity")
    fi

    if curl "${curl_args[@]}"; then
        echo "   [get_new_token] Token for $jss_api_user on ${jss_url} written to $token_file"
    else
        echo "   [get_new_token] Token for $jss_api_user on ${jss_url} not written"
        exit 1
    fi
}

check_token() {
    # is there a token file
    echo "   [check_token] Checking token"
    if [[ -f "$token_file" ]]; then
        # check we are still querying the same server and with the same account
        server_check=$( cat "$server_check_file" )
        user_check=$( cat "$user_check_file" )
        if [[ "$server_check" == "${jss_url}" && "$user_check" == "$jss_api_user" ]]; then
            if plutil -extract token raw "$token_file" >/dev/null; then
                token=$(plutil -extract token raw "$token_file")
            else
                token=""
            fi
            if plutil -extract expires raw "$token_file" >/dev/null; then
                expires=$(plutil -extract expires raw "$token_file" | awk -F . '{print $1}')
                expiration_epoch=$(date -j -f "%Y-%m-%dT%T" "$expires" +"%s")
            else
                expiration_epoch="0"
            fi
            cutoff_epoch=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
            if [[ $expiration_epoch -lt $cutoff_epoch ]]; then
                if [[ $verbose -gt 0 ]]; then
                    echo "   [check_token] token expired or invalid ($expiration_epoch v $cutoff_epoch). Grabbing a new one"
                fi
                sleep 1
                get_new_token 
            else
                echo "   [check_token] Existing token still valid"
            fi
        elif [[ "$server_check" == "${jss_url}" ]]; then
            echo "   [check_token] '$user_check' does not match '$jss_api_user'. Grabbing a new token"
            get_new_token 
        elif [[ "$user_check" == "$jss_api_user" ]]; then
            echo "   [check_token] '$server_check' does not match '${jss_url}'. Grabbing a new token"
            get_new_token 
        else
            echo "   [check_token] Token does not match current URL or user. Grabbing a new one."
            get_new_token 
        fi
    else
        echo "   [check_token] No token found. Grabbing a new one"
        get_new_token
    fi

    token=$(plutil -extract token raw "$token_file")
}

get_computer_id() {
    echo "   [get_computer_id] Getting this computer's ID from Jamf"

    computer_name=$(jamf getComputerName | xmllint --xpath '/computer_name/text()' -)
    echo "   [get_computer_id] Computer Name: $computer_name"

    rm "$tmp_folder/output-computer-id.txt" ||:

    curl_args=(
        --location
        --request GET
        --header "Authorization: Bearer $token"
        --header "Accept: application/xml"
        --output "$tmp_folder/output-computer-id.txt"
        --url "${jss_url}/JSSResource/computers"
    )
    if [[ $verbose -ne 1 ]]; then
        curl_args+=("$curl_verbosity")
    fi

    curl "${curl_args[@]}"
    
    if [[ ! -f "$tmp_folder/output-computer-id.txt" || $(cat "$tmp_folder/output-computer-id.txt") == "" ]]; then
        echo "   [main] ERROR: no output from API"
        exit 1
    fi
    computer_id=$(xmllint --xpath "//computers/computer[name='$computer_name']/id/text()" "$tmp_folder/output-computer-id.txt" 2>/dev/null)
    echo "   [get_computer_id] Computer ID: $computer_id"
    echo
}

get_app_list_from_file() {
    echo "   [get_app_list_from_file] Getting Applications for file ${input_file}"
    while read -r app; do 
        ((app_id++))
        app_name[app_id]=$(echo "$app" | cut -d ";" -f 3)
        app_idfield[app_id]=$(echo "$app" | cut -d ";" -f 1)
        appFullNamefield[app_id]=$(echo "$app" | cut -d ";" -f 2)
        app_tested[app_id]=$(echo "$app" | cut -d ";" -f 4)
        app_comment[app_id]=""
        echo "   [main] Application $app_id: ${app_name[$app_id]}"
        get_current_state "${app_name[$app_id]}"
    done < "${input_file}"
}

write_results_to_file() {
    echo "${app_idfield[app_id]};${appFullNamefield[app_id]};${app_name[app_id]};${app_tested[app_id]};${app_comment[app_id]}" >> "${output_file}"
}

get_current_state() {
    # There are for Content states on a client. A content can be 
    # 1. NOT installed
    # 2. installed in PRD version
    # 3. installed in TST version
    # 4. installed in an OLD version
    # Depending on the state of installation, the scope on policies and smart groups have to match a certain pattern.

    check_token
    echo "   [get_current_state] Checking current group membership of this computer"

    curl_args=(
        --location
        --request GET
        --header "Authorization: Bearer $token"
        --header "Accept: application/xml"
        --output "$tmp_folder/output-computermanagement.txt"
        --url "${jss_url}/JSSResource/computermanagement/id/${computer_id}/subset/smart_groups"
    )
    if [[ $verbose -ne 1 ]]; then
        curl_args+=("$curl_verbosity")
    fi

    curl "${curl_args[@]}"

    xmllint --xpath "//computer_management/smart_groups" "$tmp_folder/output-computermanagement.txt" | 
    xmllint --format - | 
    grep "${app_name[$app_id]}" > "${tmp_folder}/tmp_computer_inventory.xml"

    # Trace the state of scope for app_name to define supposed installation state of the app_name
    current_state="0"
    current=$(grep -Ec "installed|current version installed|test version installed" "${tmp_folder}/tmp_computer_inventory.xml")
    if [[ $current -eq 0 ]]; then
        current_state="not installed"
    else
        current=$(cat ${tmp_folder}/tmp_computer_inventory.xml | grep -c "test version installed" )
        if [[ $current -eq 1 ]]; then
            current_state="TST installed"
        else
            current=$(cat ${tmp_folder}/tmp_computer_inventory.xml | grep -c "current version installed"  )
            if [[ $current -eq 1 ]]; then
                current_state="PRD installed"
            else
                current_state="OLD installed"
            fi
        fi
    fi
    echo "   [get_current_state] Current state: ${app_name[$app_id]} ${current_state}"
}

test_untested_policies() {
    # Testing Procedures
    # test_result[x]="application_name:state_before:action:expected_state_after:policy_return"
    # define processes with supposed test_results to follow to test the application for testing
    test_result[1]="${app_name[$app_id]}:not installed:Uninstall:not installed:FAILED"
    test_result[2]="${app_name[$app_id]}:not installed:Update:not installed:FAILED"
    test_result[3]="${app_name[$app_id]}:not installed:Testing:TST installed:SUCCESS"
    test_result[4]="${app_name[$app_id]}:TST installed:Update:TST installed:FAILED"
    test_result[5]="${app_name[$app_id]}:TST installed:Install:TST installed:FAILED"
    test_result[6]="${app_name[$app_id]}:TST installed:Open_local:TST installed:APP_OPEN"
    test_result[7]="${app_name[$app_id]}:TST installed:Uninstall:not installed:SUCCESS"
    test_result[8]="${app_name[$app_id]}:not installed:Check_local:not installed:APP_CLOSED"
    test_result[9]="${app_name[$app_id]}:not installed:Install:PRD installed:SUCCESS"
    test_result[10]="${app_name[$app_id]}:PRD installed:Update:PRD installed:FAILED"
    test_result[11]="${app_name[$app_id]}:PRD installed:Testing:TST installed:SUCCESS"
    test_result[12]="${app_name[$app_id]}:TST installed:Uninstall:not installed:SUCCESS"
    test_count=12
}

test_production_policies() {
    # define processes to follow to test the application for production
    test_result[1]="${app_name[$app_id]}:OLD installed:Testing:OLD installed:FAILED"
    test_result[2]="${app_name[$app_id]}:OLD installed:Update:PRD installed:SUCCESS"
    test_result[3]="${app_name[$app_id]}:PRD installed:Install:PRD installed:FAILED"
    test_result[4]="${app_name[$app_id]}:PRD installed:Uninstall:not installed:SUCCESS"
    test_count=4
}

set_all_test_results(){
    # define all possible expected test_results with pre-policy execution and post-policy execution 

    # test_result[x]="application_name:state_before:action:expected_state_after:policy_return"
    test_result_all[1]="${app_name[$app_id]}:not installed:Uninstall:not installed:FAILED"
    test_result_all[2]="${app_name[$app_id]}:not installed:Update:not installed:FAILED"
    test_result_all[3]="${app_name[$app_id]}:not installed:Install:PRD installed:SUCCESS"
    test_result_all[4]="${app_name[$app_id]}:not installed:Testing:TST installed:SUCCESS"
    test_result_all[5]="${app_name[$app_id]}:PRD installed:Uninstall:not installed:SUCCESS"
    test_result_all[6]="${app_name[$app_id]}:PRD installed:Update:PRD installed:FAILED"
    test_result_all[7]="${app_name[$app_id]}:PRD installed:Install:PRD installed:FAILED"
    test_result_all[8]="${app_name[$app_id]}:PRD installed:Testing:TST installed:SUCCESS"
    test_result_all[9]="${app_name[$app_id]}:TST installed:Uninstall:not installed:SUCCESS"
    test_result_all[10]="${app_name[$app_id]}:TST installed:Update:TST installed:FAILED"
    test_result_all[11]="${app_name[$app_id]}:TST installed:Install:TST installed:FAILED"
    test_result_all[12]="${app_name[$app_id]}:TST installed:Testing:TST installed:FAILED"
    test_result_all[13]="${app_name[$app_id]}:OLD installed:Uninstall:not installed:SUCCESS"
    test_result_all[14]="${app_name[$app_id]}:OLD installed:Update:PRD installed:SUCCESS"
    test_result_all[15]="${app_name[$app_id]}:OLD installed:Install:OLD installed:FAILED"
    test_result_all[16]="${app_name[$app_id]}:OLD installed:Testing:TST installed:SUCCESS"
    test_result_all[17]="${app_name[$app_id]}:not installed:Open_local:not installed:APP_CLOSED"
    test_result_all[18]="${app_name[$app_id]}:PRD installed:Open_local:PRD installed:APP_OPEN"
    test_result_all[19]="${app_name[$app_id]}:TST installed:Open_local:TST installed:APP_OPEN"
    test_result_all[20]="${app_name[$app_id]}:OLD installed:Open_local:OLD installed:APP_OPEN"
    test_result_all[21]="${app_name[$app_id]}:not installed:Check_local:not installed:APP_CLOSED"
    test_result_all[22]="${app_name[$app_id]}::Check_local::APP_OPEN"
}

test_execute() {
    # execute testprocedure and report results to screen
    for i in $(seq 1 ${test_count}); do
        echo "   [test_execute] Test ${app_name[$app_id]} [${option[${option_id}]}] beginning..." | tee -a "$tmp_log" | tee -a "$end_log"
        action=$(echo "${test_result[${i}]}" | cut -d: -f3)
        execute_content "${app_name[$app_id]}" "${action}"
        if [[ "${full_result}" != "${test_result[${i}]}" ]]; then 
            app_comment[app_id]="${app_comment[app_id]}STEP_${i}   : ${test_result[${i}]}\nFAILED_${i} : ${full_result}"
            echo
            echo "STEP_${i}   : ${test_result[${i}]}" | tee -a "$tmp_log" | tee -a "$end_log"
            echo "FAILED_${i} : ${full_result}" | tee -a "$tmp_log" | tee -a "$end_log"
            echo "********  ${app_name[$app_id]} ${action} FAILED ********" | tee -a "$tmp_log" | tee -a "$end_log"
            echo
            
            success="false"
            break
        else
            echo
            echo "RESULT_${i} : ${full_result}" | tee -a "$tmp_log"
            echo "STEP_${i}   : Check" | tee -a "$tmp_log"
            echo
            success="true"
        fi
    done
    if [[ "${success}" == "true" ]]; then 
        app_tested[app_id]="Successful"
        echo "   [test_execute] Test ${app_name[$app_id]} [${option[${option_id}]}] completed successfully ✅" | tee -a "$tmp_log" | tee -a "$end_log"
    else 
        echo "   [TEST_RESULT] Test ${app_name[$app_id]} [${option[${option_id}]}] failed ❌" | tee -a "$tmp_log" | tee -a "$end_log"
        app_tested[app_id]="Failed"
    fi
    #echo "******* write to file ${app_tested[app_id]}"
    write_results_to_file
}

execute_content() {
    # execute policy depending on action to be tested
    exec_app="$1"
    exec_action="$2"
    
    # setting the resource for the self service policy to be able to retrieve the policy ID via API
    case "$exec_action" in  
        Uninstall) 
            #echo "Policy Uninstall ${app_name[$app_id]}"
            api_url_unencoded="${jss_url}/JSSResource/policies/name/${exec_action} ${exec_app}"
        ;;
        Update)
            #echo "Policy Update ${app_name[$app_id]}"
            api_url_unencoded="${jss_url}/JSSResource/policies/name/${exec_action} ${exec_app}"
        ;;
        Install)
            #echo "Policy ${app_name[$app_id]}"
            api_url_unencoded="${jss_url}/JSSResource/policies/name/${exec_app}"
        ;;
        Testing)
            #echo "Policy Testing ${app_name[$app_id]}"
            api_url_unencoded="${jss_url}/JSSResource/policies/name/${exec_app} (Testing)"
        ;;
        Open_local)
            # echo "Open_local /Applications/${app_name[$app_id]}.app"
            echo "   [execute_content] Current user: $CURRENT_USER"
            if [[ -d "/Applications/${app_name[$app_id]}.app" ]]; then
                if /bin/launchctl asuser "$USER_ID" /usr/bin/sudo -u "$CURRENT_USER" open "/Applications/${app_name[$app_id]}.app"; then
                    echo "   [execute_content] the system will wait for up to 30s to let application start up"
                    t=0
                    while [[ $t -lt 30 ]]; do
                        sleep 1
                        if pgrep -ix "${app_name[$app_id]}" ; then
                            exec_result="APP_OPEN"
                            echo "   [execute_content] /Applications/${app_name[$app_id]}.app is open!"
                            break
                        else
                            exec_result="APP_CLOSED"
                        fi
                        ((t++))
                    done
                else
                    echo "   [execute_content] /Applications/${app_name[$app_id]}.app failed to open!"
                    exec_result="APP_CLOSED"
                fi
            else
                echo "   [execute_content] /Applications/${app_name[$app_id]}.app not found!"
                exec_result="APP_CLOSED"
            fi
            full_result=$(echo "${exec_app}:${current_state}:${exec_action}:${current_state}:${exec_result}" | tee -a "$tmp_log")
            return
        ;;
        Check_local)
            # echo "Check_local /Applications/${app_name[$app_id]}.app"
            if pgrep -ix "${app_name[$app_id]}"; then
                exec_result="APP_OPEN"
            else
                exec_result="APP_CLOSED"
            fi  
            full_result=$(echo "${exec_app}:${current_state}:${exec_action}:${current_state}:${exec_result}" | tee -a "$tmp_log")
            return
        ;;
    esac

    # encode spaces in URL
    api_url="${api_url_unencoded// /%20}"
    
    # get Policy ID
    echo "   [execute_content] Getting Policy ID"
    curl_args=(
        --location
        --request GET
        --header "Authorization: Bearer $token"
        --header "Accept: application/xml"
        --output "$tmp_folder/output-policy-id.txt"
        --url "${api_url}"
    )
    if [[ $verbose -ne 1 ]]; then
        curl_args+=("$curl_verbosity")
    fi

    curl "${curl_args[@]}"
    
    policy_id=$(xmllint --xpath "//general/id/text()" "$tmp_folder/output-policy-id.txt" 2>/dev/null)

    if [[ -n "${policy_id}"  ]]; then
        echo "   [execute_content] Executing Policy ID ${policy_id}:"
        echo "   [execute_content] ${api_url}"
        echo
        full_result=""
        pre_state="${current_state}"
        exec_result=$(${JAMF_CMD} policy -id "${policy_id}" 2>&1 | grep "No policies were found for the ID ")
        echo "$exec_result" | tee -a "$tmp_log"
        if [[ "${exec_result}" ]]; then 
            exec_result="FAILED"
            echo
        else
            exec_result="SUCCESS"
        fi  
        get_current_state "${exec_app}"
        post_state="${current_state}"
        full_result=$(echo "${exec_app}:${pre_state}:${exec_action}:${post_state}:${exec_result}" | tee -a "$tmp_log")
    else
        echo "   [execute_content] ERROR: Policy ID could not be found for ${api_url}" | tee -a "$tmp_log"
        app_comment[app_id]="$exec_action Policy missing\n"
    fi
}


### MAIN ###

# create temp dir
/bin/mkdir -p "$tmp_folder"

# get user
CURRENT_USER=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
USER_ID=$(/usr/bin/id -u "$CURRENT_USER")

# set verbosity
verbose=0

# get local JSS as this has to run on the same instance
jss_url=$(defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)
jss_url="${jss_url%/}"
echo "   [main] Jamf Pro URL: $jss_url"
echo "${jss_url}" > "$server_check_file"

app_id=0
app_name[1]="empty"
option_id=0
option[1]="none"
repetition="none"
input_file=""

# read arguments
if [[ -z "$1" ]]; then 
    # no app title provided
    usage

else
    while [[ "$#" -gt 0 ]]; do
        key="$1"
        case $key in
            -a=*)
                ((app_id++))
                app_name[app_id]="${key#*=}"
                echo "   [main] Application $app_id: ${app_name[$app_id]}"
            ;;
            -a|--app)
                shift
                ((app_id++))
                app_name[app_id]="${1}"
                echo "   [main] Application $app_id: ${app_name[$app_id]}"
            ;;
            -o=*)
                ((option_id++))
                option[option_id]="${key#*=}"
                echo "   [main] Option ${option_id}: ${option[${option_id}]}"
                repetition[option_id]="once"
            ;;
            -o|--option)
                shift
                ((option_id++))
                option[option_id]="${1}"
                echo "   [main] Option ${option_id}: ${option[${option_id}]}"
                repetition[option_id]="once"
            ;;
            -i|--input)
                echo "      [main] Option File input!"
                shift
                input_file="${1}"
                if [[ -f "${input_file}" ]]; then 
                    echo "   [main] File ${input_file}"
                    get_app_list_from_file "${input_file}"
                    output_file="${input_file}_result"
                else
                    echo "   [main] File ${1} does not exist!"
                fi
            ;;
            -v)
                verbose=1
            ;;
            -vv)
                verbose=2
            ;;
            *)
                ((app_id++))
                app_name[app_id]="$1"
            ;;
        esac
        shift
    done
fi

# curl verbosity
echo "   [main] verbose level: $verbose"
if [[ $verbose -eq 0 ]]; then
    curl_verbosity="--silent"
elif  [[ $verbose -ge 2 ]]; then
    curl_verbosity="-v"
fi

# initialize
get_credentials
check_token

# get the computer's ID
get_computer_id

get_current_state "${app_name[$app_id]}"

max_app_id=${app_id}
max_option_id=${option_id}

for app_id in $(seq 1 ${max_app_id}); do  
    echo "   [main] Starting Testing Process for Application $app_id ${app_name[$app_id]} of $max_app_id"
    
    for option_id in $(seq 1 ${max_option_id}); do  
        set_all_test_results
        get_current_state "${app_name[$app_id]}"
        save_repetition="${repetition[$option_id]}"
        
        while  [[ "${repetition[$option_id]}" != "done" ]];  do

            #predefine possible procedures depending on current state of app_name installation
            IFS=$'\n' 
            exp_result_1=$(echo "${test_result_all[*]}" | grep "${app_name[$app_id]}:${current_state}:Testing" | cut -d: -f5)
            exp_result_2=$(echo "${test_result_all[*]}" | grep "${app_name[$app_id]}:${current_state}:Update" | cut -d: -f5)
            exp_result_3=$(echo "${test_result_all[*]}" | grep "${app_name[$app_id]}:${current_state}:Install" | cut -d: -f5)
            exp_result_4=$(echo "${test_result_all[*]}" | grep "${app_name[$app_id]}:${current_state}:Uninstall" | cut -d: -f5)

            test_count=1
            case "${option[${option_id}]}" in        
                testing)
                    # precondition to start procedure 'testing' for app_name is installation state 'not installed'
                    if [[ "${current_state}" == "not installed" ]]; then  
                        test_untested_policies
                        test_execute
                    else
                        echo "   [main] preconditions do not match: ${app_name[$app_id]} installed, needs to be uninstalled first"| tee -a "$end_log"
                
                    fi
                    break
                ;;            
                productive)
                    # precondition to start procedure 'productive' for app_name is installation state 'OLD installed'

                    if  [[ "${current_state}" == "OLD installed" ]]; then 
                        test_production
                        test_execute
                    else
                        echo "   [main] Preconditions do not match: OLD version of ${app_name[$app_id]} not installed"
                        echo "   [main] Please manually install an OLD version first"
                    fi
                ;;  
                t)
                    echo "   [main] Try installing TST version of ${app_name[$app_id]} -> should result in [${exp_result_1}]"
                    test_result[1]=$(echo "${test_result_all[*]}" | grep "${app_name[$app_id]}:${current_state}:Testing")
                    test_execute
                    # execute_content "${app_name[$app_id]}:" "Testing"
                ;;
                up)
                    echo "   [main] Try updating to PRD Version of ${app_name[$app_id]} -> should result in [${exp_result_2}]"
                    test_result[1]=$(echo "${test_result_all[*]}" | grep "${app_name[$app_id]}:${current_state}:Update")
                    test_execute
                    # execute_content "${app_name[$app_id]}:" "Update"
                ;;
                i)
                    echo "   [main] Try installing PRD Version of ${app_name[$app_id]} -> should result in [${exp_result_3}]"
                    test_result[1]=$(echo "${test_result_all[*]}" | grep "${app_name[$app_id]}:${current_state}:Install")
                    test_execute
                    # execute_content "${app_name[$app_id]}:" "Install"
                ;;
                o)
                    echo "   [main] Try to open ${current_state} of ${app_name[$app_id]} "
                    test_result[1]=$(echo "${test_result_all[*]}" | grep "${app_name[$app_id]}:${current_state}:Open_local")
                    test_execute
                    # execute_content "${app_name[$app_id]}:" "Install"
                ;;
                c)
                    echo "   [main] Check if Application is open ${current_state} of ${app_name[$app_id]} "
                    if [[ ${current_state} == "not installed" ]]; then
                        test_result[1]=$(echo "${test_result_all[*]}" | grep "${app_name[$app_id]}:not installed:Check_local")
                    else
                        test_result[1]=$(echo "${test_result_all[*]}" | grep "${app_name[$app_id]}::Check_local")
                    fi
                    test_execute
                    # execute_content "${app_name[$app_id]}:" "Install"
                ;;
                s)
                    get_current_state "${app_name[$app_id]}"
                ;;
                u)
                    echo "   [main] Try uninstalling ${app_name[$app_id]} -> should result in [${exp_result_4}]"
                    test_result[1]=$(echo "${test_result_all[*]}" | grep "${app_name[$app_id]}:${current_state}:Uninstall")
                    test_execute
                    # execute_content "${app_name[$app_id]}:" "Uninstall"
                ;;
                q)
                    repetition[option_id]="done"
                    exit
                ;;
                *)
                    repetition[option_id]="none"
                ;;
            esac

            if [[ "${repetition[$option_id]}" == "once" ]]; then
                repetition[option_id]="done"
            fi
            echo "   [main] Repetition = ${repetition[${option_id}]}"
            if [[ "${repetition[${option_id}]}" != "done" || ${option[1]} == "none" ]]; then
                echo
                echo "Possible Script Types:"
                echo "   [t]   [Testing*]     Self Service item ${app_name[$app_id]} - should result in [${exp_result_1}] *"
                echo "                        * Testing might not exist if already staged to production"
                echo "   [up]  [Update]       Self Service item ${app_name[$app_id]} - should result in [${exp_result_2}]"
                echo "   [i]   [Install PRD]  Self Service item ${app_name[$app_id]} - should result in [${exp_result_3}]"
                echo "   [u]   [Uninstall]    Self Service item ${app_name[$app_id]} - should result in [${exp_result_4}]"
                echo 
                echo "   [o]   [Open]         Application ${app_name[$app_id]} - should open if it is installed"
                echo "   [c]   [Check]        Check if Application ${app_name[$app_id]} is open - should be closed"
                echo 
                echo "   [s]   [State]        Current state of Self Service item ${app_name[$app_id]}"
                echo 
                echo "   [q]   [Quit]"
                echo
                read -r -p "Enter choice : " option["${option_id}"]
                echo
            fi
        done

        repetition[option_id]="${save_repetition}"
        # repetition[${option_id}]="none"
        # echo "Current state: ${app_name[$app_id]} ${current_state}"
    done
done
echo
