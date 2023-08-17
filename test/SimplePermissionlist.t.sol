pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/SimplePermissionlist.sol";

contract SimplePermissionlistTest is Test {
    SimplePermissionlist perms;

    function setUp() public {
        perms = new SimplePermissionlist(address(this));
    }

    function testShouldSetPermsCorrectly() public {
        address alice = address(0);

        assertEq(perms.getPermission(alice).allowed, false);

        SimplePermissionlist.Permission memory newPerms = SimplePermissionlist.Permission(true, false);

        perms.setPermission(alice, newPerms);

        assertEq(perms.getPermission(alice).allowed, true);
    }
}
