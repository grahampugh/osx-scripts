#!/bin/bash

### ACTIVE DIRECTORY USER PERMISSIONS SCRIPT ###
### by Graham Pugh
### Props to Jeff Kelley, Graham Gilbert and various others for elements of script

### This script looks at the "Allow Administration By" field of the 
### `dsconfigad -show` command and checks each of the Active Directory users  
### with mobile accounts on the computer to check whether they should have
### local admin rights.  It amends each user's membership of the local 
### 'admin' group accordingly.
###
### This ensures that users retain admin rights when away from the bound network,
### but removes any users that are no longer eligible for admin rights once the 
### computer sees the network again.

### This script can be run as a LaunchDaemon to run when a user logs in, 
### to automatically check whether they have admin rights or not

sleep 15 # wait before executing to give network time to start

log() {
  # LOGFILE="/var/log/check_local_admin.log"
  echo "${@}" 2>&1 
  logger -t check_local_admin "${@}"
}

# Find the computer's hostname.
readonly HOSTNAME=$( scutil --get LocalHostName );
echo "### Local Administrator Check:"
echo "Host Name        = $HOSTNAME"

# Find out what the existing Allowed Administrator group is
readonly CombinedADGroups=$( dsconfigad -show | grep "Allowed admin groups"  | awk '{print $5}' )

# Set some arrays
CombinedADGroupArray=()
DomainNetBIOSNameArray=()
ADGroupArray=()

# If there's more than one Allowed Administrator group, 
# we need to split and search through them all
IFS=',' read -ra BIGARR <<< "$CombinedADGroups"
for i in "${BIGARR[@]}"; do
	# Create arrays for each variable
	IFS='\' read -ra ADARR <<< "$i"
	CombinedADGroupArray+=($i)
	NetBIOSNameArray+=(${ADARR[0]})
	ADGroupArray+=(${ADARR[1]})
	echo ""
	echo "AD Domain        = ${NetBIOSNameArray[${#NetBIOSNameArray[@]}-1]}"
	echo "AD Name          = ${ADGroupArray[${#ADGroupArray[@]}-1]}"
	echo "AD Admin Group   = ${CombinedADGroupArray[${#CombinedADGroupArray[@]}-1]}"
done


# Let's not do anything until we wait for the network to come alive
# This is set to check once per 10 seconds and die after 5 minutes

# Including stuff to check for a network
. /etc/rc.common

CheckForNetwork

# check for the network 6 times over a minute before abandoning
# loopcount=0
# while [[ "${NETWORKUP}" != "-YES-" && "$loopcount" -lt 6 ]]; do
# 		log "Network not ready (attempt ${loopcount+1}). Trying again..."
#         sleep 10
#         NETWORKUP=
#         CheckForNetwork
#         ((loopcount++))
# done

if [ "${NETWORKUP}" != "-YES-" ]; then
	log "### Not connected to a network. Leaving local admins alone."
	exit 0
fi

# Next, check that we are connected to AD

# You can search for a user to check this, but we can't be generic that way
# id someUserName &>/dev/null 

# Let's search for our own computer object instead. If we can't find this, 
# then we're not bound to AD, or not connected, and we should stop

# We need to check each domain that we might be joined to
domainCheck=0
for (( c=0 ; c<=${#NetBIOSNameArray[@]}-1; c++ )); do
	dscl "/Active Directory/${NetBIOSNameArray[$c]}/All Domains" \
		-read /Computers/${HOSTNAME}$ &>/dev/null 
	if [ $? -eq 0 ]; then 
		domainCheck=1
	fi
done

if [ "$domainCheck" -eq 0 ]; then
	log "### Not connected or properly bound to AD. Leaving local admins alone."
	exit 0
fi

# OK, let's carry on, as we are connected: 

# Find all the users on this computer. Ignore system users.
dscl . list /Users | grep -v '^_.*\|daemon\|root\|nobody' | while read localUser
do
	# check if user is in the local admin group
	IsLocalAdmin=$( \
		dseditgroup -o checkmember -m $localUser admin \
		| awk '{print $1}' )

	# Grab the information from AD about this user
	ADGroups=$( id ${localUser} )
	
	# setLocalAdmin is used to determine whether the user is: 
	# an AD user in the admin group (Yes)
	# an AD user not in the admin group (No)
	# not an AD user, i.e. a local user (NotAD)
	setLocalAdmin="No" 
		
	# loop through the AD groups
	for (( c=0 ; c<=${#NetBIOSNameArray[@]}-1; c++ )); do
		# Is this a Mobile user (not a local account)?
		if [[ "$ADGroups" =~ "${NetBIOSNameArray[$c]}" ]]; then
			# Is this mobile user in the correct AD local admin group?
			if [[ "$ADGroups" =~ "${ADGroupArray[$c]}" ]]; then
				log "### User $localUser is member of AD group ${CombinedADGroupArray[$c]}"
				setLocalAdmin="Yes"
			fi
		else
			setLocalAdmin="NotAD"
		fi
	done
	if [[ "$setLocalAdmin" = "NotAD" ]]; then
		log "### User $localUser is not an AD user. Nothing to change."
	elif [[ "$setLocalAdmin" = "Yes" ]]; then
		/usr/sbin/dseditgroup -o edit -a $localUser -t user admin
	else
		log "### User $localUser is not a member of any AD groups. Setting as standard user"
		/usr/sbin/dseditgroup -o edit -d $localUser -t user admin
	fi
done

echo ""

exit 0

