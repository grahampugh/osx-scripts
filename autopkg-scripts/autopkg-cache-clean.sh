#!/bin/bash
#
# cache-clean for AutoPkg.
# by Graham Pugh
#
# This removes all but the most recent versions of packages and downloads in an AutoPkg cache

# default number of pkgs and downloads to keep if not overridden
keep_pkgs=2
keep_downloads=2

# Recipe Repos directory
RECIPE_CACHE_DIR="${HOME}/Library/AutoPkg/Cache"

# functions
usage() {
    echo "Usage: ./autopkg-cache-clean.sh [--downloads X] [--pkgs Y] [--RECIPE_CACHE_DIR /path/to/Cache]"
    echo "Default number of packages and files in downloads folder is 2"
}


# grab inputs
while test $# -gt 0; do
    case "$1" in
        -h|--help)
            usage
            exit
            ;;
        -p|--pkgs)
            # specify the number of packages to be kept in the root folder of the cache folder
            shift
            keep_pkgs="$1"
            ;;
        -d|--downloads)
            # specify the number of files to be kept in the downloads folder of the cache folder
            shift
            keep_downloads="$1"
            ;;
        --RECIPE_CACHE_DIR)
            # RECIPE_CACHE_DIR can be supplied. Defaults to ${HOME}/Library/AutoPkg/Cache"
            shift
            RECIPE_CACHE_DIR="$1"
            ;;
    esac
    shift
done

temp_file=/tmp/autopkg-cache-clean-tmp.txt

pkgs_deleted=0
downloads_deleted=0

# iterate through folders in the cache
cache_base=$(basename "$RECIPE_CACHE_DIR")
find "$RECIPE_CACHE_DIR" -type d -maxdepth 1 ! -name "$cache_base" > "$temp_file"
while IFS= read -r folder; do
    (( count++ ))
    base=$(basename "$folder")

    # find and remove old packages
    pkgs=("$folder"/*.pkg*)
    pkg_count=${#pkgs[@]}
    tail_value=$(( pkg_count - keep_pkgs ))
    if [[ $tail_value -gt 0 ]]; then
        pkgs_deleted=$(( pkgs_deleted + tail_value ))
        echo
        echo "Folder: $base"
        find "$folder" -name "*.pkg*" -maxdepth 1 -exec ls -dt {} + | tail -n $tail_value | while read -r old_pkg; do
            echo "Deleting $old_pkg"
            if [[ -d "$old_pkg" ]]; then
                rm -rf "$old_pkg"
            else
                rm "$old_pkg"
            fi
        done
    fi

    # find and remove old downloads
    downloads=("$folder"/downloads/*)
    # remove any temp files
    find "$folder/downloads" -name "tmp*" -type f -maxdepth 1 -exec rm {} + 2>/dev/null
    # now look for actual downloaded files
    downloads_count=${#downloads[@]}
    tail_value=$(( downloads_count - keep_downloads ))
    if [[ $tail_value -gt 0 ]]; then
        downloads_deleted=$(( downloads_deleted + tail_value ))
        echo
        echo "Folder: $base/downloads"
        find "$folder/downloads" -name "*.*" -maxdepth 1 -exec ls -dt {} + | tail -n $tail_value | while read -r old_file; do
            echo "Deleting $old_file"
            if [[ -d "$old_file" ]]; then
                rm -rf "$old_file"
            else
                rm "$old_file"
            fi
        done
    fi

done < "$temp_file"
rm "$temp_file"

echo
echo "Total $count folders parsed"
echo "Total $pkgs_deleted pkgs deleted"
echo "Total $downloads_deleted downloads deleted"
