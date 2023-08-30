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

    function testSetIsAllowedToTrue() public {
        assertEq(perms.getPermission(alice).isAllowed, false);

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, PermissionList.Permission(true, false, false, false, false, false));

        // allow alice
        perms.setIsAllowed(alice, true);

        assertEq(perms.getPermission(alice).isAllowed, true);
        assertEq(perms.getPermission(alice), PermissionList.Permission(true, false, false, false, false, false));
    }

    function testSetIsAllowedToFalse() public {
        assertEq(perms.getPermission(bob).isAllowed, true);

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, PermissionList.Permission(false, false, false, false, false, false));

        // disallow bob
        perms.setIsAllowed(bob, false);

        assertEq(perms.getPermission(bob).isAllowed, false);
        assertEq(perms.getPermission(bob), PermissionList.Permission(false, false, false, false, false, false));
    }

    function testSetIsAllowedRevertsUnauthorized() public {
        vm.prank(alice);

        // should revert, since alice is not the permission admin
        vm.expectRevert(PermissionList.Unauthorized.selector);
        perms.setIsAllowed(alice, true);
    }

    function testSetMultipleIsAllowed() public {
        assertEq(perms.getPermission(alice).isAllowed, false);
        assertEq(perms.getPermission(bob).isAllowed, true);

        address[] memory users = new address[](2);
        bool[] memory newValues = new bool[](2);
        users[0] = alice;
        users[1] = bob;
        newValues[0] = true;
        newValues[1] = false;

        // emits multiple PermissionSet events
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, PermissionList.Permission(true, false, false, false, false, false));
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, PermissionList.Permission(false, false, false, false, false, false));

        perms.setMultipleIsAllowed(users, newValues);

        assertEq(perms.getPermission(alice).isAllowed, true);
        assertEq(perms.getPermission(bob).isAllowed, false);
        assertEq(perms.getPermission(alice), PermissionList.Permission(true, false, false, false, false, false));
        assertEq(perms.getPermission(bob), PermissionList.Permission(false, false, false, false, false, false));
    }

    function testSetMultipleIsAllowedRevertsUnauthorized() public {
        vm.prank(alice);

        address[] memory users = new address[](1);
        bool[] memory newValues = new bool[](1);
        users[0] = alice;
        newValues[0] = false;

        // should revert, since alice is not the permission admin
        vm.expectRevert(PermissionList.Unauthorized.selector);
        perms.setMultipleIsAllowed(users, newValues);
    }

    function testSetMultipleIsAllowedRevertsBadData() public {
        address[] memory users = new address[](2);
        bool[] memory newValues = new bool[](1);
        users[0] = alice;
        users[1] = bob;
        newValues[0] = false;

        // should revert, since the input lists are different lengths
        vm.expectRevert(PermissionList.BadData.selector);
        perms.setMultipleIsAllowed(users, newValues);
    }

    function testSetNthPermissionToTrue() public {
        assertEq(perms.getPermission(alice).isAllowed, false);
        assertEq(perms.getPermission(alice), PermissionList.Permission(false, false, false, false, false, false));

        PermissionList.Permission memory currentPerms = PermissionList.Permission(false, false, false, false, false, false);

        /* ===== Set 0th permission ===== */
        currentPerms.isAllowed = true;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, currentPerms);

        // allow alice
        perms.setNthPermission(alice, 0, true);

        assertEq(perms.getPermission(alice).isAllowed, true);
        assertEq(perms.getPermission(alice), currentPerms);

        /* ===== Set 1st permission ===== */
        currentPerms.state1 = true;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, currentPerms);

        // allow alice
        perms.setNthPermission(alice, 1, true);

        assertEq(perms.getPermission(alice).state1, true);
        assertEq(perms.getPermission(alice), currentPerms);

        /* ===== Set 2nd permission ===== */
        currentPerms.state2 = true;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, currentPerms);

        // allow alice
        perms.setNthPermission(alice, 2, true);

        assertEq(perms.getPermission(alice).state2, true);
        assertEq(perms.getPermission(alice), currentPerms);

        /* ===== Set 3rd permission ===== */
        currentPerms.state3 = true;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, currentPerms);

        // allow alice
        perms.setNthPermission(alice, 3, true);

        assertEq(perms.getPermission(alice).state3, true);
        assertEq(perms.getPermission(alice), currentPerms);

        /* ===== Set 4th permission ===== */
        currentPerms.state4 = true;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, currentPerms);

        // allow alice
        perms.setNthPermission(alice, 4, true);

        assertEq(perms.getPermission(alice).state4, true);
        assertEq(perms.getPermission(alice), currentPerms);

        /* ===== Set 5th permission ===== */
        currentPerms.state5 = true;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, currentPerms);

        // allow alice
        perms.setNthPermission(alice, 5, true);

        assertEq(perms.getPermission(alice).state5, true);
        assertEq(perms.getPermission(alice), currentPerms);
    }

    function testSetNthPermissionToFalse() public {
        perms.setPermission(bob, PermissionList.Permission(true, true, true, true, true, true));

        assertEq(perms.getPermission(bob).isAllowed, true);
        assertEq(perms.getPermission(bob), PermissionList.Permission(true, true, true, true, true, true));

        PermissionList.Permission memory currentPerms = PermissionList.Permission(true, true, true, true, true, true);

        /* ===== Set 0th permission ===== */
        currentPerms.isAllowed = false;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, currentPerms);

        // allow bob
        perms.setNthPermission(bob, 0, false);

        assertEq(perms.getPermission(bob).isAllowed, false);
        assertEq(perms.getPermission(bob), currentPerms);

        /* ===== Set 1st permission ===== */
        currentPerms.state1 = false;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, currentPerms);

        // allow bob
        perms.setNthPermission(bob, 1, false);

        assertEq(perms.getPermission(bob).state1, false);
        assertEq(perms.getPermission(bob), currentPerms);

        /* ===== Set 2nd permission ===== */
        currentPerms.state2 = false;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, currentPerms);

        // allow bob
        perms.setNthPermission(bob, 2, false);

        assertEq(perms.getPermission(bob).state2, false);
        assertEq(perms.getPermission(bob), currentPerms);

        /* ===== Set 3rd permission ===== */
        currentPerms.state3 = false;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, currentPerms);

        // allow bob
        perms.setNthPermission(bob, 3, false);

        assertEq(perms.getPermission(bob).state3, false);
        assertEq(perms.getPermission(bob), currentPerms);

        /* ===== Set 4th permission ===== */
        currentPerms.state4 = false;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, currentPerms);

        // allow bob
        perms.setNthPermission(bob, 4, false);

        assertEq(perms.getPermission(bob).state4, false);
        assertEq(perms.getPermission(bob), currentPerms);

        /* ===== Set 5th permission ===== */
        currentPerms.state5 = false;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, currentPerms);

        // allow bob
        perms.setNthPermission(bob, 5, false);

        assertEq(perms.getPermission(bob).state5, false);
        assertEq(perms.getPermission(bob), currentPerms);
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
