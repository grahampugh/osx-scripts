#!/bin/bash

# Run this script to create a DMG containing the Matlab installer files

# Enter a volume name
VOLNAME="Matlab-R2015a-installer-files"

# Filenames you want to pack
INSTALLER="R2015a-maci64.iso"
LICENSE_FILE="network.lic"
INSTALLER_FILE="installer_input.txt"

# STOP EDITING
	
output_Name="${VOLNAME}.dmg"

mkdir tmp
ls ${INSTALLER} ${LICENSE_FILE} ${INSTALLER_FILE} | while read script
do
	echo "MATLAB DMG maker."
	mv $script tmp/
done
hdiutil create \
	-volname "${VOLNAME}" \
	-srcfolder ./tmp \
	-ov \
	$output_Name
mv tmp/* .
rm -rf tmp
exit 0