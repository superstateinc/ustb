#!/bin/bash

set -exo pipefail

PROXY_FILE="out/TransparentUpgradeableProxy.sol/ITransparentUpgradeableProxy.json"

# only event abi
jq -s '.[0].abi + .[1].abi' out/USTB.sol/USTB.json $PROXY_FILE > ustbAbi.json
jq -s '.[0].abi + .[1].abi' out/AllowList.sol/AllowList.json $PROXY_FILE > allowlistAbi.json

echo "sucessfully generated ustbAbi.json and allowlistAbi.json"