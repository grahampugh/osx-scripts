#!/bin/zsh
# shellcheck shell=bash

: <<DESCRIPTION
Script design inspired by Kyle Hoare @ Jamf.
DESCRIPTION

##############################################################
# Global Variables
##############################################################

current_user=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
working_dir=$(dirname "$0")
apiutil_msu_script="$working_dir/apiutil-msu.zsh"

# ensure log file is writable
dialog_log=$(/usr/bin/mktemp /var/tmp/dialog.XXX)
echo "Creating dialog log ($dialog_log)..."
/usr/bin/touch "$dialog_log"
/usr/sbin/chown "${current_user}:wheel" "$dialog_log"
/bin/chmod 666 "$dialog_log"

# swiftDialog variables
dialog_app="/Library/Application Support/Dialog/Dialog.app"
dialog_bin="/usr/local/bin/dialog"
dialog_output="/var/tmp/dialog.json"
icon="/Library/Application Support/JAMF/bin/Management Action.app"

tmpdir="/tmp"
log_file="/tmp/jamf_api_log.txt"
csv_dir="/Users/Shared/APIUtilScripts/MSUPlanStatus"

##############################################################
# Functions
##############################################################

rootCheck() {
    # Check that the script is NOT running as root
    if [[ $EUID -eq 0 ]]; then
        echo "### This script is NOT MEANT to run as root."
        echo "This script is meant to be run as an admin user."
        echo "Please run without sudo."
        echo
        exit 4 # Running as root.
    fi
}

##############################################################
# Check if SwiftDialog is installed
##############################################################

dialog_check() {
    # URL to get latest swift dialog
    swiftdialog_api_url="https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest"
    # obtain the download URL
    dialog_download_url=$(curl -sL -H "Accept: application/json" "$swiftdialog_api_url" | awk -F '"' '/browser_download_url/ { print $4; exit }')

    if ! command -v "$dialog_bin" >/dev/null ; then
        echo "SwiftDialog is not installed. App will be installed now....."
        dialog_install
    else
        echo "SwiftDialog is installed. Checking installed version....."
        
        dialog_installed_version=$("$dialog_bin" -v | sed 's/\.[0-9]*$//')
        
        # obtain the tag
        dialog_latest_version=$(curl -sL -H "Accept: application/json" "$swiftdialog_api_url" | awk -F '"' '/tag_name/ { print $4; exit }')
        if [[ ! $dialog_latest_version ]]; then
            echo "Could not obtain latest version information, proceeding without check..."
        elif [[ "$dialog_installed_version" != "${dialog_latest_version//v/}" ]]; then
            echo "Dialog needs updating (v$dialog_installed_version older than $dialog_latest_version)"
            dialog_install
            sleep 3
        else
            echo "Dialog is up to date. Continuing...."
        fi
    fi
}

dialog_install() {
    # install
    if /usr/bin/curl -L "$dialog_download_url" -o "$tmpdir/dialog.pkg" ; then
        if sudo installer -pkg "$tmpdir/dialog.pkg" -target / ; then
            dialog_string=$("$dialog_bin" --version)
        else
            echo "swiftDialog installation failed"
            exit 1
        fi
    else
        echo "swiftDialog download failed"
        exit 1
    fi
    # check it did actually get downloaded
    if [[ -d "$dialog_app" && -f "$dialog_bin" ]]; then
        echo "swiftDialog v$dialog_string is installed"
    else
        echo "Could not download swiftDialog."
        exit 1
    fi

    /bin/rm "$tmpdir/dialog.pkg" ||:
}

##############################################################
# This function sends a command to our command file, and sleeps briefly to avoid race conditions
##############################################################

dialog_command()
{
    echo "$@" >> "$dialog_log" 2>/dev/null & sleep 0.1
}

dialog_command_with_output()
{
    "$dialog_bin" "$@" 2>/dev/null > "$dialog_output" & sleep 0.1
}

initial_dialog() {
    # shellcheck disable=SC2054
    dialog_args=(
        --commandfile
        "$dialog_log"
        --title "Managed Software Updates Wizard"
        --position centre
        --moveable
        --icon "$icon"
        --message "Choose the options below.\n\nEnter a target server from the API Utility if you have more than one server configured."
        --button1text "Continue"
        --button2text "Quit"
        --alignment left
        --infobox '[grahampugh/osx-scripts](https://github.com/grahampugh/osx-scripts)'
        --messagefont 'name=Arial,size=16'
        --selecttitle "Options",radio
        --selectvalues "Create Plan, View Plans, View Update Statuses, Toggle Software Update Feature"
        --textfield 'Target Server,prompt='
        --height 500
        --json
        --ontop
    )
    echo "quit:" >> "$dialog_log"
    "$dialog_bin" "${dialog_args[@]}" 2>/dev/null > "$dialog_output"
    if [[ $? -eq 2 ]]; then
        echo "User cancelled dialog so exiting..."
        exit 0
    fi
}

create_dialog() {
    # shellcheck disable=SC2054
    dialog_args=(
        --commandfile
        "$dialog_log"
        --title "Managed Software Updates Wizard"
        --position centre
        --moveable
        --icon "$icon"
        --message "Choose the options below.\n\nEnter a Computer or Mobile Device Group.\n\nOnly fill in a specific version if you select the Specific Version option for Version Type."
        --button1text "Continue"
        --button2text "Quit"
        --alignment left
        --infobox '[grahampugh/osx-scripts](https://github.com/grahampugh/osx-scripts)'
        --messagefont 'name=Arial,size=16'
        --selecttitle "Device Type",radio
        --selectvalues "Computer, Mobile Device, Apple TV"
        --selecttitle "Version Type",radio
        --selectvalues "Latest Minor, Latest Major, Specific Version"
        --textfield 'Target Group,prompt='
        --textfield 'Specific Version,prompt='
        --textfield 'Days Until Forced Install,prompt=7'
        --height 700
        --json
        --ontop
    )
    echo "quit:" >> "$dialog_log"
    "$dialog_bin" "${dialog_args[@]}" 2>/dev/null > "$dialog_output"
    if [[ $? -eq 2 ]]; then
        echo "User cancelled dialog so exiting..."
        exit 0
    fi
}

plan_dialog() {
    dialog_args=(
        --commandfile
        "$dialog_log"
        --title "Managed Software Updates Wizard"
        --position centre
        --moveable
        --icon "$icon"
        --message "Choose the options below." \
        --button1text "Continue"
        --button2text "Quit"
        --alignment left
        --infobox '[grahampugh/osx-scripts](https://github.com/grahampugh/osx-scripts)'
        --messagefont 'name=Arial,size=16'
        --checkbox "Open CSV file"
        --checkbox "Get Event Store Info"
        --checkboxstyle switch
        --height 500
        --json
        --ontop
    )
    echo "quit:" >> "$dialog_log"
    "$dialog_bin" "${dialog_args[@]}" 2>/dev/null > "$dialog_output"
    if [[ $? -eq 2 ]]; then
        echo "User cancelled dialog so exiting..."
        exit 0
    fi
}

update_status_dialog() {
dialog_args=(
        --commandfile
        "$dialog_log"
        --title "Managed Software Updates Wizard"
        --position centre
        --moveable
        --icon "$icon"
        --message "Choose the options below." \
        --button1text "Continue"
        --button2text "Quit"
        --alignment left
        --infobox '[grahampugh/osx-scripts](https://github.com/grahampugh/osx-scripts)'
        --messagefont 'name=Arial,size=16'
        --checkbox "Open CSV file"
        --checkboxstyle switch
        --height 500
        --json
        --ontop
    )
    echo "quit:" >> "$dialog_log"
    "$dialog_bin" "${dialog_args[@]}" 2>/dev/null > "$dialog_output"
    if [[ $? -eq 2 ]]; then
        echo "User cancelled dialog so exiting..."
        exit 0
    fi
}

progress_dialog() {
    # show progress
    dialog_args=(
        --commandfile
        "$dialog_log"
        --title "Managed Software Updates Wizard"
        --position centre
        --moveable
        --icon "$icon"
        --message "Your request is being processed..."
        --button1disabled
        --progress 1
        --alignment left
        --infobox '[grahampugh/osx-scripts](https://github.com/grahampugh/osx-scripts)'
        --messagefont 'name=Arial,size=16'
        --ontop
    )
    "$dialog_bin" "${dialog_args[@]}" 2>/dev/null & sleep 0.1

    echo "progresstext: Processing" >> "$dialog_log"
    echo  "progress: 0" >> "$dialog_log"
}

done_dialog() {
    # done dialog
    output=$(tail -n 1 "$log_file")
    if [[ ! $output ]]; then
        output="(no output)"
    fi
    dialog_args=(
        --commandfile
        "$dialog_log"
        --title "Managed Software Updates Wizard"
        --position centre
        --moveable
        --icon "$icon"
        --message "The process is now completed with the following output::\n\n$output"
        --button1text "Perform another action"
        --button2text "Quit"
        --alignment left
        --infobox '[grahampugh/osx-scripts](https://github.com/grahampugh/osx-scripts)'
        --messagefont 'name=Arial,size=16'
        --ontop
    )
    echo "quit:" >> "$dialog_log" & sleep 0.1
    "$dialog_bin" "${dialog_args[@]}" 2>/dev/null > "$dialog_output"
    if [[ $? -eq 2 ]]; then
        echo "User cancelled dialog so exiting..."
        exit 0
    fi
}

failed_dialog() {
    # done dialog
    error=$(tail -n 1 "$log_file")
    dialog_args=(
        --commandfile
        "$dialog_log"
        --title "Managed Software Updates Wizard"
        --position centre
        --moveable
        --icon "$icon"
        --message "There was an error:\n\n$error"
        --button1text "Perform another action"
        --button2text "Quit"
        --alignment left
        --infobox '[grahampugh/osx-scripts](https://github.com/grahampugh/osx-scripts)'
        --messagefont 'name=Arial,size=16'
        --ontop
    )
    echo "quit:" >> "$dialog_log" & sleep 0.1
    "$dialog_bin" "${dialog_args[@]}" 2>/dev/null
}

rootCheck
dialog_check

while true; do
    args=()
    echo "" > "$log_file"

    initial_dialog

    ##############################################################
    # Gather information from the dialog
    ##############################################################

    # cat "$dialog_output" # TEMP

    OPTION=$(plutil -extract "Options.selectedValue" raw "$dialog_output" 2>/dev/null)
    TARGET=$(plutil -extract "Target Server" raw "$dialog_output" 2>/dev/null)
    if [[ "$TARGET" ]]; then
        args+=(--path "$TARGET")
    fi

    if [[ "$OPTION" == "Create Plan" ]]; then
        args+=(--create)
        create_dialog
        # cat "$dialog_output" # TEMP
        DEVICE_TYPE=$(plutil -extract "Device Type.selectedValue" raw "$dialog_output" 2>/dev/null | tr '[:lower:]' '[:upper:]' | sed 's| |_|g')
        args+=(--device-type "$DEVICE_TYPE")
        VERSION_TYPE=$(plutil -extract "Version Type.selectedValue" raw "$dialog_output" 2>/dev/null | tr '[:lower:]' '[:upper:]' | sed 's| |_|g')
        args+=(--version-type "$VERSION_TYPE")
        SPECIFIC_VERSION=$(plutil -extract "Specific Version" raw "$dialog_output" 2>/dev/null)
        args+=(--specific-version "$SPECIFIC_VERSION")
        TARGET_GROUP=$(plutil -extract "Target Group" raw "$dialog_output" 2>/dev/null)
        args+=(--group "$TARGET_GROUP")
        DAYS=$(plutil -extract "Days Until Forced Install" raw "$dialog_output" 2>/dev/null)
        if [[ $DAYS ]]; then
            args+=(--days-until-force-install "$DAYS")
        fi

    elif [[ "$OPTION" == "View Plans" ]]; then
        args+=(--plan)
        plan_dialog
        # cat "$dialog_output" # TEMP
        OPEN_CSV=$(plutil -extract "Open CSV file" raw "$dialog_output" 2>/dev/null)
        if [[ "$OPEN_CSV" ]]; then
            args+=(--open)
        fi
        GET_EVENTS=$(plutil -extract "Get Event Store Info" raw "$dialog_output" 2>/dev/null)
        if [[ "$GET_EVENTS" ]]; then
            args+=(--events)
        fi

    elif [[ "$OPTION" == "View Update Statuses" ]]; then
        args+=(--status)
        # cat "$dialog_output" # TEMP
        update_status_dialog
        OPEN_CSV=$(plutil -extract "Open CSV file" raw "$dialog_output" 2>/dev/null)
        if [[ "$OPEN_CSV" ]]; then
            args+=(--open)
        fi

    elif [[ "$OPTION" == "Toggle Software Update Feature" ]]; then
        args+=(--toggle)
        args+=(--i-am-sure)
        cat "$dialog_output" # TEMP
    fi

    # echo "${args[*]}" # TEMP

    ##############################################################
    # Assemble options
    ##############################################################

    # now run
    progress_dialog >/dev/null 2>&1
    if "$apiutil_msu_script" "${args[@]}"; then
        echo "progress: complete" >> "$dialog_log"
        echo "quit:" >> "$dialog_log" & sleep 0.1
        done_dialog
    else
        echo "progress: complete" >> "$dialog_log"
        echo "quit:" >> "$dialog_log" & sleep 0.1
        failed_dialog
    fi

    if [[ ("$OPTION" == "View Plans" || "$OPTION" == "View Plans") && ! $OPEN_CSV ]]; then
        # open the enclosing folder
        open "$csv_dir"
    fi
done
