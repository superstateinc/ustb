#!/bin/bash

set -exo pipefail

if [ -n "$CHAIN_ID" ]; then
  chain_id_args="--chain-id $CHAIN_ID"
else
  # default to Goerli
  chain_id="--chain-id 5"
fi

if [ -n "$DEPLOYER_PK" ]; then
  wallet_args="--private-key $DEPLOYER_PK"
else
  wallet_args="--unlocked"
fi

if [ -z "$ADMIN_ADDRESS" ]; then
  echo "ADMIN_ADDRESS is not set"
  exit 1
fi

if [ -z "NEW_ADMIN_ADDRESS" ]; then
  echo "NEW_ADMIN_ADDRESS is not set"
  exit 1
fi

if [ -z "ALLOWLIST_PROXY_ADDRESS" ]; then
  echo "ALLOWLIST_PROXY_ADDRESS is not set"
  exit 1
fi

if [ -z "PROXY_ADMIN_ADDRESS" ]; then
  echo "PROXY_ADMIN_ADDRESS is not set"
  exit 1
fi

if [ -z "PROXY_TOKEN_ADDRESS" ]; then
  echo "PROXY_TOKEN_ADDRESS is not set"
  exit 1
fi

if [ -n "$RPC_URL" ]; then
  rpc_args="--rpc-url $RPC_URL"
else
  rpc_args=""
fi

if [ -n "$ETHERSCAN_API_KEY" ]; then
  etherscan_args="--verify --etherscan-api-key $ETHERSCAN_API_KEY"
else
  etherscan_args=""
fi

forge script \
    $chain_id_args \
    $rpc_args \
    $wallet_args \
    $etherscan_args \
    --broadcast \
    $@ \
    script/v2/DeployAndUpgradeUstbScriptV2.s.sol:DeployAndUpgradeUstbScriptV2