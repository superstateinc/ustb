// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// THIS IS A TEST CONTRACT DO NOT USE IN PRODUCTION

/**
 * @title MockAllowList
 * @notice A contract that provides allowlist functionalities
 * @author Compound
 */
contract MockAllowList {
    /// @notice The major version of this contract
    string public constant VERSION = "2";

    /// @dev Address of the administrator with permissions to update the allowlist
    address public immutable permissionAdmin;

    /// @dev Mapping of addresses to their permissions
    struct Permission {
        bool isAllowed;
        bool state1;
        bool state2;
        bool state3;
        bool state4;
        bool state5;
        bool state6;
        bool state7;
    }

    /// @notice A record of permissions for each entityId determining if they are allowed. One indexed, since 0 is the default value for all addresses
    mapping(uint256 => Permission) public permissions;

    /// @notice A record of entityIds associated with each address. Setting to 0 removes the address from the allowList.
    mapping(address => uint256) public addressEntityIds;

    /// @notice An event emitted when an entityId's permission status is changed
    event PermissionSet(uint256 indexed entityId, Permission permission);

    /// @notice An event emitted when an address is associated with an entityId
    event EntityIdSet(address indexed addr, uint256 indexed entityId);

    /// @dev Thrown when a request is not sent by the authorized admin
    error Unauthorized();

    /// @dev Thrown when the input for a function is invalid
    error BadData();

    /**
     * @notice Construct a new AllowList instance
     * @param _permissionAdmin Address of the permission administrator
     */
    constructor(address _permissionAdmin) {
        permissionAdmin = _permissionAdmin;
    }

    /**
     * @notice Fetches the permissions for a given address
     * @param addr The entityId whose permissions are to be fetched
     * @return Permission The permissions of the address
     */
    function getPermission(address addr) external view returns (Permission memory) {
        uint256 entityId = addressEntityIds[addr];
        return permissions[entityId];
    }

    /**
     * @notice Sets permissions for a given entityId
     * @param entityId The entityId to be updated
     * @param permission The permission status to set
     */
    function setPermission(uint256 entityId, Permission calldata permission) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();

        permissions[entityId] = permission;

        emit PermissionSet(entityId, permission);
    }

    /**
     * @notice Sets isAllowed permissions for a given entityId
     * @param entityId The entityId to be updated
     * @param value The isAllowed status to set
     */
    function setIsAllowed(uint256 entityId, bool value) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();

        Permission storage perms = permissions[entityId];
        perms.isAllowed = value;

        emit PermissionSet(entityId, perms);
    }

    /**
     * @notice Sets the nth permission for a given entityId
     * @param entityId The entityId to be updated
     * @param index The index of the permission to update
     * @param value The status to set
     * @dev Permissions are 0 indexed, meaning the first permission (isAllowed) has an index of 0
     */
    function setNthPermission(uint256 entityId, uint256 index, bool value) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();

        Permission memory perms = permissions[entityId];
        perms = setPermissionAtIndex(perms, index, value);
        permissions[entityId] = perms;

        emit PermissionSet(entityId, perms);
    }

    /**
     * @dev Sets the nth permission for a Permission and returns the updated struct
     * @param perms The Permission to be updated
     * @param index The index of the permission to update
     * @param value The status to set
     */
    function setPermissionAtIndex(Permission memory perms, uint256 index, bool value)
        internal
        pure
        returns (Permission memory)
    {
        if (index == 0) {
            perms.isAllowed = value;
        } else if (index == 1) {
            perms.state1 = value;
        } else if (index == 2) {
            perms.state2 = value;
        } else if (index == 3) {
            perms.state3 = value;
        } else if (index == 4) {
            perms.state4 = value;
        } else if (index == 5) {
            perms.state5 = value;
        } else {
            revert BadData();
        }

        return perms;
    }
}
