// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IAllowList} from "./IAllowList.sol";

interface IAllowListV2 is IAllowList {
    type EntityId is uint256;

    event FundPermissionSet(EntityId indexed entityId, string fundSymbol, bool permission);
    event ProtocolAddressPermissionSet(address indexed addr, string fundSymbol, bool isAllowed);

    /// @dev Thrown when trying to set entityId for an address that has protocol permissions
    error AddressHasProtocolPermissions();
    /// @dev Thrown when trying to set protocol permissions for an address that has an entityId
    error AddressHasEntityId();
    /// @dev Thrown when trying to set protocol permissions but the code size is 0
    error CodeSizeZero();
    /// @dev Thrown when a method is no longer supported
    error Deprecated();

    function isAddressAllowedForFund(address addr, string calldata fundSymbol) external view returns (bool);

    function isEntityAllowedForFund(EntityId entityId, string calldata fundSymbol) external view returns (bool);

    function setEntityAllowedForFund(EntityId entityId, string calldata fundSymbol, bool isAllowed) external;

    /**
     * @notice Sets protocol permissions for an address
     * @param addr The address to set permissions for
     * @param fundSymbol The fund symbol to set permissions for
     * @param isAllowed The permission value to set
     */
    function setProtocolAddressPermission(address addr, string calldata fundSymbol, bool isAllowed) external;

    /**
     * @notice Sets protocol permissions for multiple addresses
     * @param addresses The addresses to set permissions for
     * @param fundSymbol The fund symbol to set permissions for
     * @param isAllowed The permission value to set
     */
    function setProtocolAddressPermissions(address[] calldata addresses, string calldata fundSymbol, bool isAllowed)
        external;

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

    function hasAnyProtocolPermissions(address addr) external view returns (bool hasPermissions);

    function protocolPermissionsForFunds(address protocol) external view returns (uint256);

    function protocolPermissions(address, string calldata) external view returns (bool);

    function initialize() external;
}
