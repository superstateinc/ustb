pragma solidity ^0.8.20;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import "src/Permissionlist.sol";
import "test/PermissionlistV2.sol";

contract PermissionlistTest is Test {
    TransparentUpgradeableProxy proxy;
    ProxyAdmin proxyAdmin;

    Permissionlist public perms;

    // Storage slot with the admin of the contract.
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address alice = address(10);
    address bob = address(11);

    function setUp() public {
        perms = new Permissionlist(address(this));
        // deploy proxy contract and point it to implementation
        proxy = new TransparentUpgradeableProxy(address(perms), address(this), "");

        bytes32 proxyAdminAddress = vm.load(address(proxy), ADMIN_SLOT);
        proxyAdmin = ProxyAdmin(address(uint160(uint256(proxyAdminAddress))));

        // whitelist bob
        Permissionlist.Permission memory allowPerms = Permissionlist.Permission(true);
        perms.setPermission(bob, allowPerms);
    }

    function testInitialize() public {
        assertEq(perms.permissionAdmin(), address(this));
    }

    function testSetAllowPerms() public {
        assertEq(perms.getPermission(alice).allowed, false);

        // allow alice
        Permissionlist.Permission memory newPerms = Permissionlist.Permission(true);
        perms.setPermission(alice, newPerms);

        assertEq(perms.getPermission(alice).allowed, true);
    }

    function testSetPermissonsRevertsUnauthorized() public {
        vm.prank(alice);

        // should revert, since alice is not the permission admin
        vm.expectRevert(Permissionlist.Unauthorized.selector);
        Permissionlist.Permission memory newPerms = Permissionlist.Permission(true);
        perms.setPermission(alice, newPerms);
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

    function testUpgradePermissions() public {
        PermissionlistV2 permsV2 = new PermissionlistV2(address(this));

        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(permsV2), "");

        // check permission admin didn't change
        assertEq(permsV2.permissionAdmin(), address(this));

        // check bob's whitelisting hasn't changed
        assertEq(permsV2.getPermission(bob).allowed, true);

        // check bob's new statuses are at default false values
        assertEq(permsV2.getPermission(bob).isKyc, false);
        assertEq(permsV2.getPermission(bob).isAccredited, false);

        // set new multi-permission values for bob
        PermissionlistV2.Permission memory multiPerms = PermissionlistV2.Permission(true, true, false);
        permsV2.setPermission(bob, multiPerms);

        assertEq(permsV2.getPermission(bob).allowed, true);
        assertEq(permsV2.getPermission(bob).isKyc, true);
        assertEq(permsV2.getPermission(bob).isAccredited, false);
    }
}
