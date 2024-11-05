// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IAllowList} from "./IAllowList.sol";

interface IAllowListV2 is IAllowList {
    type EntityId is uint256;

    event FundPermissionSet(EntityId indexed entityId, string fundSymbol, bool permission);

    /// @dev Thrown when a method is no longer supported
    error Deprecated();

    function isAddressAllowedForFund(address addr, string calldata fundSymbol) external view returns (bool);

    function isEntityAllowedForFund(EntityId entityId, string calldata fundSymbol) external view returns (bool);

    function setEntityAllowedForFund(EntityId entityId, string calldata fundSymbol, bool isAllowed) external;

    /**
     * @notice Sets entity for an array of addresses and sets permissions for an entity
     * @param entityId The entityId to be updated
     * @param addresses The addresses to associate with an entityId
     * @param fundPermissionsToUpdate The funds to update permissions for
     * @param fundPermissions The permissions for each fund
     */
    function setEntityPermissionsAndAddresses(
        EntityId entityId,
        address[] calldata addresses,
        string[] calldata fundPermissionsToUpdate,
        bool[] calldata fundPermissions
    ) external;
}
