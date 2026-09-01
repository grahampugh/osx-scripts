#!/bin/zsh

# Reformat photo folders from patterns like:
#   "Some Moment, 18. August 2014"
#   "18. August 2014"
#   "18 August 2014"
# into:
#   "2014-08-18 Some Moment"
#   "2014-08-18"

setopt nomatch

BASE_DIR="${1:-}"

if [[ -z "$BASE_DIR" ]]; then
    echo "Usage: $0 <folder_path>"
    exit 1
fi

if [[ ! -d "$BASE_DIR" ]]; then
    echo "Error: directory not found: $BASE_DIR"
    exit 1
fi

typeset -A MONTHS
MONTHS=(
    January 01
    February 02
    March 03
    April 04
    May 05
    June 06
    July 07
    August 08
    September 09
    October 10
    November 11
    December 12
)

for sub_dir in "$BASE_DIR"/*(/N); do
    dir_name="${sub_dir:t}"

    if [[ "$dir_name" =~ ^(.*),[[:space:]]+([0-9]+)\.?[[:space:]]+([A-Za-z]+)[[:space:]]+([0-9]{4})$ ]]; then
        moment="${match[1]}"
        day="${match[2]}"
        month_name="${match[3]}"
        year="${match[4]}"
    elif [[ "$dir_name" =~ ^([0-9]+)\.?[[:space:]]+([A-Za-z]+)[[:space:]]+([0-9]{4})$ ]]; then
        moment=""
        day="${match[1]}"
        month_name="${match[2]}"
        year="${match[3]}"
    else
        continue
    fi

    month="${MONTHS[$month_name]:-}"
    if [[ -z "$month" ]]; then
        continue
    fi

    day=$(printf "%02d" "$day")

    if [[ -n "$moment" ]]; then
        new_name="${year}-${month}-${day} ${moment}"
    else
        new_name="${year}-${month}-${day}"
    fi

    new_path="${sub_dir:h}/${new_name}"

    if [[ "$sub_dir" != "$new_path" ]]; then
        mv -- "$sub_dir" "$new_path"
    fi
done

echo "Reformatted folders in $BASE_DIR"
