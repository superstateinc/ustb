#!/bin/bash

set -exo pipefail

PROXY_FILE="out/TransparentUpgradeableProxy.sol/ITransparentUpgradeableProxy.json"
SUPERSTATE_TOKEN_FILE="out/SuperstateToken.sol/SuperstateToken.json"

forge build

# only event abi
jq -s '.[0].abi + .[1].abi' $PROXY_FILE $SUPERSTATE_TOKEN_FILE> ustbAbi.json
jq -s '.[0].abi + .[1].abi' $PROXY_FILE $SUPERSTATE_TOKEN_FILE > usccAbi.json
jq -s '.[0].abi + .[1].abi' out/AllowList.sol/AllowList.json $PROXY_FILE > allowlistAbi.json

echo "successfully generated ustbAbi.json, usccAbi.json and allowlistAbi.json"