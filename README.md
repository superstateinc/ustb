# SUPTB Token Contract

Repository for the SUPTB Token contract. Contains contracts for an upgradeable Permissionlist (`src/Permissionlist.sol`) and a upgradeable ERC7246 token that interacts with the Permissionlist to check if transfers and encumbers are allowed (`src/SUPTB.sol`).

## Running tests

```sh
forge test -vvv
```

To run coverage

```sh
forge coverage
```
