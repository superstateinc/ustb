// TODO: Decide contract license
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

/**
 * @title PermissionList
 * @notice A contract that provides allowlist functionalities
 * @author Compound
 */
contract PermissionList {
    /// @notice The major version of this contract
    string public constant VERSION = "1";

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
    }

    /// @notice A record of permissions for each address determining if they are allowed
    mapping(address => Permission) public permissions;

    /// @notice An event emitted when an address's permission status is changed
    event PermissionSet(address indexed addr, Permission permission);

    /// @dev Thrown when a request is not sent by the authorized admin
    error Unauthorized();

    /// @dev Thrown when the input for a function is invalid
    error BadData();

    /**
     * @notice Construct a new PermissionList instance
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
        if (msg.sender != permissionAdmin) revert Unauthorized();

        permissions[addr] = permission;

        emit PermissionSet(addr, permission);
    }

    /**
     * @notice Sets permissions for a list of addresses
     * @param users The addresses to be updated
     * @param perms The permission statuses to set
     */
    function setMultiplePermissions(address[] calldata users, Permission[] calldata perms) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();
        if (users.length != perms.length) revert BadData();

        for (uint i = 0; i < users.length; ) {
            permissions[users[i]] = perms[i];
            emit PermissionSet(users[i], perms[i]);

            unchecked { i++; }
        }
    }
}
