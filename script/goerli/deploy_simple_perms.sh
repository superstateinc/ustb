#!/bin/bash

source ../../.env && fireblocks-json-rpc --http \
--apiKey $FIREBLOCKS_API_KEY \
--privateKey $FIREBLOCKS_API_PRIVATE_KEY_PATH \
--apiBaseUrl $FIREBLOCKS_API_BASE_URL \
--chainId $FIREBLOCKS_CHAIN_ID -- \
forge script ./SimpleContractsDeployScript.s.sol:SimpleContractsDeployScript \
# Sender is a Fireblocks EOA Vault
--sender 0x9825df3dc587BCc86b1365DA2E4EF07B0Cabfb9B --broadcast --unlocked --rpc-url {}



