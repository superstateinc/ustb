// SPDX-License-Identifier: undefined
pragma solidity ^0.8.20;

contract SimplePermissionlist {
    address public immutable permissionAdmin;

    struct Permission {
        bool allowed;
        bool forbidden;
    }

    mapping(address => Permission) public permissions;

    event PermissionSet(address indexed addr, Permission permission);

    constructor(address _permissionAdmin) {
        permissionAdmin = _permissionAdmin;
    }

    function getPermission(address receiver) public view returns (Permission memory) {
        return permissions[receiver];
    }

    function setPermission(address addr, Permission memory permission) external {
        if (msg.sender != permissionAdmin) revert("Not admin");

        permissions[addr] = permission;
        emit PermissionSet(addr, permission);
    }
}
