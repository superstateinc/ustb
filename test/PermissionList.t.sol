pragma solidity ^0.8.20;

import "forge-std/StdUtils.sol";
import { Test } from "forge-std/Test.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import "src/PermissionList.sol";
import "test/PermissionListV2.sol";

contract PermissionListTest is Test {
    event PermissionSet(address indexed addr, PermissionList.Permission permission);

    TransparentUpgradeableProxy proxy;
    ProxyAdmin proxyAdmin;

    PermissionList public perms;

    // Storage slot with the admin of the contract.
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address alice = address(10);
    address bob = address(11);

    function setUp() public {
        PermissionList permsImplementation = new PermissionList(address(this));
        // deploy proxy contract and point it to implementation
        proxy = new TransparentUpgradeableProxy(address(permsImplementation), address(this), "");

        bytes32 proxyAdminAddress = vm.load(address(proxy), ADMIN_SLOT);
        proxyAdmin = ProxyAdmin(address(uint160(uint256(proxyAdminAddress))));

        // wrap in ABI to support easier calls
        perms = PermissionList(address(proxy));

        // whitelist bob
        PermissionList.Permission memory allowPerms = PermissionList.Permission(true, false, false, false, false, false);
        perms.setPermission(bob, allowPerms);
    }

    function testInitialize() public {
        assertEq(perms.permissionAdmin(), address(this));
    }

    function testSetPermission() public {
        assertEq(perms.getPermission(alice).isAllowed, false);

        PermissionList.Permission memory newPerms = PermissionList.Permission(true, false, false, true, false, true);

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, newPerms);

        // allow alice
        perms.setPermission(alice, newPerms);

        assertEq(perms.getPermission(alice).isAllowed, true);
        assertEq(perms.getPermission(alice), PermissionList.Permission(true, false, false, true, false, true));
    }

    function testSetPermissonsRevertsUnauthorized() public {
        vm.prank(alice);

        // should revert, since alice is not the permission admin
        vm.expectRevert(PermissionList.Unauthorized.selector);
        PermissionList.Permission memory newPerms = PermissionList.Permission(true, false, false, false, false, false);
        perms.setPermission(alice, newPerms);
    }

    function testSetDisallowPerms() public {
        assertEq(perms.getPermission(bob).isAllowed, true);

        // disallow bob
        PermissionList.Permission memory disallowPerms = PermissionList.Permission(false, false, false, false, false, false);
        perms.setPermission(bob, disallowPerms);

        assertEq(perms.getPermission(bob).isAllowed, false);
    }

    function testUndoAllowPerms() public {
        assertEq(perms.getPermission(alice).isAllowed, false);

        // allow alice
        PermissionList.Permission memory allowPerms = PermissionList.Permission(true, false, false, false, false, false);
        perms.setPermission(alice, allowPerms);
        assertEq(perms.getPermission(alice).isAllowed, true);

        // now disallow alice
        PermissionList.Permission memory disallowPerms = PermissionList.Permission(false, false, false, false, false, false);
        perms.setPermission(alice, disallowPerms);
        assertEq(perms.getPermission(alice).isAllowed, false);
    }

    function testSetMultiplePermissons() public {
        assertEq(perms.getPermission(alice).isAllowed, false);
        assertEq(perms.getPermission(bob).isAllowed, true);

        address[] memory users = new address[](2);
        PermissionList.Permission[] memory newPerms = new PermissionList.Permission[](2);
        users[0] = alice;
        users[1] = bob;
        newPerms[0] = PermissionList.Permission(true, false, false, false, false, true);
        newPerms[1] = PermissionList.Permission(false, false, true, false, false, false);

        // emits multiple PermissionSet events
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, newPerms[0]);
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, newPerms[1]);

        perms.setMultiplePermissions(users, newPerms);

        assertEq(perms.getPermission(alice).isAllowed, true);
        assertEq(perms.getPermission(bob).isAllowed, false);
        assertEq(perms.getPermission(alice), PermissionList.Permission(true, false, false, false, false, true));
        assertEq(perms.getPermission(bob), PermissionList.Permission(false, false, true, false, false, false));
    }

    function testSetMultiplePermissonsRevertsUnauthorized() public {
        vm.prank(alice);

        address[] memory users = new address[](1);
        PermissionList.Permission[] memory newPerms = new PermissionList.Permission[](1);
        users[0] = alice;
        newPerms[0] = PermissionList.Permission(true, false, false, false, false, false);

        // should revert, since alice is not the permission admin
        vm.expectRevert(PermissionList.Unauthorized.selector);
        perms.setMultiplePermissions(users, newPerms);
    }

    function testSetMultiplePermissonsRevertsBadData() public {
        address[] memory users = new address[](2);
        PermissionList.Permission[] memory newPerms = new PermissionList.Permission[](1);
        users[0] = alice;
        users[1] = bob;
        newPerms[0] = PermissionList.Permission(true, false, false, false, false, false);

        // should revert, since the input lists are different lengths
        vm.expectRevert(PermissionList.BadData.selector);
        perms.setMultiplePermissions(users, newPerms);
    }

    function testUpgradePermissions() public {
        PermissionListV2 permsV2Implementation = new PermissionListV2(address(this));

        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(permsV2Implementation), "");

        PermissionListV2 permsV2 = PermissionListV2(address(proxy));

        // check permission admin didn't change
        assertEq(permsV2.permissionAdmin(), address(this));

        // check bob's whitelisting hasn't changed
        assertEq(permsV2.getPermission(bob).isAllowed, true);

        // check bob's new statuses are at default false values
        assertEq(permsV2.getPermission(bob).isKyc, false);
        assertEq(permsV2.getPermission(bob).isAccredited, false);

        // set new multi-permission values for bob
        PermissionListV2.Permission memory multiPerms = PermissionListV2.Permission(true, true, false);
        permsV2.setPermission(bob, multiPerms);

        assertEq(permsV2.getPermission(bob).isAllowed, true);
        assertEq(permsV2.getPermission(bob).isKyc, true);
        assertEq(permsV2.getPermission(bob).isAccredited, false);
    }

    function assertEq(PermissionList.Permission memory expected, PermissionList.Permission memory actual) internal {
        bytes memory expectedBytes = abi.encode(expected);
        bytes memory actualBytes = abi.encode(actual);
        assertEq(expectedBytes, actualBytes); // use the forge-std/Test assertEq(bytes, bytes) function
    }
}
