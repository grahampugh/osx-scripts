#!/bin/bash

### Fusion Drive Checker.
### by Graham Pugh.
### Adapted from script by "henkb"; http://deploystudio.com/Forums/viewtopic.php?id=4914

# This script checks disk0 to see whether it is HFS or CoreStorage, using the diskutil tool.
# If it is CoreStorage, the script then checks disk1 to see if it is SATA.
# If disk1 is SATA, it checks that this is also CoreStorage, and if so we assume that 
# this is a Fusion Drive. 
# If disk1 is not SATA, we assume that it is an external disk, implying that disk0 is 
# in fact a FileVaulted volume.
#
# When added to DeployStudio as a WorkFlow Returned by Script, this script can automatically invoke
# a Fusion Drive partitioning workflow on a Mac with a disk0+disk1 Fusion Drive
# Mac, but pass straight on to a Restore task for non-fusion Macs.
#
# The only thing to edit is your workflow identifier - see inline comments.

echo
echo "### Checking filesystem architecture on disk0 (HFS or CoreStorage). ###"
TYPE=$(diskutil list | grep -A4 /dev/disk0 | tail -n 1 | awk '{print $2}' | cut -d "_" -f2)
if [ "$TYPE" = "HFS" ]
    then echo "# Architecture is HFS. Skipping additional steps and continue with regular DeployStudio-workflow."
elif [ "$TYPE" = "CoreStorage" ]
	then echo "# disk0 is CoreStorage. Checking for disk1."
	if system_profiler SPSerialATADataType | grep "BSD Name: disk1" ; then
		echo "# disk1 is SATA. Checking file system"
		SECOND_TYPE=$(diskutil list | grep -A4 /dev/disk1 | tail -n 1 | awk '{print $2}' | cut -d "_" -f2)
		if [ "$SECOND_TYPE" = "CoreStorage" ]
			then echo "# Two disks with CoreStorage volumes found. Existing Architecture is Fusion Drive."
			echo "RuntimeSelectWorkflow: 2790BE8F-C912-45B9-A820-19A0E6204586"  # Substitute your Fusion workflow identifier here
		else
			echo "# disk1 found, but not CoreStorage" 
		fi
	else
		echo "# disk1 not found, or is external." 
	fi
	if fdesetup status | grep On ; then
		echo "# FileVault is enabled."
	fi
else
    echo
    echo "### Problem finding file structure of hard drive(s)! Check it with Disk Utility!"
fi
exit 0
