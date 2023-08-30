#!/bin/bash

source ../../.env && fireblocks-json-rpc --http \
--apiKey $FIREBLOCKS_API_KEY \
--privateKey $FIREBLOCKS_API_PRIVATE_KEY_PATH \
--apiBaseUrl $FIREBLOCKS_API_BASE_URL \
--chainId $FIREBLOCKS_CHAIN_ID -- \
forge script ./DeployScript.s.sol:DeployScript \
--sender $SENDER --broadcast --unlocked --rpc-url {}



