#!/bin/zsh

# This script will pop up a mini dialog with progress of a jamf pro policy

# source https://github.com/bartreardon/swiftDialog-scripts/blob/main/JamfSelfService/jss-progress.sh

jamf_pid=""
jamf_log="/var/log/jamf.log"
dialog_log=$(mktemp /var/tmp/dialog.XXX)
chmod 644 ${dialog_log}
script_log="/var/tmp/jamfprogress.log"
lock_file="/var/tmp/lock.txt"
count=0

# icon to show on dialogs
icon="${1}"
if [[ -z $icon ]]; then
    icon="/Library/Application Support/JAMF/bin/Management Action.app/Contents/MacOS/Management Action"
fi

# Location of this script
progress_script_location="${2}"
if [[ -z "$progress_script_location" ]]; then
    progress_script_location="/Library/Management/swiftDialog"
fi

function update_log() {
    /bin/echo "$(date) ${1}" >> "$script_log"
}

function dialog_cmd() {
    /bin/echo "${1}" >> "${dialog_log}"
    sleep 0.1
}

function launch_dialog() {
	update_log "launching main dialog with log ${dialog_log}"
    /usr/local/bin/dialog --moveable --position bottomright --mini --title "${policy_name}" --icon "${icon}" --message "Please wait while we perform a management task on your computer" --progress 8 --commandfile "${dialog_log}" &
    PID=$!
    update_log "main dialog running in the background with PID $PID"
    sleep 0.1
}

function dialog_error() {
	update_log "launching error dialog"
    errormsg="### Error\n\nSomething went wrong. Please contact IT support and report the following error message:\n\n${1}"
    /usr/local/bin/dialog --ontop --title "Jamf Policy Error" --icon "${icon}" --overlayicon caution --message "${errormsg}"
    PID=$!
    update_log "error dialog running in the background with PID $PID"
    sleep 0.1
}

function quit_script() {
	update_log "sending quit command"
    [[ -f "/usr/local/bin/dialog" ]] && dialog_cmd "quit: "
    sleep 0.1
    # brutal hack - need to find a better way
    pgrep tail && pkill tail
    if [[ -f "${dialog_log}" ]]; then
        update_log "removing ${dialog_log}"
		rm "${dialog_log}"
    fi
    update_log "removing $lock_file"
    rm -f "$lock_file" ||:
    update_log "***** End *****"
    exit 0
}

function read_jamf_log() {
    update_log "starting jamf log read"    
    launchd_count=1
    if [[ "${jamf_pid}" ]]; then
        update_log "processing jamf pro log for PID ${jamf_pid}"
        while read -r line; do    
            status_line=$(echo "${line}")
            case "${status_line}" in
                *Success*)
                    if [[ "${status_line}" == *"$jamf_pid"* ]]; then
                        update_log "Success"
                        dialog_cmd "progresstext: Complete"
                        dialog_cmd "progress: complete"
                        sleep 2
                        update_log "Success Break"
                        quit_script
                    fi
                ;;
                *failed*)
                    if [[ "${status_line}" == *"$jamf_pid"* ]]; then
                        update_log "Failed"
                        dialog_cmd "progresstext: Policy Failed"
                        dialog_cmd "progress: complete"
                        sleep 2
                        dialog_cmd "quit: "
                        dialog_error "${status_line}"
                        update_log "Error Break"
                        quit_script
                    fi
                ;;
                *"Removing existing launchd task"*)
                    $(( launchd_removal_count-- ))
                    if [[ ${launchd_removal_count} -le 0 ]]; then
                        update_log "Launchd task removed"
                        dialog_cmd "progresstext: Completed"
                        dialog_cmd "progress: complete"
                        sleep 2
                        update_log "Launchd Break"
                        quit_script
                    else
                        progresstext=$(echo "${status_line}" | awk -F "]: " '{print $NF}')
                        update_log "Reading policy entry : ${progresstext}"
                        dialog_cmd "progresstext: ${progresstext}"
                        dialog_cmd "progress: increment"
                    fi
                ;;
                *"Executing Policy"*)
                    # running a trigger so we need to switch to the new PID and add another launchd
                    $(( launchd_count++ ))
                    jamf_pid=$( awk -F"[][]" '{print $2}' <<< "$status_line" )
                    update_log "processing jamf pro log for PID ${jamf_pid}"
                    progresstext=$(echo "${status_line}" | awk -F "]: " '{print $NF}')
                    update_log "Reading policy entry : ${progresstext}"
                    dialog_cmd "progresstext: ${progresstext}"
                    dialog_cmd "progress: increment"
                ;;
                *)
                    progresstext=$(echo "${status_line}" | awk -F "]: " '{print $NF}')
                    update_log "Reading policy entry : ${progresstext}"
                    dialog_cmd "progresstext: ${progresstext}"
                    dialog_cmd "progress: increment"
                ;;
            esac
            ((count++))
            if [[ ${count} -gt 10 ]]; then
                update_log "hit maxcount"
                dialog_cmd "progress: complete"
                sleep 0.5
                #break
                quit_script
            fi
        done < <(tail -f -n1 $jamf_log) 
    fi
    update_log "end while loop"
}

function main() {
    update_log "***** Start *****"
    if [[ ! -e "/usr/local/bin/dialog" ]]; then
        update_log "dialog not installed!"
        quit_script
    fi
    last_log_entry=$( tail -n 1 "$jamf_log" )
    update_log "$last_log_entry"
    if [[ -f "$lock_file" ]]; then
        # script is already running or crashed
        update_log "$lock_file present so script is already running"
        exit
    fi

    # write lockfile to prevent this script doing anything twice
    update_log "creating $lock_file"
    touch "$lock_file"
    if [[ "$last_log_entry" == *"Checking for policy ID"* ]]; then
        update_log "getting PID"
        jamf_pid=$( awk -F"[][]" '{print $2}' <<< "$last_log_entry" )
        if [[ $jamf_pid ]]; then
            update_log "PID is ${jamf_pid}"
        else
            update_log "couldn't get a PID"
        fi
        update_log "getting policy name"
        n=0
        while [[ $n -lt 10 ]]; do
            log_entry=$( tail -n 1 "$jamf_log" )
            if [[ $log_entry != "$last_log_entry" ]]; then
                if [[ "$log_entry" == *"Executing Policy"* ]]; then
                    policy_name=$( sed 's|^.*Executing Policy ||' <<< "$log_entry" )
                    break
                fi
                last_log_entry="$log_entry"
                $(( n++ ))
            fi
            sleep 0.1
        done
        if [[ $policy_name ]]; then
            update_log "policy name is $policy_name"
            launch_dialog
            update_log "Processing Jamf Log"
            read_jamf_log
        else
            update_log "policy name not found"
        fi
        update_log "All Done we think"
    fi
    quit_script
}

main 
exit 0