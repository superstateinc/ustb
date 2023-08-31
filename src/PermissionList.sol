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

    /**
     * @notice Sets isAllowed permissions for a given address
     * @param addr The address to be updated
     * @param value The isAllowed status to set
     */
    function setIsAllowed(address addr, bool value) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();

        Permission memory perms = permissions[addr];
        perms.isAllowed = value;
        permissions[addr] = perms;

        emit PermissionSet(addr, perms);
    }

    /**
     * @notice Sets isAllowed permissions for a list of addresses
     * @param users The addresses to be updated
     * @param values The isAllowed statuses to set
     */
    function setMultipleIsAllowed(address[] calldata users, bool[] calldata values) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();
        if (users.length != values.length) revert BadData();

        for (uint i = 0; i < users.length; ) {
            address user = users[i];
            Permission memory perms = permissions[user];
            perms.isAllowed = values[i];
            permissions[user] = perms;

            emit PermissionSet(user, perms);

            unchecked { i++; }
        }
    }

    /**
     * @notice Sets the nth permission for a given address
     * @param addr The address to be updated
     * @param index The index of the permission to update
     * @param value The status to set
     * @dev Permissions are 0 indexed, meaning the first permission (isAllowed) has an index of 0
     */
    function setNthPermission(address addr, uint index, bool value) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();

        Permission memory perms = permissions[addr];
        perms = setPermissionAtIndex(perms, index, value);
        permissions[addr] = perms;

        emit PermissionSet(addr, perms);
    }

    /**
     * @notice Sets the nth permissions for a list of addresses
     * @param users The addresses to be updated
     * @param indices The indices of the permissions to update
     * @param values The statuses to set
     */
    function setMultipleNthPermissions(address[] calldata users, uint[] calldata indices, bool[] calldata values) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();
        if (users.length != indices.length || users.length != values.length) revert BadData();

        for (uint i = 0; i < users.length; ) {
            address user = users[i];
            Permission memory perms = permissions[user];
            perms = setPermissionAtIndex(perms, indices[i], values[i]);
            permissions[user] = perms;

            emit PermissionSet(user, perms);

            unchecked { i++; }
        }
    }

    /**
     * @dev Sets the nth permission for a Permission and returns the updated struct
     * @param perms The Permission to be updated
     * @param index The index of the permission to update
     * @param value The status to set
     */
    function setPermissionAtIndex(Permission memory perms, uint index, bool value) internal returns (Permission memory) {
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
