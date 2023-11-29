#!/bin/zsh
# shellcheck shell=bash

: <<DOC
This script creates a LaunchDaemon that periodically downloads the defined Apple Software Catalog.
This can be used by Jamf Extension Attributes to check whether local first party software is up to date 
DOC

SCRIPT_PATH="/Library/Scripts/download-sucatalog.sh"
LAUNCHDAEMON_LABEL="com.github.grahampugh.download-sucatalog"
LAUNCHDAEMON_PATH="/Library/LaunchDaemons/$LAUNCHDAEMON_LABEL.plist"
CURRENT_CATALOG="https://swscan.apple.com/content/catalogs/others/index-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog"
CATALOG_CACHE="/var/sucatalog/current-catalog.sucatalog"

# create script directory
/bin/mkdir -p "/Library/Scripts"

# 1. Create the Script
/usr/bin/tee "$SCRIPT_PATH" << SCRIPT
#!/bin/zsh

# This script downloads the current Apple software catalog

# create cache directory
/bin/mkdir -p "/var/sucatalog"

# download catalog
curl -s "$CURRENT_CATALOG" > "$CATALOG_CACHE"
SCRIPT

# prepare the script
chmod +x "$SCRIPT_PATH"

# 2. Create the LaunchDeamon
tee "$LAUNCHDAEMON_PATH" << LAUNCHDAEMON
<?xml version="1.0" encoding="UTF-8"?> 
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"> 
<plist version="1.0"> 
<dict> 
    <key>Label</key> 
    <string>com.github.grahampugh.download-sucatalog</string> 
    <key>ProgramArguments</key> 
    <array> 
        <string>/bin/zsh</string> 
        <string>$SCRIPT_PATH</string> 
    </array>
    <key>StartCalendarInterval</key>
    <!-- Always include Hour and Minute (default is *) -->
    <!-- Weekdays are 1 - 5; Saturday is 6; Sunday is 0 and 7 -->
    <dict>
        <key>Hour</key>
        <integer>*</integer>
        <key>Minute</key>
        <integer>15</integer>
        <key>Weekday</key>
        <integer>*</integer>
    </dict>
    <key>RunAtLoad</key> 
    <true/>
</dict> 
</plist>
LAUNCHDAEMON

# bootout the LD if it's already present
if launchctl list "$LAUNCHDAEMON_LABEL"; then
    echo "Removing existing LaunchDaemon $LAUNCHDAEMON_LABEL"
    launchctl bootout system "$LAUNCHDAEMON_PATH"
fi

# prepare and run the LaunchDaemon
echo "Bootstrapping LaunchDaemon $LAUNCHDAEMON_LABEL"
chown root:wheel "$LAUNCHDAEMON_PATH"
chmod 644 "$LAUNCHDAEMON_PATH"
launchctl bootstrap system "$LAUNCHDAEMON_PATH"
