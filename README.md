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
