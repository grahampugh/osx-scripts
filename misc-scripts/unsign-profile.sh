#!/bin/bash

# A script that will take a signed mobileconfig profile
# and create an unsigned version of it in the same directory.
# Can be used inside an Apple Shortcuts workflow or run from the command line.

input="$1"

# Verify the file has .mobileconfig extension
if [[ "$input" != *.mobileconfig ]]; then
    echo "Error: File must have .mobileconfig extension"
    exit 1
fi

# Verify the file exists
if [[ ! -f "$input" ]]; then
    echo "Error: File does not exist: $input"
    exit 1
fi

# Test if the file is a valid signed mobileconfig by attempting to decode it
if security cms -D -i "$input" -o /dev/null 2>/dev/null; then
    # File is signed, proceed with creating unsigned version
    # Determine source and target filenames based on whether input contains -signed
    if [[ "$input" == *-signed.mobileconfig ]]; then
        base_name="${input%-signed.mobileconfig}"
        signed_filename="$input"
        unsigned_filename="${base_name}-unsigned.mobileconfig"
        target_filename="${base_name}.mobileconfig"
    else
        base_name="${input%.mobileconfig}"
        signed_filename="${base_name}-signed.mobileconfig"
        unsigned_filename="${base_name}-unsigned.mobileconfig"
        target_filename="$input"
    fi
    
    # Extract unsigned content
    security cms -D -i "$input" -o "$unsigned_filename"
    # move the signed profile to -signed.mobileconfig (only if it doesn't already end with -signed)
    if [[ "$input" != *-signed.mobileconfig ]]; then
        mv "$input" "$signed_filename"
    fi
    
    # move the unsigned profile to target filename while linting it using plutil
    if plutil -convert xml1 "$unsigned_filename" -o "$target_filename"; then
        echo "Successfully created unsigned profile: $target_filename"
        echo "Original signed profile saved as: $signed_filename"
        rm -f "$unsigned_filename"
        exit 0
    else
        echo "Error: Failed to create unsigned profile"
        exit 1
    fi
else
    # Check if it's a valid plist but unsigned
    if plutil -lint "$input" > /dev/null 2>&1; then
        echo "Error: File is a valid mobileconfig but is already unsigned"
    else
        echo "Error: File is not a valid mobileconfig file"
    fi
    exit 1
fi
