// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IAllowListV2} from "../interfaces/allowlist/IAllowListV2.sol";
import {Ownable2StepUpgradeable} from "openzeppelin/access/Ownable2StepUpgradeable.sol";

/**
 * @title AllowList
 * @notice A contract that provides allowlist functionalities
 * @author Chris Ridmann (Superstate)
 */
contract AllowList is IAllowListV2, Ownable2StepUpgradeable {
    /**
     * @dev This empty reserved space is put in place to allow future versions to inherit from new contracts
     * without impacting the fields within `SuperstateToken`.
     */
    uint256[500] private __inheritanceGap;

    /// @notice The major version of this contract
    string public constant VERSION = "2";

    /// @notice A record of entityIds associated with each address. Setting to 0 removes the address from the allowList.
    mapping(address => EntityId) public addressEntityIds;

    /// @notice A record of permissions for each entityId determining if they are allowed.
    mapping(EntityId => mapping(string => bool)) fundPermissionsByEntityId;

    /// Future allow lists could be added here

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new fields without impacting
     * any contracts that inherit `SuperstateToken`
     */
    uint256[100] private __additionalFieldsGap;

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     */
    function initialize() public initializer {
        __Ownable2Step_init();
    }

    function isAddressAllowedForFund(address addr, string calldata fundSymbol) external view returns (bool) {
        EntityId entityId = addressEntityIds[addr];
        return isEntityAllowedForFund(entityId, fundSymbol);
    }

    function isEntityAllowedForFund(EntityId entityId, string calldata fundSymbol) public view returns (bool) {
        return fundPermissionsByEntityId[entityId][fundSymbol];
    }

    function setEntityAllowedForFund(EntityId entityId, string calldata fundSymbol, bool isAllowed) external {
        _checkOwner();
        _setEntityAllowedForFundInternal(entityId, fundSymbol, isAllowed);
    }

    function _setEntityAllowedForFundInternal(EntityId entityId, string calldata fundSymbol, bool isAllowed) internal {
        fundPermissionsByEntityId[entityId][fundSymbol] = isAllowed;
        emit FundPermissionSet(entityId, fundSymbol, isAllowed);
    }

    /**
     * @notice Sets the entityId for a given address. Setting to 0 removes the address from the allowList
     * @param entityId The entityId whose permissions are to be set
     * @param addr The address to set entity for
     * @dev the caller must check if msg.sender is authenticated
     */
    function _setEntityAddressInternal(EntityId entityId, address addr) internal {
        EntityId prevId = addressEntityIds[addr];

        if (EntityId.unwrap(prevId) == EntityId.unwrap(entityId)) revert AlreadySet();

        // Must set entityId to zero before setting to a new value.
        // If prev id is nonzero, revert if entityId is not zero.
        if (EntityId.unwrap(prevId) != 0 && EntityId.unwrap(entityId) != 0) revert NonZeroEntityIdMustBeChangedToZero();

        addressEntityIds[addr] = entityId;
        emit EntityIdSet(addr, EntityId.unwrap(entityId));
    }

    /**
     * @notice Sets the entityId for a given address. Setting to 0 removes the address from the allowList
     * @param entityId The entityId to associate with an address
     * @param addr The address to associate with an entityId
     */
    function setEntityIdForAddress(uint256 entityId, address addr) external {
        _checkOwner();
        _setEntityAddressInternal(EntityId.wrap(entityId), addr);
    }

    /**
     * @notice Sets the entity Id for a list of addresses. Setting to 0 removes the address from the allowList
     * @param entityId The entityId to associate with an address
     * @param addresses The addresses to associate with an entityId
     */
    function setEntityIdForMultipleAddresses(uint256 entityId, address[] calldata addresses) external {
        _checkOwner();

        for (uint256 i = 0; i < addresses.length; ++i) {
            _setEntityAddressInternal(EntityId.wrap(entityId), addresses[i]);
        }
    }

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
    ) external {
        _checkOwner();

        // Ensure fundPermissionsToUpdate.length == fundPermissions.length
        if (fundPermissionsToUpdate.length != fundPermissions.length) {
            revert BadData();
        }

        // Set Entity for addresses
        for (uint256 i = 0; i < addresses.length; ++i) {
            _setEntityAddressInternal(entityId, addresses[i]);
        }

        // Set permissions for entity
        for (uint256 i = 0; i < fundPermissionsToUpdate.length; ++i) {
            _setEntityAllowedForFundInternal(entityId, fundPermissionsToUpdate[i], fundPermissions[i]);
        }
    }

    /// DEPRECATED FUNCTIONS FROM V1

    /**
     * @notice Fetches the permissions for a given address.
     * @dev Deprecated in v2
     */
    function getPermission(address) external pure returns (Permission memory) {
        revert Deprecated();
    }

    /**
     * @notice Sets permissions for a given entityId.
     * @dev Deprecated in v2
     */
    function setPermission(uint256, Permission calldata) external pure {
        revert Deprecated();
    }

    /**
     * @notice Sets entity for an array of addresses and sets permissions for an entity.
     * @dev Deprecated in v2
     */
    function setEntityPermissionAndAddresses(uint256, address[] calldata, Permission calldata) external pure {
        revert Deprecated();
    }

    /**
     * @notice Sets isAllowed permissions for a given entityId
     * @dev Deprecated in v2
     */
    function setIsAllowed(uint256, bool) external pure {
        revert Deprecated();
    }

    /**
     * @notice Sets the nth permission for a given entityId.
     * @dev Deprecated in v2
     */
    function setNthPermission(uint256, uint256, bool) external pure {
        revert Deprecated();
    }

    /**
     * @notice Sets the nth permission for a Permission and returns the updated struct
     * @dev Deprecated in v2
     */
    function _setPermissionAtIndex(Permission memory, uint256, bool) internal pure returns (Permission memory) {
        revert Deprecated();
    }
}
