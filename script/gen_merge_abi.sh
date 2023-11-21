#!/bin/bash

set -exo pipefail

PROXY_FILE="out/TransparentUpgradeableProxy.sol/ITransparentUpgradeableProxy.json"

# only event abi
jq -s '.[0].abi + .[1].abi | map(select(.type == "event"))' out/SUPTB.sol/SUPTB.json $PROXY_FILE > suptbAbi.json
jq -s '.[0].abi + .[1].abi | map(select(.type == "event"))' out/AllowList.sol/AllowList.json $PROXY_FILE > allowlistAbi.json

echo "sucessfully generated suptbAbi.json and allowlistAbi.json"