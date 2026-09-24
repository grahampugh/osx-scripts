#!/usr/bin/env bash
# extract-apple-serials.sh
# by Graham Pugh.
#
# Extract valid Apple serial numbers from an arbitrary block of text.
#
# A serial is treated as valid if it is a 10- or 12-character alphanumeric
# token, not bordered by other alphanumeric characters, containing at least
# one letter AND one digit (this rules out plain words and plain numbers).
# Output is uppercased, deduplicated, and printed one serial per line in the
# order first seen.
#
# Usage:
#   extract-apple-serials.sh "some text with C02ABC123DEF in it"   # from args
#   extract-apple-serials.sh -f devices.csv                        # from a file
#   pbpaste | extract-apple-serials.sh                             # from stdin
#   extract-apple-serials.sh                                       # interactive paste
#
# With no arguments and an interactive terminal, paste your text then press
# Ctrl-D on a new line to finish.

set -euo pipefail

usage() {
    /bin/cat <<'EOF'
Usage: extract-apple-serials.sh [TEXT ...]
       extract-apple-serials.sh -f FILE
       command | extract-apple-serials.sh

Extract valid Apple serial numbers from pasted/piped text.

Options:
  -f FILE   Read the text from FILE instead of arguments/stdin.
  -h        Show this help.

With no TEXT and no -f, reads from stdin (pipe, or paste + Ctrl-D).
EOF
}

input_file=""
while getopts ":f:h" opt; do
    case "${opt}" in
        f) input_file="${OPTARG}" ;;
        h) usage; exit 0 ;;
        \?) echo "ERROR: unknown option -${OPTARG}" >&2; usage >&2; exit 2 ;;
        :) echo "ERROR: option -${OPTARG} requires an argument" >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))

# Gather the raw text from the first available source.
if [[ -n "${input_file}" ]]; then
    if [[ ! -f "${input_file}" ]]; then
        echo "ERROR: file not found: ${input_file}" >&2
        exit 1
    fi
    raw=$(/bin/cat "${input_file}")
elif [[ $# -gt 0 ]]; then
    raw="$*"
else
    # Read everything from stdin (pipe, redirect, or interactive paste + Ctrl-D).
    if [[ -t 0 ]]; then
        echo "Paste text containing serial numbers, then press Ctrl-D to finish:" >&2
    fi
    raw=$(/bin/cat)
fi

/usr/bin/python3 - "${raw}" <<'PYEOF'
import re, sys

text = sys.argv[1]
# 10- or 12-char alphanumeric tokens, not bordered by other alphanumerics.
pattern = re.compile(r'(?<![A-Z0-9])([A-Z0-9]{10}|[A-Z0-9]{12})(?![A-Z0-9])')
seen = set()
for match in pattern.findall(text.upper()):
    # Require at least one letter and one digit to avoid false positives.
    if any(c.isalpha() for c in match) and any(c.isdigit() for c in match):
        if match not in seen:
            seen.add(match)
            print(match)
PYEOF
