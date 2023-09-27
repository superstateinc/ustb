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

    address alice = address(10);
    address bob = address(11);

    function setUp() public {
        PermissionList permsImplementation = new PermissionList(address(this));

        // deploy proxy admin contract
        proxyAdmin = new ProxyAdmin();

        // deploy proxy contract and point it to implementation
        proxy = new TransparentUpgradeableProxy(address(permsImplementation), address(proxyAdmin), "");

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

    function testSetPermissionRevertsUnauthorized() public {
        vm.prank(alice);

        // should revert, since alice is not the permission admin
        vm.expectRevert(PermissionList.Unauthorized.selector);
        PermissionList.Permission memory newPerms = PermissionList.Permission(true, false, false, false, false, false);
        perms.setPermission(alice, newPerms);
    }

    function testSetPermissionRevertsAlreadySet() public {
        PermissionList.Permission memory samePerms = PermissionList.Permission(true, false, false, false, false, false);

        // should revert, since bob's perms are already this
        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setPermission(bob, samePerms);
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

    function testSetMultiplePermissions() public {
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

    function testSetMultiplePermissionsRevertsUnauthorized() public {
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

    function testSetMultiplePermissionsRevertsAlreadySet() public {
        address[] memory users = new address[](1);
        PermissionList.Permission[] memory samePerms = new PermissionList.Permission[](1);
        users[0] = bob;
        samePerms[0] = PermissionList.Permission(true, false, false, false, false, false);

        // should revert, since bob's perms are already this
        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setMultiplePermissions(users, samePerms);
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

    function testSetIsAllowedRevertsAlreadySet() public {
        // should revert, since `isAllowed` is already set to true for bob
        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setIsAllowed(bob, true);
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

    function testSetMultipleIsAllowedRevertsAlreadySet() public {
        address[] memory users = new address[](1);
        bool[] memory sameValues = new bool[](1);
        users[0] = bob;
        sameValues[0] = true;

        // should revert, since `isAllowed` is already set to true for bob
        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setMultipleIsAllowed(users, sameValues);
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

    function testSetNthPermissionUnauthorized() public {
        hoax(alice);

        vm.expectRevert(PermissionList.Unauthorized.selector);
        perms.setNthPermission(bob, 1, true);
    }

    function testSetNthPermissionBadData() public {
        vm.expectRevert(PermissionList.BadData.selector);
        perms.setNthPermission(bob, 6, true);
    }

    function testSetNthPermissionAlreadySet() public {
        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setNthPermission(bob, 0, true);

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setNthPermission(bob, 1, false);

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setNthPermission(bob, 2, false);

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setNthPermission(bob, 3, false);

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setNthPermission(bob, 4, false);

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setNthPermission(bob, 5, false);
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

    function testSetMultipleNthPermissions() public {
        perms.setPermission(bob, PermissionList.Permission(true, true, true, true, true, true));

        assertEq(perms.getPermission(alice), PermissionList.Permission(false, false, false, false, false, false));
        assertEq(perms.getPermission(bob), PermissionList.Permission(true, true, true, true, true, true));

        // we'll be iteratively setting alice's permissions to true and bob's to false, starting from the 0 index
        address[] memory users = new address[](12);
        uint[] memory indices = new uint[](12);
        bool[] memory newValues = new bool[](12);
        users[0] = alice;
        users[1] = alice;
        users[2] = alice;
        users[3] = alice;
        users[4] = alice;
        users[5] = alice;
        users[6] = bob;
        users[7] = bob;
        users[8] = bob;
        users[9] = bob;
        users[10] = bob;
        users[11] = bob;
        indices[0] = 0;
        indices[1] = 1;
        indices[2] = 2;
        indices[3] = 3;
        indices[4] = 4;
        indices[5] = 5;
        indices[6] = 0;
        indices[7] = 1;
        indices[8] = 2;
        indices[9] = 3;
        indices[10] = 4;
        indices[11] = 5;
        newValues[0] = true;
        newValues[1] = true;
        newValues[2] = true;
        newValues[3] = true;
        newValues[4] = true;
        newValues[5] = true;
        newValues[6] = false;
        newValues[7] = false;
        newValues[8] = false;
        newValues[9] = false;
        newValues[10] = false;
        newValues[11] = false;

        // emits multiple PermissionSet events
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, PermissionList.Permission(true, false, false, false, false, false));
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, PermissionList.Permission(true, true, false, false, false, false));
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, PermissionList.Permission(true, true, true, false, false, false));
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, PermissionList.Permission(true, true, true, true, false, false));
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, PermissionList.Permission(true, true, true, true, true, false));
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(alice, PermissionList.Permission(true, true, true, true, true, true));
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, PermissionList.Permission(false, true, true, true, true, true));
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, PermissionList.Permission(false, false, true, true, true, true));
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, PermissionList.Permission(false, false, false, true, true, true));
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, PermissionList.Permission(false, false, false, false, true, true));
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, PermissionList.Permission(false, false, false, false, false, true));
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bob, PermissionList.Permission(false, false, false, false, false, false));

        perms.setMultipleNthPermissions(users, indices, newValues);

        assertEq(perms.getPermission(alice), PermissionList.Permission(true, true, true, true, true, true));
        assertEq(perms.getPermission(bob), PermissionList.Permission(false, false, false, false, false, false));
    }

    function testSetMultipleNthPermissionsRevertsUnauthorized() public {
        vm.prank(alice);

        address[] memory users = new address[](1);
        uint[] memory indices = new uint[](1);
        bool[] memory newValues = new bool[](1);
        users[0] = alice;
        indices[0] = 0;
        newValues[0] = false;

        // should revert, since alice is not the permission admin
        vm.expectRevert(PermissionList.Unauthorized.selector);
        perms.setMultipleNthPermissions(users, indices, newValues);
    }

    function testSetMultipleNthPermissionsRevertsAlreadySet() public {
        address[] memory users = new address[](1);
        uint[] memory indices = new uint[](1);
        bool[] memory sameValues = new bool[](1);
        users[0] = bob;
        indices[0] = 0;
        sameValues[0] = true;

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setMultipleNthPermissions(users, indices, sameValues);

        indices[0] = 1;
        sameValues[0] = false;

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setMultipleNthPermissions(users, indices, sameValues);

        indices[0] = 2;
        sameValues[0] = false;

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setMultipleNthPermissions(users, indices, sameValues);

        indices[0] = 3;
        sameValues[0] = false;

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setMultipleNthPermissions(users, indices, sameValues);

        indices[0] = 4;
        sameValues[0] = false;

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setMultipleNthPermissions(users, indices, sameValues);

        indices[0] = 5;
        sameValues[0] = false;

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setMultipleNthPermissions(users, indices, sameValues);
    }

    function testSetMultipleNthPermissionsRevertsBadData() public {
        address[] memory users = new address[](1);
        uint[] memory indices = new uint[](2);
        bool[] memory newValues = new bool[](1);

        // should revert, since the input lists are different lengths
        vm.expectRevert(PermissionList.BadData.selector);
        perms.setMultipleNthPermissions(users, indices, newValues);

        address[] memory usersB = new address[](1);
        uint[] memory indicesB = new uint[](1);
        bool[] memory newValuesB = new bool[](2);

        // should revert, since the input lists are different lengths
        vm.expectRevert(PermissionList.BadData.selector);
        perms.setMultipleNthPermissions(usersB, indicesB, newValuesB);
    }

    function testUpgradePermissions() public {
        assertEq(perms.getPermission(alice), PermissionList.Permission(false, false, false, false, false, false));
        assertEq(perms.getPermission(bob), PermissionList.Permission(true, false, false, false, false, false));

        PermissionListV2 permsV2Implementation = new PermissionListV2(address(this));
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxy)), address(permsV2Implementation));
        PermissionListV2 permsV2 = PermissionListV2(address(proxy));

        // check Permissions struct values are unchanged after upgrade
        assertEq(permsV2.getPermission(alice), PermissionListV2.Permission(false, false, false, false, false, false, false, false));
        assertEq(permsV2.getPermission(bob), PermissionListV2.Permission(true, false, false, false, false, false, false, false));

        // check permission admin didn't change
        assertEq(permsV2.permissionAdmin(), address(this));

        // check bob's whitelisting hasn't changed
        assertEq(permsV2.getPermission(bob).isAllowed, true);

        // check bob's new statuses are at default false values
        assertEq(permsV2.getPermission(bob).state1, false);
        assertEq(permsV2.getPermission(bob).state2, false);

        // set new multi-permission values for bob
        PermissionListV2.Permission memory multiPerms = PermissionListV2.Permission(true, true, false, false, false, false, false, false);
        permsV2.setPermission(bob, multiPerms);

        assertEq(permsV2.getPermission(bob).isAllowed, true);
        assertEq(permsV2.getPermission(bob).state1, true);
        assertEq(permsV2.getPermission(bob).state2, false);
    }

    function assertEq(PermissionList.Permission memory expected, PermissionList.Permission memory actual) internal {
        bytes memory expectedBytes = abi.encode(expected);
        bytes memory actualBytes = abi.encode(actual);
        assertEq(expectedBytes, actualBytes); // use the forge-std/Test assertEq(bytes, bytes) function
    }

    function assertEq(PermissionListV2.Permission memory expected, PermissionListV2.Permission memory actual) internal {
        bytes memory expectedBytes = abi.encode(expected);
        bytes memory actualBytes = abi.encode(actual);
        assertEq(expectedBytes, actualBytes); // use the forge-std/Test assertEq(bytes, bytes) function
    }
}
