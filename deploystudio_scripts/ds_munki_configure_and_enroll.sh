#!/bin/bash 

### Munki configurator and auto-enroller
### by Graham Pugh

# This script can be packaged with Munki to automatically point your client to your
# Munki server, set defaults such as the Client Identifier, whether to install Apple Updates
#
# This particular script looks for a Local Host Name in the form ITxxxxxx, e.g. IT012345
# - change the "ITTAGCHECK" to suit your naming pattern.
# If the name doesn't match that, the script sets the localhost name to the Mac's 
# serial number.
# It prepends the resulting LocalHostName with "client-", to produce the ClientIdentifier. 
# Set this as you wish.
#
# Finally it pushes these details to enroll.php on the Munki Server.
# The munki-enroll folder should be placed in your munki repo.
# You need to set group write permissions to _www to the manifests folder of your munki repo.

# The Munki Repo URL
MUNKI_REPO_URL="http://your.munki.server/munki_repo"

# The ClientIdentifier - the default is "site_default"
IDENTIFIER="site_default"

# This setting determines whether Munki should handle Apple Software Updates
# Set to false if you want Munki to only deal with third party software (false is default)
defaults write /Library/Preferences/ManagedInstalls InstallAppleSoftwareUpdates -bool True

# The existence of this file prods Munki to check for and install updates upon startup
# If you'd rather your clients waited for an hour or so, so that users aren't
# bothered at login, comment this out
touch /Users/Shared/.com.googlecode.munki.checkandinstallatstartup

# Figures out the computer's local host name - don't use ComputerName as this may contain bad characters
LOCALHOSTNAME=$( scutil --get LocalHostName );

# Checks whether it is a valid IT tag - you can choose your own naming scheme
ITTAGCHECK=`echo $LOCALHOSTNAME | grep -iE '\<IT[0-9]{6}\>'`
if [ $? -ne 0 ]; then
	# Sets the LocalHostName to the serial number if we don't have an IT tag name
	SERIAL=`/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Serial\ Number\ \(system\)/ {print $NF}'`
	scutil --set LocalHostName "$SERIAL"
	LOCALHOSTNAME="$SERIAL"
fi

# set the ClientIdentifier to "client-LOCALHOSTNAME"
defaults write /Library/Preferences/ManagedInstalls ClientIdentifier "client-$LOCALHOSTNAME"

# Sets the URL to the Munki Repository
defaults write /Library/Preferences/ManagedInstalls SoftwareRepoURL "$MUNKI_REPO_URL"

### This is the Munki-enroll bit - nothing to edit here

# Leave this unless you have put your munki-enroll script somewhere unusual
SUBMITURL="$MUNKI_REPO_URL/munki-enroll/enroll.php"

# Application paths
CURL="/usr/bin/curl"

$CURL --max-time 5 --data \
	"hostname=$LOCALHOSTNAME&identifier=$IDENTIFIER" \
    $SUBMITURL
 	 
exit 0