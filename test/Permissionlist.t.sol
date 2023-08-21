pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/Permissionlist.sol";

contract PermissionlistTest is Test {
    Permissionlist public perms;

    address alice = address(10);
    address bob = address(11);

    function setUp() public {
        perms = new Permissionlist(address(this));

        // whitelist bob
        Permissionlist.Permission memory allowPerms = Permissionlist.Permission(true);
        perms.setPermission(bob, allowPerms);
    }

    function testSetAllowPerms() public {
        assertEq(perms.getPermission(alice).allowed, false);

        // allow alice
        Permissionlist.Permission memory newPerms = Permissionlist.Permission(true);
        perms.setPermission(alice, newPerms);

        assertEq(perms.getPermission(alice).allowed, true);
    }

    function testSetDisallowPerms() public {
        assertEq(perms.getPermission(bob).allowed, true);

        // disallow bob
        Permissionlist.Permission memory disallowPerms = Permissionlist.Permission(false);
        perms.setPermission(bob, disallowPerms);

        assertEq(perms.getPermission(bob).allowed, false);
    }

    function testUndoAllowPerms() public {
        assertEq(perms.getPermission(alice).allowed, false);

        // allow alice
        Permissionlist.Permission memory allowPerms = Permissionlist.Permission(true);
        perms.setPermission(alice, allowPerms);
        assertEq(perms.getPermission(alice).allowed, true);

        // now disallow alice
        Permissionlist.Permission memory disallowPerms = Permissionlist.Permission(false);
        perms.setPermission(alice, disallowPerms);
        assertEq(perms.getPermission(alice).allowed, false);
    }

    // TODO: Test upgrading struct preserves permissions
}
