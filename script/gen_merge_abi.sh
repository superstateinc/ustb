#!/bin/bash

set -exo pipefail

PROXY_FILE="out/TransparentUpgradeableProxy.sol/ITransparentUpgradeableProxy.json"
FOO_FILE="out/ISuperstateTokenV1.sol/ISuperstateTokenV1.json"
FOO2_FILE="out/ISuperstateTokenV2.sol/ISuperstateTokenV2.json"
FOO3_FILE="out/Ownable2StepUpgradeable.sol/Ownable2StepUpgradeable.json"
FOO4_FILE="out/OwnableUpgradeable.sol/OwnableUpgradeable.json"

# only event abi
jq -s '.[0].abi + .[1].abi + .[2].abi + .[3].abi + .[4].abi + .[5].abi' out/USTBV2.sol/USTBV2.json $PROXY_FILE $FOO_FILE $FOO2_FILE $FOO3_FILE $FOO4_FILE > ustbAbi.json
jq -s '.[0].abi + .[1].abi + .[2].abi + .[3].abi + .[4].abi + .[5].abi' out/USCCV2.sol/USCCV2.json $PROXY_FILE $FOO_FILE $FOO2_FILE $FOO3_FILE $FOO4_FILE > usccAbi.json
#jq -s '.[0].abi + .[1].abi' out/USTBV2.sol/USTBV2.json $PROXY_FILE > ustbAbi.json
#jq -s '.[0].abi + .[1].abi' out/USCCV2.sol/USCCV2.json $PROXY_FILE > usccAbi.json
jq -s '.[0].abi + .[1].abi' out/AllowList.sol/AllowList.json $PROXY_FILE > allowlistAbi.json

echo "successfully generated ustbAbi.json, usccAbi.json and allowlistAbi.json"