pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/SimplePermissionlist.sol";

contract SimplePermissionlistTest is Test {
    SimplePermissionlist perms;

    function setUp() public {
        perms = new SimplePermissionlist();
    }

    function testShouldSetPermsCorrectly() public {
        address alice = address(0);

        assertEq(perms.getPermissions(alice), false);

        perms.setPermissions(alice, true);

        assertEq(perms.getPermissions(alice), true);
    }
}
