#!/bin/bash
#
# autopkg update-trust-info for recipe lists.
# by Graham Pugh
#
# This updates trust for all recipes in a repo list. 
# Optionally, it forces a new override.

usage() {
    echo
    echo "   Usage:"
    echo "   ./autopkg-update-trust-info-recipe-list.sh '<RECIPE-LIST>'"
    echo
    echo "   Tip: use 'autopkg search product.jamf' to find out whether a jamf recipe exists."
    echo "   If a recipe exists, check that the repo is already added using 'autopkg repo-list'"
    echo "   To add a new repo, use 'autopkg repo-add <REPO-NAME>'"
    echo
    echo "   Notes:"
    echo "    - use '-v[v]' for verbosity of the verify-trust-info output"
    echo "    - use '--verify-only' to only verify the recipe, not update it"
    echo "    - use '--force' to force a new override rather than update the existing override with update-trust-info"
    echo "    - use '--format plist' to specify a plist format override (default is yaml)"
    echo "    - use '--pull' to add any missing parent repos to your repos"
    echo "    - use '--prefs' to point to a different autopkg preferences file"
    echo "    - use '--overrides-directory' to point to a different RecipeOverrides directory"
    echo
}

make_override() {
    recipe_name="$1"
    # skip any blank lines
    if [[ ! "$recipe_name" ]]; then
        return
    fi

    echo
    echo "   ---"
    echo "   Recipe to Override: '${recipe_name}'"

    pull=""
    if [[ $pull_parents -eq 1 ]]; then
        pull="--pull"
    fi

    # check if there is already an override
    echo "   Checking for existing override in ${RECIPE_OVERRIDE_DIR}..."
    # look for an existing recipe in the overrides first, unless using --force option
    if [[ $force_new_override -eq 1 ]]; then
        echo "   Forcing new override for recipe ${recipe_name}..."
        echo "   WARNING! Any local changes to the override will be lost."
        echo
        ${AUTOPKG} make-override "${recipe_name}" --force --prefs "$AUTOPKG_PREFS" --override-dir="${RECIPE_OVERRIDE_DIR}" --format="$recipe_format" $pull
    else
        if ! ${AUTOPKG} verify-trust-info "${recipe_name}" --prefs "$AUTOPKG_PREFS" --override-dir="${RECIPE_OVERRIDE_DIR}" $verbosity; then
            if [[ $verify_only -ne 1 ]]; then
                echo
                echo "   Updating trust info for recipe ${recipe_name}..."
                echo
                ${AUTOPKG} update-trust-info "${recipe_name}" --prefs "$AUTOPKG_PREFS" --override-dir="${RECIPE_OVERRIDE_DIR}"
            else
                echo
                echo "   Recipe ${recipe_name} not trusted."
            fi
        else
            echo
            echo "    Recipe ${recipe_name} is already trusted, so nothing to do."
        fi
    fi
}


## MAIN BODY

# defaults
inputted_list=""
recipe_format="yaml"
pull_parents=0
verify_only=0
verbosity=""
RECIPE_OVERRIDE_DIR="${HOME}/Library/AutoPkg/RecipeOverrides"
AUTOPKG="/usr/local/bin/autopkg"
AUTOPKG_PREFS="$HOME/Library/Preferences/com.github.autopkg.plist"

echo
echo " # AutoPkg update-trust-info for recipe lists, by Graham Pugh"
echo 

# grab inputs
while test $# -gt 0
do
    case "$1" in
        --prefs)
            shift
            AUTOPKG_PREFS="$1"
            [[ $AUTOPKG_PREFS == "/"* ]] || AUTOPKG_PREFS="$(pwd)/${AUTOPKG_PREFS}"
            ;;
        --overrides-directory)
            shift
            RECIPE_OVERRIDE_DIR="$1"
            ;;
        --force) 
            force_new_override=1
            ;;
        --pull) 
            pull_parents=1
            ;;
        --verify-only) 
            verify_only=1
            ;;
        --format) 
            shift
            recipe_format="$1"
            ;;
        -v) 
            verbosity="-v"
            ;;
        -vv*) 
            verbosity="-vv"
            ;;
        -h|--help|-*)
            usage
            exit 0
            ;;
        *)
            inputted_list="$1"
            ;;
    esac
    shift
done

# reset force if verify-only chosen
if [[ $verify_only -eq 1 ]]; then
    force_new_override=0
fi

# check that the prefs file exists
echo "   AutoPkg prefs file: $AUTOPKG_PREFS"
if [[ ! -f "$AUTOPKG_PREFS" ]]; then
    echo "   ERROR: Specified preferences file does not exist!"
    exit 1
fi

# check that the overrides path exists
echo "   RecipeOverrides directory: $RECIPE_OVERRIDE_DIR"
if [[ ! -d "$RECIPE_OVERRIDE_DIR" ]]; then
    echo "   ERROR: Specified RecipeOverrides directory does not exist!"
    exit 2
fi

# check recipe format validity
if [[ "$recipe_format" != "yaml" && "$recipe_format" != "plist" ]]; then
    echo "   WARNING: invalid recipe override format specified. Using 'yaml'."
    recipe_format="yaml"
fi

# get recipes from list
if [[ -f "$inputted_list" ]]; then
    while IFS='' read -r line || [[ -n "$line" ]]; do
        inputted_jamf_recipe="${line}"
        make_override "$inputted_jamf_recipe"
    done < "${inputted_list}"
else
    echo "   ERROR: no recipe list specified."
    usage
    exit 3
fi
