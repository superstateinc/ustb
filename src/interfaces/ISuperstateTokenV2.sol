// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {IERC7246} from "src/interfaces/IERC7246.sol";
import {AllowList} from "src/allowlist/AllowList.sol";
import {ISuperstateTokenV1} from "./ISuperstateTokenV1.sol";

interface ISuperstateTokenV2 is ISuperstateTokenV1 {
    /// @dev Thrown if an attempt to call `renounceOwnership` is made
    error RenounceOwnershipDisabled();

    /**
     * @notice Initialize version 2 of the contract.
     * @notice If creating an entirely new contract, the original `initialize` method still needs to be called.
     */
    function initializeV2() external;
}
