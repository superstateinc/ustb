// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

/**
 * @title Permissionlist
 * @notice A contract that provides allowlist functionalities
 * @author Compound
 * TODO: Make upgradeable
 */
contract Permissionlist {
    /// @dev Address of the administrator with permissions to update the allowlist
    address public immutable permissionAdmin;

    /// @dev Mapping of addresses to their permissions
    struct Permission {
        bool allowed;
    }

    /// @notice A record of permissions for each address determining if they are allowed
    mapping(address => Permission) public permissions;

    /// @notice An event emitted when an address's permission status is changed
    event PermissionSet(address indexed addr, Permission permission);

    /**
     * @notice Construct a new Permissionlist instance
     * @param _permissionAdmin Address of the permission administrator
     */
    constructor(address _permissionAdmin) {
        permissionAdmin = _permissionAdmin;
    }

    /**
     * @notice Fetches the permissions for a given address
     * @param receiver The address whose permissions are to be fetched
     * @return Permission The permissions of the address
     */
    function getPermission(address receiver) public view returns (Permission memory) {
        return permissions[receiver];
    }

    /**
     * @notice Sets permissions for a given address
     * @param addr The address to be updated
     * @param permission The permission status to set
     */
    function setPermission(address addr, Permission memory permission) external {
        require(msg.sender == permissionAdmin, "Not authorized to set permissions");
        permissions[addr] = permission;

        emit PermissionSet(addr, permission);
    }
}
