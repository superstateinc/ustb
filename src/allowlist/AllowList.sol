// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IAllowListV2} from "../interfaces/allowlist/IAllowListV2.sol";
import {Ownable2StepUpgradeable} from "openzeppelin/access/Ownable2StepUpgradeable.sol";

/**
 * @title AllowList
 * @notice A contract that provides allowlist functionalities with both entity-based and protocol address permissions
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
    mapping(EntityId => mapping(string fundSymbol => bool permission)) public fundPermissionsByEntityId;

    /// @notice A record of how many funds a protocol is allowed for
    mapping(address protocol => uint256 numberOfFunds) public protocolPermissionsForFunds;

    /// @notice Protocol address permissions, mutually exclusive with entityId permissions
    mapping(address protocol => mapping(string fundSymbol => bool permission)) public protocolPermissions;

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
        // EntityId is 0 for unset addresses
        if (EntityId.unwrap(addressEntityIds[addr]) == 0) {
            return protocolPermissions[addr][fundSymbol];
        }

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

    function _setProtocolAllowedForFundInternal(address addr, string calldata fundSymbol, bool isAllowed) internal {
        bool currentValue = protocolPermissions[addr][fundSymbol];

        if (currentValue == isAllowed) revert AlreadySet();

        uint256 codeSize;
        assembly {
            codeSize := extcodesize(addr)
        }

        if (codeSize == 0) revert CodeSizeZero();

        if (isAllowed) {
            protocolPermissionsForFunds[addr] += 1;
        } else {
            protocolPermissionsForFunds[addr] -= 1;
        }

        protocolPermissions[addr][fundSymbol] = isAllowed;
        emit ProtocolAddressPermissionSet(addr, fundSymbol, isAllowed);
    }

    /**
     * @notice Sets protocol permissions for an address
     * @param addr The address to set permissions for
     * @param fundSymbol The fund symbol to set permissions for
     * @param isAllowed The permission value to set
     */
    function setProtocolAddressPermission(address addr, string calldata fundSymbol, bool isAllowed) external {
        _checkOwner();
        if (EntityId.unwrap(addressEntityIds[addr]) != 0) revert AddressHasEntityId();

        _setProtocolAllowedForFundInternal(addr, fundSymbol, isAllowed);
    }

    /**
     * @notice Sets protocol permissions for multiple addresses
     * @param addresses The addresses to set permissions for
     * @param fundSymbol The fund symbol to set permissions for
     * @param isAllowed The permission value to set
     */
    function setProtocolAddressPermissions(address[] calldata addresses, string calldata fundSymbol, bool isAllowed)
        external
    {
        _checkOwner();

        for (uint256 i = 0; i < addresses.length; ++i) {
            if (EntityId.unwrap(addressEntityIds[addresses[i]]) != 0) revert AddressHasEntityId();
            _setProtocolAllowedForFundInternal(addresses[i], fundSymbol, isAllowed);
        }
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

        // Check if address has protocol permissions when trying to set a non-zero entityId
        if (EntityId.unwrap(entityId) != 0) {
            if (hasAnyProtocolPermissions(addr)) revert AddressHasProtocolPermissions();
        }

        // Must set entityId to zero before setting to a new value.
        // If prev id is nonzero, revert if entityId is not zero.
        if (EntityId.unwrap(prevId) != 0 && EntityId.unwrap(entityId) != 0) revert NonZeroEntityIdMustBeChangedToZero();

        addressEntityIds[addr] = entityId;
        emit EntityIdSet(addr, EntityId.unwrap(entityId));
    }

    /**
     * @notice Helper function to check if an address has any protocol permissions
     * @param addr The address to check
     * @return hasPermissions True if the address has any protocol permissions for any fund
     * @dev This is used to ensure an address doesn't have both entity and protocol permissions
     */
    function hasAnyProtocolPermissions(address addr) public view returns (bool hasPermissions) {
        hasPermissions = protocolPermissionsForFunds[addr] > 0;
    }

    function setEntityIdForAddress(EntityId entityId, address addr) external {
        _checkOwner();
        _setEntityAddressInternal(entityId, addr);
    }

    /**
     * @notice Sets the entity Id for a list of addresses. Setting to 0 removes the address from the allowList
     * @param entityId The entityId to associate with an address
     * @param addresses The addresses to associate with an entityId
     */
    function setEntityIdForMultipleAddresses(EntityId entityId, address[] calldata addresses) external {
        _checkOwner();

        for (uint256 i = 0; i < addresses.length; ++i) {
            _setEntityAddressInternal(entityId, addresses[i]);
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

        // Check for protocol permissions and set Entity for addresses
        for (uint256 i = 0; i < addresses.length; ++i) {
            _setEntityAddressInternal(entityId, addresses[i]);
        }

        // Set permissions for entity
        for (uint256 i = 0; i < fundPermissionsToUpdate.length; ++i) {
            _setEntityAllowedForFundInternal(entityId, fundPermissionsToUpdate[i], fundPermissions[i]);
        }
    }

    function renounceOwnership() public virtual override onlyOwner {
        revert RenounceOwnershipDisabled();
    }
}
