#!/bin/bash

# Update trust info of an AutoPkg recipe list
# by Graham Pugh

show_help() {
    echo
    echo "autopkg-recipe-list-update-trust-info"
    echo "updates trust info for all .jamf.recipe[.plist][.yaml] in a folder or list"
    echo "Usage:"
    echo "./autopkg-recipe-list-update-trust-info.sh" 
    echo "  -l, --recipe-list /path/to/recipe-list.txt (optional)"
    echo "  -f, --folder /path/to/OverridesFolder (optional folder of recipes/overrides)" 
    echo "  -o, --recipe-overrides (optional, iterate through standard RecipeOverrides folder"
    echo "  -p, --prefs /path/to/autopkg-prefs.plist (optional, default is $HOME/Library/Preferences/com.github.autopkg.plist"
    echo
    exit
}

# we need arguments so exit if none are supplied
[[ $# -eq 0 ]] && show_help

# grab inputs
while test $# -gt 0; do
    case "$1" in
        -p|--prefs)
            shift
            AUTOPKG_PREFS="$1"
            [[ $AUTOPKG_PREFS == *"/"* ]] || AUTOPKG_PREFS="$(pwd)/${AUTOPKG_PREFS}"
            ;;
        -l|--recipe-list)
            shift
            AUTOPKG_RECIPE_LIST="$1"
            [[ $AUTOPKG_RECIPE_LIST == *"/"* ]] || AUTOPKG_RECIPE_LIST="$(pwd)/${AUTOPKG_RECIPE_LIST}"
            ;;
        -f|--folder)
            shift
            OVERRIDES_FOLDER="$1"
            [[ $OVERRIDES_FOLDER == *"/"* ]] || OVERRIDES_FOLDER="$(pwd)/${OVERRIDES_FOLDER}"
            ;;
        -o|--recipe-overrides)
            OVERRIDES_FOLDER="$HOME/Library/AutoPkg/RecipeOverrides"
            ;;
        *)
            show_help
            ;;
    esac
    shift
done

# provide prefs
[[ $AUTOPKG_PREFS ]] || AUTOPKG_PREFS="$HOME/Library/Preferences/com.github.autopkg.plist"
echo "AutoPkg prefs file: $AUTOPKG_PREFS"

if [[ $AUTOPKG_RECIPE_LIST ]]; then
    TEMP_LIST=$(mktemp -q /tmp/autopkg.XXX)
    cp "$AUTOPKG_RECIPE_LIST" "$TEMP_LIST"
elif [[ -d "$OVERRIDES_FOLDER" ]]; then
    if ! TEMP_LIST=$(mktemp -q /tmp/autopkg.XXX); then
        echo "$0: Can't create temp file, exiting..."
        exit 1
    fi
    for override in "$OVERRIDES_FOLDER"/*.jamf.recipe*; do
        basename "$override" >> "$TEMP_LIST"
    done

fi

# iterate through the recipe list
while IFS='' read -r line || [[ -n "$line" ]]; do
    autopkg update-trust-info "$line"
done < "${TEMP_LIST}"

rm "$TEMP_LIST"
