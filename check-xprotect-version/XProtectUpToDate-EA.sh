#!/bin/zsh
# shellcheck shell=bash

# Adapted from @isaac via @Henry at https://macadmins.slack.com/archives/C0C4X3G3W/p1698417748947319?thread_ts=1698093407.530229&cid=C0C4X3G3W

# check that a cached catalog exists
CATALOG_CACHE="/var/sucatalog/current-catalog.sucatalog"

# get the current reported XProtect version
if [[ -f "$CATALOG_CACHE" ]]; then
    xProtectURL=$(grep -m 1 -o 'https.*XProtectPlistConfigData.*pkm' < "$CATALOG_CACHE")
    xProtectLatestVersion=$(curl -s "${xProtectURL}" | grep -o 'CFBundleShortVersionString[^ ]*' | cut -d '"' -f 2)
else
    echo "<result>No catalog found</result>"
    exit 0
fi

xProtectInstalledVersion=$(defaults read /Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist CFBundleShortVersionString)

if [[ "$xProtectLatestVersion" == "$xProtectInstalledVersion" ]]; then
	echo "<result>Pass</result>"
else
	echo "<result>Fail</result>"
fi
