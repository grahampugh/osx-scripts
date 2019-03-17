#!/bin/bash

# variables
credentials="betaadmin:bhztfv@bhztfv@"

# input for filepath
filepath=$1
filename=$(basename "$filepath")
obj_id=$2

# if no object ID is provided, make it -1
if [[ -z $obj_id ]]; then
    obj_id="-1"
fi

# base64 encode
enc_creds=$(printf "$credentials" | iconv -t ISO-8859-1 | base64 -i -)

/usr/bin/curl --header "authorization: Basic $enc_creds" -X POST "https://ethzurichgrahamxpah5.jamfcloud.com/dbfileupload" -H 'DESTINATION: 0' -H "OBJECT_ID: $obj_id" -H 'FILE_TYPE: 0' -H "FILE_NAME: $filename" -T "$filepath" | xmllint --format -
