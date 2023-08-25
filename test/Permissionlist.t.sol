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
    Permissionlist public wrappedPerms;

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

        // wrap in ABI to support easier calls
        wrappedPerms = Permissionlist(address(proxy));

        // whitelist bob
        Permissionlist.Permission memory allowPerms = Permissionlist.Permission(true);
        wrappedPerms.setPermission(bob, allowPerms);
    }

    function testInitialize() public {
        assertEq(wrappedPerms.permissionAdmin(), address(this));
    }

    function testSetAllowPerms() public {
        assertEq(wrappedPerms.getPermission(alice).allowed, false);

        // allow alice
        Permissionlist.Permission memory newPerms = Permissionlist.Permission(true);
        wrappedPerms.setPermission(alice, newPerms);

        assertEq(wrappedPerms.getPermission(alice).allowed, true);
    }

    function testSetPermissonsRevertsUnauthorized() public {
        vm.prank(alice);

        // should revert, since alice is not the permission admin
        vm.expectRevert(Permissionlist.Unauthorized.selector);
        Permissionlist.Permission memory newPerms = Permissionlist.Permission(true);
        wrappedPerms.setPermission(alice, newPerms);
    }

    function testSetDisallowPerms() public {
        assertEq(wrappedPerms.getPermission(bob).allowed, true);

        // disallow bob
        Permissionlist.Permission memory disallowPerms = Permissionlist.Permission(false);
        wrappedPerms.setPermission(bob, disallowPerms);

        assertEq(wrappedPerms.getPermission(bob).allowed, false);
    }

    function testUndoAllowPerms() public {
        assertEq(wrappedPerms.getPermission(alice).allowed, false);

        // allow alice
        Permissionlist.Permission memory allowPerms = Permissionlist.Permission(true);
        wrappedPerms.setPermission(alice, allowPerms);
        assertEq(wrappedPerms.getPermission(alice).allowed, true);

        // now disallow alice
        Permissionlist.Permission memory disallowPerms = Permissionlist.Permission(false);
        wrappedPerms.setPermission(alice, disallowPerms);
        assertEq(wrappedPerms.getPermission(alice).allowed, false);
    }

    function testUpgradePermissions() public {
        PermissionlistV2 permsV2 = new PermissionlistV2(address(this));

        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(permsV2), "");

        PermissionlistV2 wrappedPermsV2 = PermissionlistV2(address(proxy));

        // check permission admin didn't change
        assertEq(wrappedPermsV2.permissionAdmin(), address(this));

        // check bob's whitelisting hasn't changed
        assertEq(wrappedPermsV2.getPermission(bob).allowed, true);

        // check bob's new statuses are at default false values
        assertEq(wrappedPermsV2.getPermission(bob).isKyc, false);
        assertEq(wrappedPermsV2.getPermission(bob).isAccredited, false);

        // set new multi-permission values for bob
        PermissionlistV2.Permission memory multiPerms = PermissionlistV2.Permission(true, true, false);
        wrappedPermsV2.setPermission(bob, multiPerms);

        assertEq(wrappedPermsV2.getPermission(bob).allowed, true);
        assertEq(wrappedPermsV2.getPermission(bob).isKyc, true);
        assertEq(wrappedPermsV2.getPermission(bob).isAccredited, false);
    }
}
