#!/bin/zsh
# shellcheck shell=bash

# Sourced from @isaac via @Henry at https://macadmins.slack.com/archives/C0C4X3G3W/p1698417748947319?thread_ts=1698093407.530229&cid=C0C4X3G3W

CURRENT_CATALOG="https://swscan.apple.com/content/catalogs/others/index-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog"

xProtectURL=$(curl -s "$CURRENT_CATALOG" | grep -m 1 -o 'https.*XProtectPlistConfigData.*pkm')
xProtectLatestVersion=$(curl -s "${xProtectURL}" | grep -o 'CFBundleShortVersionString[^ ]*' | cut -d '"' -f 2)
xProtectInstalledVersion=$(defaults read /Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist CFBundleShortVersionString)

if [[ "$xProtectLatestVersion" == "$xProtectInstalledVersion" ]]; then
	echo "<result>Pass</result>"
else
	echo "<result>Fail</result>"
fi
