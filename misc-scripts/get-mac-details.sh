#!/usr/bin/env bash
# get-mac-details.sh
# Print the Mac's marketing name using TelemetryDeck's macs.json.
set -euo pipefail

RAW_URL="https://github.com/TelemetryDeck/AppleModelNames/raw/refs/heads/main/dataset/macs.json"
TMP_FILE="/tmp/macs.json"
SERIAL=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Serial Number/ {print $2; exit}')
DEVICE_ID=$(/usr/sbin/ioreg -c IOPlatformExpertDevice -d 2 | grep target-sub-type | awk -F'[<>]' '{print $2}' | tr -d '"')

# Detect model identifier and family name
MODEL_ID="$(sysctl -n hw.model 2>/dev/null || true)"
if [ -z "$MODEL_ID" ]; then
    MODEL_ID="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Identifier/ {print $2; exit}')"
fi
MODEL_NAME="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ {print $2; exit}')"

if [ -z "${MODEL_ID:-}" ]; then
  echo "Could not determine model identifier from the system."
  exit 1
fi

# Try to download fresh mapping (quick timeouts)
if curl --connect-timeout 5 --max-time 10 -sfL "$RAW_URL" -o "$TMP_FILE"; then
    # Validate JSON
    jq -e . "$TMP_FILE" >/dev/null 2>&1
else
    echo "Couldn't get data"
    exit 1
fi

# Lookup model identifier in JSON and print marketing name
MARKETING_NAME="$(jq -r --arg MODEL_ID "$MODEL_ID" \
    '.[$MODEL_ID] | .readableName' "$TMP_FILE")"
PROCESSOR_TYPE="$(jq -r --arg MODEL_ID "$MODEL_ID" \
    '.[$MODEL_ID] | .processorType' "$TMP_FILE")"
FIRST_RELEASE="$(jq -r --arg MODEL_ID "$MODEL_ID" \
    '.[$MODEL_ID] | .systemFirstRelease' "$TMP_FILE")"
LAST_RELEASE="$(jq -r --arg MODEL_ID "$MODEL_ID" \
    '.[$MODEL_ID] | .systemLastRelease' "$TMP_FILE")"
if [[ $LAST_RELEASE == "null" ]]; then
    LAST_RELEASE="N/A"
fi
echo "Serial: $SERIAL
Model Identifier: $MODEL_ID
Marketing Name: $MARKETING_NAME
Device ID: $DEVICE_ID
Model Name: $MODEL_NAME
Processor Type: $PROCESSOR_TYPE
First Release: $FIRST_RELEASE
Last Release: $LAST_RELEASE"
