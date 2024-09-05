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
tmpfolder="/tmp/jamf-auto-tester"
tmplog="$tmpfolder/tmp.log"
tmplogfinal="/tmp/jamf-auto-tester_final.log"
token_file="/tmp/jamf-auto-tester_token.txt"
server_check_file="/tmp/jamf_auto_server_check.txt"
user_check_file="/tmp/jamf_auto_user_check.txt"
outputfile="/tmp/singletest_result.log"
verbose=1

### FUNCTIONS ###

usage() {
    echo
    echo "Usage:"
    echo "./app-installation-tester.sh <options> "
    echo "		APPNAME            - Testing installation of Self Service item APPNAME"
    echo "		-a=APPNAME or -a|--app APPNAME            - Testing installation of Self Service item APPNAME"
    echo "	"
    echo "		-i|--input INPUTFILE            - Specify a file that contains all the applications to be tested "
    echo "					(as replacement or addition to -a) "
    echo "	"
    echo "		-o=OPTION or -o|--option OPTION     "
    echo "	"
    echo "			OPTION s            - Current state of Self Service item APPNAMEs"
    echo "			OPTION t            - Testing installation of Self Service testing item APPNAMEs"
    echo "			OPTION p            - Testing installation of Self Service productive item APPNAMEs"
    echo "			OPTION u            - Testing uninstaller of Self Service item APPNAMEs"
    echo "			OPTION up           - Testing update of Self Service item APPNAMEs"
    echo "			OPTION testing      - Testing Self Service item APPNAMEs in Testing procedure"
    echo "			OPTION productive   - Testing Self Service item APPNAMEs in Production procedure"
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
    if curl --location --silent \
        --request POST \
        --user "${jss_api_user}:${jss_api_password}" \
        --url "${jss_url}/api/v1/auth/token" \
        --header 'Accept: application/json' \
        --output "$token_file"
    then
        echo "   [get_new_token] Token for $jss_api_user on ${jss_url} written to $token_file"
    else
        echo "   [get_new_token] Token for $jss_api_user on ${jss_url} not written"
    fi
}

check_token() {
    # is there a token file
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
    export token
}

get_computer_id() {
    echo "   [get_computer_id] Getting this computer's ID from Jamf"

    computer_name=$(jamf getComputerName | xmllint --xpath '/computer_name/text()' -)
    echo "   [get_computer_id] Computer Name: $computer_name"

    curl --location --silent \
        --request GET \
        --header "Authorization: Bearer $token" \
        --header "Accept: application/xml" \
        --output "$tmpfolder/output.txt" \
        --url "${jss_url}/JSSResource/computers" 
    computer_id=$(xmllint --xpath "//computers/computer[name='$computer_name']/id/text()" "$tmpfolder/output.txt")
    echo "   [get_computer_id] Computer ID: $computer_id"
    echo
}

get_app_list_from_file() {
    echo "   [get_app_list_from_file] Getting Applications for file ${inputfile}"
    while read -r app; do 
        ((appID++))
        appName[appID]=$(echo "$app" | cut -d ";" -f 3)
        appIDfield[appID]=$(echo "$app" | cut -d ";" -f 1)
        appFullNamefield[appID]=$(echo "$app" | cut -d ";" -f 2)
        appTested[appID]=$(echo "$app" | cut -d ";" -f 4)
        appComment[appID]=""
            echo "   [main] Application $appID: ${appName[$appID]}"
        get_current_state "${appName[$appID]}"
    done < "${inputfile}"
}

write_results_to_file() {
    echo "${appIDfield[appID]};${appFullNamefield[appID]};${appName[appID]};${appTested[appID]};${appComment[appID]}" >> "${outputfile}"
}

get_current_state() {
    # There are for Content states on a client. A content can be 
    # 1. NOT installed
    # 2. installed in PRD version
    # 3. installed in TST version
    # 4. installed in an OLD version
    # Depending on the state of installation, the scope on policies and smart groups have to match a certain pattern.

    check_token

    curl --location --silent \
        --request GET \
        --header "Authorization: Bearer $token" \
        --header "Accept: application/xml" \
        --output "$tmpfolder/output-computermanagement.txt" \
        --url "${jss_url}/JSSResource/computermanagement/id/${computer_id}/subset/smart_groups"

    xmllint --xpath "//computer_management/smart_groups" "$tmpfolder/output-computermanagement.txt" | 
    xmllint --format - | 
    grep "${appName[$appID]}" > "${tmpfolder}/tmp_computer_inventory.xml"

    # Trace the state of scope for appName to define supposed installation state of the appName
    current_state="0"
    current=$(grep -Ec "installed|current version installed|test version installed" "${tmpfolder}/tmp_computer_inventory.xml")
    if [[ $current -eq 0 ]]; then
        current_state="not installed"
    else
        current=$(cat ${tmpfolder}/tmp_computer_inventory.xml | grep -c "test version installed" )
        if [[ $current -eq 1 ]]; then
            current_state="TST installed"
        else
            current=$(cat ${tmpfolder}/tmp_computer_inventory.xml | grep -c "current version installed"  )
            if [[ $current -eq 1 ]]; then
                current_state="PRD installed"
            else
                current_state="OLD installed"
            fi
        fi
    fi
    echo "   [get_current_state] Current state: ${appName[$appID]} ${current_state}"
}

test_untested_policies() {
    # Testing Procedures
    # testresult[x]="application_name:state_before:action:expected_state_after:policy_return"
    # define processes with supposed testresults to follow to test the application for testing
    testresult[1]="${appName[$appID]}:not installed:Uninstall:not installed:FAILED"
    testresult[2]="${appName[$appID]}:not installed:Update:not installed:FAILED"
    testresult[3]="${appName[$appID]}:not installed:Testing:TST installed:SUCCESS"
    testresult[4]="${appName[$appID]}:TST installed:Update:TST installed:FAILED"
    testresult[5]="${appName[$appID]}:TST installed:Install:TST installed:FAILED"
    testresult[6]="${appName[$appID]}:TST installed:Open_local:TST installed:APP_OPEN"
    testresult[7]="${appName[$appID]}:TST installed:Uninstall:not installed:SUCCESS"
    testresult[8]="${appName[$appID]}:not installed:Check_local:not installed:APP_CLOSED"
    testresult[9]="${appName[$appID]}:not installed:Install:PRD installed:SUCCESS"
    testresult[10]="${appName[$appID]}:PRD installed:Update:PRD installed:FAILED"
    testresult[11]="${appName[$appID]}:PRD installed:Testing:TST installed:SUCCESS"
    testresult[12]="${appName[$appID]}:TST installed:Uninstall:not installed:SUCCESS"
    test_count=12
}

test_production_policies() {
    # define processes to follow to test the application for production
    testresult[1]="${appName[$appID]}:OLD installed:Testing:OLD installed:FAILED"
    testresult[2]="${appName[$appID]}:OLD installed:Update:PRD installed:SUCCESS"
    testresult[3]="${appName[$appID]}:PRD installed:Install:PRD installed:FAILED"
    testresult[4]="${appName[$appID]}:PRD installed:Uninstall:not installed:SUCCESS"
    test_count=4
}

set_all_testresults(){
    # define all possible expected testresults with pre-policy execution and post-policy execution 

    # testresult[x]="application_name:state_before:action:expected_state_after:policy_return"
    testresult_all[1]="${appName[$appID]}:not installed:Uninstall:not installed:FAILED"
    testresult_all[2]="${appName[$appID]}:not installed:Update:not installed:FAILED"
    testresult_all[3]="${appName[$appID]}:not installed:Install:PRD installed:SUCCESS"
    testresult_all[4]="${appName[$appID]}:not installed:Testing:TST installed:SUCCESS"
    testresult_all[5]="${appName[$appID]}:PRD installed:Uninstall:not installed:SUCCESS"
    testresult_all[6]="${appName[$appID]}:PRD installed:Update:PRD installed:FAILED"
    testresult_all[7]="${appName[$appID]}:PRD installed:Install:PRD installed:FAILED"
    testresult_all[8]="${appName[$appID]}:PRD installed:Testing:TST installed:SUCCESS"
    testresult_all[9]="${appName[$appID]}:TST installed:Uninstall:not installed:SUCCESS"
    testresult_all[10]="${appName[$appID]}:TST installed:Update:TST installed:FAILED"
    testresult_all[11]="${appName[$appID]}:TST installed:Install:TST installed:FAILED"
    testresult_all[12]="${appName[$appID]}:TST installed:Testing:TST installed:FAILED"
    testresult_all[13]="${appName[$appID]}:OLD installed:Uninstall:not installed:SUCCESS"
    testresult_all[14]="${appName[$appID]}:OLD installed:Update:PRD installed:SUCCESS"
    testresult_all[15]="${appName[$appID]}:OLD installed:Install:OLD installed:FAILED"
    testresult_all[16]="${appName[$appID]}:OLD installed:Testing:TST installed:SUCCESS"
    testresult_all[17]="${appName[$appID]}:not installed:Open_local:not installed:APP_CLOSED"
    testresult_all[18]="${appName[$appID]}:PRD installed:Open_local:PRD installed:APP_OPEN"
    testresult_all[19]="${appName[$appID]}:TST installed:Open_local:TST installed:APP_OPEN"
    testresult_all[20]="${appName[$appID]}:OLD installed:Open_local:OLD installed:APP_OPEN"
    testresult_all[21]="${appName[$appID]}:not installed:Check_local:not installed:APP_CLOSED"
    testresult_all[22]="${appName[$appID]}::Check_local::APP_OPEN"
}

test_execute() {
    # execute testprocedure and report results to screen
    for i in $(seq 1 ${test_count}); do
        echo "   [test_execute] Test ${appName[$appID]} [${option[${optionID}]}] beginning..." | tee -a "$tmplog" | tee -a "$tmplogfinal"
        action=$(echo "${testresult[${i}]}" | cut -d: -f3)
        execute_content "${appName[$appID]}" "${action}"
        if [[ "${full_result}" != "${testresult[${i}]}" ]]; then 
            appComment[appID]="${appComment[appID]}STEP_${i}   : ${testresult[${i}]}\nFAILED_${i} : ${full_result}"
            echo
            echo "STEP_${i}   : ${testresult[${i}]}" | tee -a "$tmplog" | tee -a "$tmplogfinal"
            echo "FAILED_${i} : ${full_result}" | tee -a "$tmplog" | tee -a "$tmplogfinal"
            echo "********  ${appName[$appID]} ${action} FAILED ********" | tee -a "$tmplog" | tee -a "$tmplogfinal"
            echo
            
            success="false"
            break
        else
            echo
            echo "RESULT_${i} : ${full_result}" | tee -a "$tmplog"
            echo "STEP_${i}   : Check" | tee -a "$tmplog"
            echo
            success="true"
        fi
    done
    if [[ "${success}" == "true" ]]; then 
        appTested[appID]="Successful"
        echo "   [test_execute] Test ${appName[$appID]} [${option[${optionID}]}] completed successfully ✅" | tee -a "$tmplog" | tee -a "$tmplogfinal"
    else 
        echo "   [test_execute] Test ${appName[$appID]} [${option[${optionID}]}] failed ❌" | tee -a "$tmplog" | tee -a "$tmplogfinal"
        appTested[appID]="Failed"
    fi
    #echo "******* write to file ${appTested[appID]}"
    write_results_to_file
}

execute_content() {
    # execute policy depending on action to be tested
    exec_app="$1"
    exec_action="$2"
    
    # setting the resource for the self service policy to be able to retrieve the policy ID via API
    case "$exec_action" in  
        Uninstall) 
            #echo "Policy Uninstall ${appName[$appID]}"
            JSSResourceComputers=$(echo "${jss_url}/JSSResource/policies/name/${exec_action}%20${exec_app}"| sed 's| |%20|g')
        ;;
        Update)
            #echo "Policy Update ${appName[$appID]}"
            JSSResourceComputers=$(echo "${jss_url}/JSSResource/policies/name/${exec_action}%20${exec_app}"| sed 's| |%20|g')
        ;;
        Install)
            #echo "Policy ${appName[$appID]}"
            JSSResourceComputers=$(echo "${jss_url}/JSSResource/policies/name/${exec_app}"| sed 's| |%20|g')
        ;;
        Testing)
            #echo "Policy Testing ${appName[$appID]}"
            JSSResourceComputers=$(echo "${jss_url}/JSSResource/policies/name/${exec_app} (Testing)"| sed 's| |%20|g')
        ;;
        Open_local)
            # echo "Open_local /Applications/${appName[$appID]}.app"
            echo "   [execute_content] Current user: $CURRENT_USER"
            if [[ -d "/Applications/${appName[$appID]}.app" ]]; then
                if /bin/launchctl asuser "$USER_ID" /usr/bin/sudo -u "$CURRENT_USER" open "/Applications/${appName[$appID]}.app"; then
                    echo "   [execute_content] the system will wait for up to 30s to let application start up"
                    t=0
                    while [[ $t -lt 30 ]]; do
                        sleep 1
                        if pgrep -ix "${appName[$appID]}" ; then
                            exec_result="APP_OPEN"
                            echo "   [execute_content] /Applications/${appName[$appID]}.app is open!"
                            break
                        else
                            exec_result="APP_CLOSED"
                        fi
                        ((t++))
                    done
                else
                    echo "   [execute_content] /Applications/${appName[$appID]}.app failed to open!"
                    exec_result="APP_CLOSED"
                fi
            else
                echo "   [execute_content] /Applications/${appName[$appID]}.app not found!"
                exec_result="APP_CLOSED"
            fi
            full_result=$(echo "${exec_app}:${current_state}:${exec_action}:${current_state}:${exec_result}" | tee -a "$tmplog")
            return
        ;;
        Check_local)
            # echo "Check_local /Applications/${appName[$appID]}.app"
            if pgrep -ix "${appName[$appID]}"; then
                exec_result="APP_OPEN"
            else
                exec_result="APP_CLOSED"
            fi	
            full_result=$(echo "${exec_app}:${current_state}:${exec_action}:${current_state}:${exec_result}" | tee -a "$tmplog")
            return
        ;;
    esac
    
    # get Policy ID
    policy_id=$(/usr/bin/curl -s -f -k -H "Accept: application/xml" -H "Authorization: Bearer $token" "${JSSResourceComputers}" | /usr/bin/xmllint --xpath "//general/id/text()" - )
    if [[ -n "${policy_id}"  ]]; then
        echo "   [execute_content] Executing Policy ID ${policy_id}:"
        echo "   [execute_content] ${JSSResourceComputers}"
        echo
        full_result=""
        pre_state="${current_state}"
        exec_result=$(${JAMF_CMD} policy -id "${policy_id}" 2>&1 | grep "No policies were found for the ID ")
        echo "$exec_result" | tee -a "$tmplog"
        if [[ -n ${exec_result} ]]; then 
            exec_result="FAILED"
            echo
        else
            exec_result="SUCCESS"
        fi	
        get_current_state "${exec_app}"
        post_state="${current_state}"
        full_result=$(echo "${exec_app}:${pre_state}:${exec_action}:${post_state}:${exec_result}" | tee -a "$tmplog")
    else
        echo "   [execute_content] ERROR: Policy ID could not be found for ${JSSResourceComputers}" | tee -a "$tmplog"
        appComment[appID]="$exec_action Policy missing\n"
    fi
}


### MAIN ###

# create temp dir
/bin/mkdir -p "$tmpfolder"

# get user
CURRENT_USER=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
USER_ID=$(/usr/bin/id -u "$CURRENT_USER")

# get local JSS as this has to run on the same instance
jss_url=$(defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)
jss_url="${jss_url%/}"
echo "JSS URL: $jss_url"
echo "${jss_url}" > "$server_check_file"

# initialize
get_credentials
check_token

# get the computer's ID
get_computer_id

appID=0
appName[1]="empty"
optionID=0
option[1]="none"
repetition="none"
inputfile=""

# read arguments
if [[ -z "$1" ]]; then 
    # no app title provided
    usage

elif [[ "$1" =~ ^!- ]]; then
    ((appID++))
    appName[appID]="$1"
    echo "   [main] $appID ${appName[$appID]}"
    get_current_state "${appName[$appID]}"

else
    while [[ "$#" -gt 0 ]]; do
        key="$1"
        case $key in
        -a=*)
            ((appID++))
            appName[appID]="${key#*=}"
            echo "   [main] Application $appID: ${appName[$appID]}"
            get_current_state "${appName[$appID]}"
        ;;
       -a|--app)
            shift
            ((appID++))
            appName[appID]="${1}"
            echo "   [main] Application $appID: ${appName[$appID]}"
            get_current_state "${appName[$appID]}"
        ;;
       -o=*)
            ((optionID++))
            option[optionID]="${key#*=}"
            echo "   [main] Option ${optionID}: ${option[${optionID}]}"
            repetition[optionID]="once"
        ;;
       -o|--option)
            shift
            ((optionID++))
            option[optionID]="${1}"
            echo "   [main] Option ${optionID}: ${option[${optionID}]}"
            repetition[optionID]="once"
        ;;
        -i|--input)
            echo "   Option File input!"
            shift
            inputfile="${1}"
            if [[ -e "${inputfile}" ]]; then 
                echo "[main] File ${inputfile}"
                get_app_list_from_file "${inputfile}"
                outputfile="${inputfile}_result"
            else
                echo "   [main] File ${1} does not exist!"
            fi
       ;;
           esac
        shift
    done
fi

maxappID=${appID}
maxoptionID=${optionID}

for appID in $(seq 1 ${maxappID}); do  
    echo "   [main] Starting Testing Process for Application $appID ${appName[$appID]} of $maxappID"
    
    for optionID in $(seq 1 ${maxoptionID}); do  
        set_all_testresults
        get_current_state "${appName[$appID]}"
        save_repetition="${repetition[$optionID]}"
        
        while  [[ "${repetition[$optionID]}" != "done" ]];  do

            #predefine possible procedures depending on current state of appName installation
            IFS=$'\n' 
            exp_restult1=$(echo "${testresult_all[*]}" | grep "${appName[$appID]}:${current_state}:Testing" | cut -d: -f5)
            exp_restult2=$(echo "${testresult_all[*]}" | grep "${appName[$appID]}:${current_state}:Update" | cut -d: -f5)
            exp_restult3=$(echo "${testresult_all[*]}" | grep "${appName[$appID]}:${current_state}:Install" | cut -d: -f5)
            exp_restult4=$(echo "${testresult_all[*]}" | grep "${appName[$appID]}:${current_state}:Uninstall" | cut -d: -f5)

            test_count=1
            case "${option[${optionID}]}" in        
                testing)
                    # precondition to start procedure 'testing' for appName is installation state 'not installed'
                    if [[ "${current_state}" == "not installed" ]]; then  
                        test_untested_policies
                        test_execute
                    else
                        echo "   [main] preconditions do not match: ${appName[$appID]} installed, needs to be uninstalled first"| tee -a "$tmplogfinal"
                
                    fi
                    break
                ;;            
                productive)
                    # precondition to start procedure 'productive' for appName is installation state 'OLD installed'

                    if  [[ "${current_state}" == "OLD installed" ]]; then 
                        test_production
                        test_execute
                    else
                        echo "   [main] preconditions do not match: OLD version of ${appName[$appID]} not installed"
                        echo "   [main] please manually install an OLD version first"
                    fi
                ;;  
                t)
                    echo "   [main] Try Installing TST Version of ${appName[$appID]} -> should result in [${exp_restult1}]"
                    testresult[1]=$(echo "${testresult_all[*]}" | grep "${appName[$appID]}:${current_state}:Testing")
                    test_execute
                    # execute_content "${appName[$appID]}:" "Testing"
                ;;
                up)
                    echo "   [main] Try updating to PRD Version of ${appName[$appID]} -> should result in [${exp_restult2}]"
                    testresult[1]=$(echo "${testresult_all[*]}" | grep "${appName[$appID]}:${current_state}:Update")
                    test_execute
                    # execute_content "${appName[$appID]}:" "Update"
                ;;
                i)
                    echo "   [main] Try installing PRD Version of ${appName[$appID]} -> should result in [${exp_restult3}]"
                    testresult[1]=$(echo "${testresult_all[*]}" | grep "${appName[$appID]}:${current_state}:Install")
                    test_execute
                    # execute_content "${aappIDppName[$]}:" "Install"
                ;;
                o)
                    echo "   [main] Try to Open ${current_state} of ${appName[$appID]} "
                    testresult[1]=$(echo "${testresult_all[*]}" | grep "${appName[$appID]}:${current_state}:Open_local")
                    test_execute
                    # execute_content "${aappIDppName[$]}:" "Install"
                ;;
                c)
                    echo "   [main] Check if Application is open ${current_state} of ${appName[$appID]} "
                    if [[ ${current_state} == "not installed" ]]; then
                        testresult[1]=$(echo "${testresult_all[*]}" | grep "${appName[$appID]}:not installed:Check_local")
                    else
                        testresult[1]=$(echo "${testresult_all[*]}" | grep "${appName[$appID]}::Check_local")
                    fi
                    test_execute
                    # execute_content "${aappIDppName[$]}:" "Install"
                ;;
                s)
                    get_current_state "${appName[$appID]}"
                ;;
                u)
                    echo "   [main] Try uninstalling ${appName[$appID]} -> should result in [${exp_restult4}]"
                    testresult[1]=$(echo "${testresult_all[*]}" | grep "${appName[$appID]}:${current_state}:Uninstall")
                    test_execute
                    # execute_content "${appName[$appID]}:" "Uninstall"
                ;;
                q)
                    repetition[optionID]="done"
                    exit
                ;;
                *)
                    repetition[optionID]="none"
                ;;
            esac

            if [[ "${repetition[$optionID]}" == "once" ]]; then
                repetition[optionID]="done"
            fi
            echo "   [main] Repetition = ${repetition[${optionID}]}"
            if [[ "${repetition[${optionID}]}" != "done" || ${option[1]} == "none" ]]; then
                echo
                echo "Possible Script Types:"
                echo "   [t]   [Testing*]     Self Service item ${appName[$appID]} - should result in [${exp_restult1}] *"
                echo "                        * Testing might not exist if already staged to production"
                echo "   [up]  [Update]       Self Service item ${appName[$appID]} - should result in [${exp_restult2}]"
                echo "   [i]   [Install PRD]  Self Service item ${appName[$appID]} - should result in [${exp_restult3}]"
                echo "   [u]   [Uninstall]    Self Service item ${appName[$appID]} - should result in [${exp_restult4}]"
                echo 
                echo "   [o]   [Open]         Application ${appName[$appID]} - should open if it is installed"
                echo "   [c]   [Check]        Check if Application ${appName[$appID]} is open - should be closed"
                echo 
                echo "   [s]   Current state of Self Service item ${appName[$appID]}"
                echo 
                echo "   [q]   Quit"
                echo
                read -r -p "Enter choice : " option["${optionID}"]
                echo
            fi
        done

        repetition[optionID]="${save_repetition}"
        # repetition[${optionID}]="none"
        # echo "Current state: ${appName[$appID]} ${current_state}"
    done
done
echo
