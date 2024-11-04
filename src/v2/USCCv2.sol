// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SuperstateTokenV2} from "src/v2/SuperstateTokenV2.sol";
import {AllowList} from "src/allowlist/AllowList.sol";

/**
 * @title USCC
 * @notice A Pausable ERC7246 token contract that interacts with the AllowList contract to check if transfers are allowed
 * @author Superstate
 */
contract USCCv2 is SuperstateTokenV2 {
    /**
     * @notice Construct a new ERC20 token instance with the given admin and AllowList
     * @param _admin The address designated as the admin with special privileges
     * @param _allowList Address of the AllowList contract to use for permission checking
     * @dev Disables initialization on the implementation contract
     */
    constructor(address _admin, AllowList _allowList) SuperstateTokenV2(_admin, _allowList) {}

    /**
     * @notice Check permissions of an address for transferring / encumbering
     * @param addr Address to check permissions for
     * @return bool True if the address has sufficient permission, false otherwise
     */
    function hasSufficientPermissions(address addr) public view override returns (bool) {
        AllowList.Permission memory permissions = allowList.getPermission(addr);
        return permissions.state1;
    }
}
