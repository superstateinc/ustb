#!/bin/bash

if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo "ETHERSCAN_API_KEY is not set"
    exit 1
fi

if [ -z "$GUID" ]; then
    echo "GUID is not set"
    exit 1
fi

URL="https://api.etherscan.io/api"

response=$(curl -s -G \
    --data-urlencode "apikey=$ETHERSCAN_API_KEY" \
    --data-urlencode "guid=$GUID" \
    --data-urlencode "module=contract" \
    --data-urlencode "action=checkverifystatus" \
    "$URL")

status=$(echo $response | jq -r '.status')
message=$(echo $response | jq -r '.message')
result=$(echo $response | jq -r '.result')

echo "status : $status"   # 0=Error, 1=Pass
echo "message : $message" # OK, NOTOK
echo "result : $result"   # result explanation

if [ "$status" == "0" ]; then
    echo "An error occurred: $result"
    exit 1
fi

echo $response | jq
