// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

/**
 * @title PermissionlistV2
 * @notice A contract that provides allowlist and other permission functionalities
 * @author Compound
 */
contract PermissionlistV2 {
    /// @notice The major version of this contract
    string public constant VERSION = "2";

    /// @dev Address of the administrator with permissions to update the allowlist
    address public immutable permissionAdmin;

    /// @dev Mapping of addresses to their permissions
    struct Permission {
        bool allowed;
        bool isKyc;
        bool isAccredited;
    }

    /// @notice A record of permissions for each address determining if they are allowed
    mapping(address => Permission) public permissions;

    /// @notice An event emitted when an address's permission status is changed
    event PermissionSet(address indexed addr, Permission permission);

    /**
     * @dev Thrown when a request is not sent by the authorized admin
     */
    error Unauthorized();

    /**
     * @notice Construct a new Permissionlist instance
     * @param _permissionAdmin Address of the permission administrator
     */
    constructor(address _permissionAdmin) {
        permissionAdmin = _permissionAdmin;
    }

    /**
     * @notice Fetches the permissions for a given address
     * @param addr The address whose permissions are to be fetched
     * @return Permission The permissions of the address
     */
    function getPermission(address addr) external view returns (Permission memory) {
        return permissions[addr];
    }

    /**
     * @notice Sets permissions for a given address
     * @param addr The address to be updated
     * @param permission The permission status to set
     */
    function setPermission(address addr, Permission memory permission) external {
        if (msg.sender != permissionAdmin) {
            revert Unauthorized();
        }

        permissions[addr] = permission;

        emit PermissionSet(addr, permission);
    }
}
