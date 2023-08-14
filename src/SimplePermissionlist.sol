// SPDX-License-Identifier: undefined
pragma solidity ^0.8.20;

contract SimplePermissionlist {
    mapping(address => bool) public permissions;

    event PermissionSet(address indexed addr, bool value);

    constructor() {}

    function getPermissions(address addr) public view returns (bool) {
        return permissions[addr];
    }

    function setPermissions(address addr, bool value) external {
        permissions[addr] = value;
        emit PermissionSet(addr, value);
    }
}
