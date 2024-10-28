#!/bin/bash

set -exo pipefail

PROXY_FILE="out/TransparentUpgradeableProxy.sol/ITransparentUpgradeableProxy.json"

forge build

forge inspect src/v2/USTBv2.sol:USTBv2 abi > ustb-impl.json
forge inspect src/v2/USCCv2.sol:USCCv2 abi > uscc-impl.json
forge inspect src/AllowList.sol:AllowList abi > allowlist-impl.json

# only event abi
jq -s '.[0] + .[1].abi' ustb-impl.json $PROXY_FILE > ustbAbi.json
jq -s '.[0] + .[1].abi' uscc-impl.json $PROXY_FILE > usccAbi.json
jq -s '.[0] + .[1].abi' allowlist-impl.json $PROXY_FILE > allowlistAbi.json

echo "successfully generated ustbAbi.json, usccAbi.json and allowlistAbi.json"
rm ustb-impl.json
rm uscc-impl.json
rm allowlist-impl.json
