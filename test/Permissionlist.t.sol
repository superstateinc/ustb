pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/Permissionlist.sol";

contract PermissionlistTest is Test {
    Permissionlist perms;

    function setUp() public {
        perms = new Permissionlist(address(this));
    }

    function testShouldSetPermsCorrectly() public {
        address alice = address(0);

        assertEq(perms.getPermission(alice).allowed, false);

        Permissionlist.Permission memory newPerms = Permissionlist.Permission(true);

        perms.setPermission(alice, newPerms);

        assertEq(perms.getPermission(alice).allowed, true);
    }
}
