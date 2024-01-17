# SUPTB Token Contract

Repository for the SUPTB Token contract. Contains contracts for an upgradeable AllowList (`src/AllowList.sol`) and a upgradeable ERC7246 token that interacts with the AllowList to check if transfers and encumbers are allowed (`src/SUPTB.sol`).

## Running tests

```sh
forge test -vvv
```

To run coverage

```sh
forge coverage
```

## Deployment Guide

* ./deploy.sh or ./deploy_ustb_upgrade.sh to deploy new contracts
    * If verify did not work, use verify scripts
* if redeploying proxy or doing a fresh deploy
    * register the proxy/impl in etherscan https://{chain_name}.etherscan.io/proxyContractChecker, and create a migration in webserver to add the contract address there too, pulumi secrets
    * update fireblocks whitelist, make sure admin address is funded
* If abi changed, run `gen_merge_abi.sh` and copy into `webserver` repo. dedup "admin"
* Verify the deployed contract is correct using https://github.com/lidofinance/diffyscan
* Upgrade contract in fireblocks using proxy admin if applicable
* Edit `contract_deployment` file or create new one with `gen_deploy.py`, leave a note in the below changelog
* Create a PR in webserver for the new deployment file

### Changelog

| Deploy File Name | Commit Hash | Notes |
|------------|-------------|--------|
| sepolia.json    | d7e42b9     | redeploy sepolia
| goerli.json     | 628cd5c     | redeploy goerli because of circle issue
| mainnet.json    | dbd126e     | add bulk mint
| goerli.json     | fefd6d4     | add bulk mint
| goerli.json     | 8c88411     | deployed new ustb impl and upgraded
| mainnet.json    | 8c88411     | deployed mainnet
| goerli.json     | bfe063d     | allowlist rename, burn changes, not including USTB rename | 
| goerli_old.json | 96de27d     | audit feedback |
| sepolia.json    | 83e2229     | misc nits, revert self encumber |
