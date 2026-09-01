#!/bin/zsh

# Check for argument
if [[ -z "$1" ]]; then
    echo "Usage: $0 <folder_path>"
    exit 1
fi

BASE_DIR="$1"
TARGET_DIR="$BASE_DIR"

# Verify directory exists
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: Directory $TARGET_DIR does not exist."
    exit 1
fi

# Ensure exiftool is available
if ! command -v exiftool &> /dev/null; then
    echo "Error: exiftool required. Install options:"
    echo "  Homebrew: brew install exiftool"
    echo "  Source pkg (macOS): https://exiftool.org/"
    exit 1
fi

typeset -A seen_locations

# Process each image
while IFS= read -r -d '' file; do
    # Extract date: prefer EXIF DateTimeOriginal, fall back to file modified date
    date_str=$(exiftool -DateTimeOriginal -s3 "$file" 2>/dev/null | awk 'NF {print $1; exit}' | sed 's/:/-/g')

    if [[ -z "$date_str" ]]; then
        file_mtime=$(stat -f "%m" "$file" 2>/dev/null)
        if [[ -n "$file_mtime" ]]; then
            date_str=$(date -r "$file_mtime" "+%Y-%m-%d" 2>/dev/null)
        fi
    fi

    if [[ -z "$date_str" ]]; then
        continue
    fi

    year="${date_str:0:4}"
    full_date="$date_str"

    # Extract location summary
    loc=$(exiftool -Composite:City -Composite:Country -s3 "$file" 2>/dev/null | grep -v '^$' | paste -sd ", " -)
    loc_safe="${loc//\//-}"
    loc_safe="${loc_safe//:/-}"

    if [[ -n "$loc" ]]; then
        if [[ -z "${seen_locations[$loc]+x}" ]]; then
            echo "Location found: $loc"
            seen_locations["$loc"]=1
        fi
        location_dir="$full_date $loc_safe"
    else
        location_dir=""
    fi

    # Build target path
    if [[ -n "$location_dir" ]]; then
        dest_dir="$TARGET_DIR/$year/$location_dir"
    else
        dest_dir="$TARGET_DIR/$year/$full_date"
    fi

    # Only log when the folder actually gets created
    if [[ ! -d "$dest_dir" ]]; then
        mkdir -p "$dest_dir"
        echo "New date folder: $year/$full_date${location_dir:+ $loc_safe}"
    fi

    mv "$file" "$dest_dir/"
done < <(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" -o -iname "*.png" -o -iname "*.mov" \) -print0)

echo "Organized photos into hierarchical folders in $TARGET_DIR"
