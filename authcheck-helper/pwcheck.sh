#!/bin/bash

user="$1"

# Prompt silently
read -s -p "Password for $user: " pw
echo  # newline after prompt

# Pass password via stdin
if echo "$pw" | authcheck "$user"; then
    echo "✅ Authentication succeeded"
else
    echo "❌ Authentication failed"
fi

# Clear variable (reduce chance of lingering in memory)
unset pw