# SUPTB Token Contract

Repository for the SUPTB Token contract. Contains contracts for an upgradeable PermissionList (`src/PermissionList.sol`) and a upgradeable ERC7246 token that interacts with the PermissionList to check if transfers and encumbers are allowed (`src/SUPTB.sol`).

## Running tests

```sh
forge test -vvv
```

To run coverage

```sh
forge coverage
```

## Deployment

* Deploy contracts `script/deploy.sh`. Be mindful, script sets the proxy admin to be the same as the PermissionList and SUPTB token. 
In prod this will presumably be our fireblocks address

* Create clean deployment file in `contract_deployment` out of foundry broadcast file `python script/gen_deploy.py broadcast/DeployScript.s.sol/11155111/run-latest.json sepolia.json`
