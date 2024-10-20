Summary of changes:

- Added `Ownable2Step` to be able to specify a different admin to the contract
  - Note: This was done in a backwards compatible way by preserving the storage layout. If upgrading from a prior version of this contract, the `_existingAdmin` must be the one from the prior contract. The `admin` field will no longer be used in subsequent versions of the contract.