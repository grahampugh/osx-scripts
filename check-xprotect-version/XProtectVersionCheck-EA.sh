#!/bin/zsh
# shellcheck shell=bash

# Adapted from @isaac via @Henry at https://macadmins.slack.com/archives/C0C4X3G3W/p1698417748947319?thread_ts=1698093407.530229&cid=C0C4X3G3W

# check that a cached PKM file exists
XPROTECT_PKM_CACHE="/var/sucatalog/XProtectPlistConfigData.pkm"

# get the current reported XProtect version
if [[ -f "$XPROTECT_PKM_CACHE" ]]; then
    xProtectLatestVersion=$(grep -o 'CFBundleShortVersionString[^ ]*' < "$XPROTECT_PKM_CACHE" | cut -d '"' -f 2)
else
    echo "<result>XProtect config data file not found</result>"
    exit 0
fi

xProtectInstalledVersion=$(defaults read /Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist CFBundleShortVersionString)

if [[ "$xProtectLatestVersion" == "$xProtectInstalledVersion" ]]; then
    echo "<result>Pass</result>"
else
    echo "<result>Fail</result>"
fi
