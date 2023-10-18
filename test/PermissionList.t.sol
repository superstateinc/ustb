pragma solidity ^0.8.20;

import "forge-std/StdUtils.sol";
import { Test } from "forge-std/Test.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import "src/PermissionList.sol";
import "test/PermissionListV2.sol";

contract PermissionListTest is Test {
    event PermissionSet(uint indexed addr, PermissionList.Permission permission);
    event EntityIdSet(address indexed addr, uint indexed entityId);

    TransparentUpgradeableProxy proxy;
    ProxyAdmin proxyAdmin;

    PermissionList public perms;

    address alice = address(10);
    address bob = address(11);
    uint bobEntityId = 11;
    
    PermissionList.Permission public allowPerms = PermissionList.Permission(true, false, false, false, false, false);

    function setUp() public {
        PermissionList permsImplementation = new PermissionList(address(this));

        // deploy proxy admin contract
        proxyAdmin = new ProxyAdmin();

        // deploy proxy contract and point it to implementation
        proxy = new TransparentUpgradeableProxy(address(permsImplementation), address(proxyAdmin), "");

        // wrap in ABI to support easier calls
        perms = PermissionList(address(proxy));

        // whitelist bob
        address[] memory addrs = new address[](1);
        addrs[0] = bob;
        perms.setEntityPermissionAndAddresses(bobEntityId, addrs, allowPerms);
    }

    function testInitialize() public {
        assertEq(perms.permissionAdmin(), address(this));
    }

    function testSetEntityIdSetPermission() public {
        assertEq(perms.getPermission(alice).isAllowed, false);

        uint aliceEntityId = 1;

        vm.expectEmit(true, true, false, true);
        emit EntityIdSet(alice, aliceEntityId);
        perms.setEntityIdForAddress(aliceEntityId, alice);

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(aliceEntityId, allowPerms);

        // allow alice's entity
        perms.setPermission(aliceEntityId, allowPerms);

        assertEq(perms.getPermission(alice).isAllowed, true);
        assertEq(perms.getPermission(alice), allowPerms);
    }

    function testSetPermissionRevertsZeroEntityId() public {
        vm.expectRevert(PermissionList.ZeroEntityIdNotAllowed.selector);
        perms.setPermission(0, allowPerms);
    }

    function testSetEntityIdRevertsChangedNonZero() public {
        perms.setEntityIdForAddress(1, alice);
        
        vm.expectRevert(PermissionList.EntityIdChangedToNonZero.selector);
        perms.setEntityIdForAddress(2, alice);
    }

    function testSetEntityIdRevertsAlreadySet() public {
        perms.setEntityIdForAddress(4, alice);
        
        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setEntityIdForAddress(4, alice);
    }

    function testSetEntityIdRevertsAlreadySetZero() public {
        perms.setEntityIdForAddress(0, bob);
        
        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setEntityIdForAddress(0, bob);
    }

    function testRemoveAddressFromEntityRevertsUnauthorized() public {
        vm.prank(alice);

        // should revert, since alice is not the permission admin
        vm.expectRevert(PermissionList.Unauthorized.selector);
        perms.setEntityIdForAddress(0, alice);
    }

    function testRemoveAddressFromEntity() public {
        PermissionList.Permission memory newPerms = PermissionList.Permission(true, false, false, true, false, true);

        perms.setEntityIdForAddress(1, alice);
        perms.setPermission(1, newPerms);
        assertEq(perms.getPermission(alice).isAllowed, true);

        perms.setEntityIdForAddress(0, alice);

        assertEq(perms.getPermission(alice).isAllowed, false);
    }

    function testSetEntityIdForMultipleAddresses() public {
        address[] memory addrs = new address[](2);

        uint entityId = 1;

        address charlie = address(2);
        addrs[0] = alice;
        addrs[1] = charlie;

        assertEq(perms.addressEntityIds(alice), 0);
        assertEq(perms.addressEntityIds(charlie), 0);
        assertEq(perms.getPermission(alice).isAllowed, false);
        assertEq(perms.getPermission(charlie).isAllowed, false);

        vm.expectEmit(true, true, true, true);
        emit EntityIdSet(alice, entityId);
        emit EntityIdSet(charlie, entityId);
        perms.setEntityIdForMultipleAddresses(entityId, addrs);

        assertEq(perms.addressEntityIds(alice), entityId);
        assertEq(perms.addressEntityIds(charlie), entityId);
        
        perms.setPermission(entityId, allowPerms);
        assertEq(perms.getPermission(alice).isAllowed, true);
        assertEq(perms.getPermission(charlie).isAllowed, true);
    }

    function testSetEntityIdForMultipleAddressesRevertsUnauthorized() public {
        vm.prank(alice);

        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;

        // should revert, since alice is not the permission admin
        vm.expectRevert(PermissionList.Unauthorized.selector);
        perms.setEntityIdForMultipleAddresses(1, addrs);
    }

    function testSetEntityIdForMultipleAddressesRevertsAlreadySet() public {
        address[] memory addrs = new address[](2);
        address charlie = address(2);

        addrs[0] = alice;
        addrs[1] = charlie;

        perms.setEntityIdForAddress(2, alice);
        perms.setEntityIdForAddress(1, charlie);

        // reverts if only one is duplicated
        vm.expectRevert(PermissionList.EntityIdChangedToNonZero.selector);
        perms.setEntityIdForMultipleAddresses(1, addrs);
    }
    // TODO: reverts if set to zero

    function testSetEntityPermissionAndAddresses() public {
        address[] memory addrs = new address[](2);
        
        address charlie = address(2);
        addrs[0] = alice;
        addrs[1] = charlie;

        assertEq(perms.addressEntityIds(alice), 0);
        assertEq(perms.addressEntityIds(charlie), 0);
        assertEq(perms.getPermission(alice).isAllowed, false);
        assertEq(perms.getPermission(charlie).isAllowed, false);

        vm.expectEmit(true, true, true, true);
        emit EntityIdSet(alice, 1);
        emit EntityIdSet(charlie, 1);
        emit PermissionSet(1, allowPerms);
        perms.setEntityPermissionAndAddresses(1, addrs, allowPerms);

        assertEq(perms.addressEntityIds(alice), 1);
        assertEq(perms.addressEntityIds(charlie), 1);
        
        assertEq(perms.getPermission(alice).isAllowed, true);
        assertEq(perms.getPermission(charlie).isAllowed, true);
    }

    function testSetEntityPermissionsAndAddressesRevertsUnauthorized() public {
        vm.prank(alice);
        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;

        // should revert, since alice is not the permission admin
        vm.expectRevert(PermissionList.Unauthorized.selector);
        perms.setEntityPermissionAndAddresses(1, addrs, allowPerms);
    }

    function testSetPermissionRevertsUnauthorized() public {
        vm.prank(alice);

        // should revert, since alice is not the permission admin
        vm.expectRevert(PermissionList.Unauthorized.selector);
        PermissionList.Permission memory newPerms = PermissionList.Permission(true, false, false, false, false, false);
        perms.setPermission(1, newPerms);
    }

    function testSetPermissionRevertsAlreadySet() public {
        PermissionList.Permission memory samePerms = PermissionList.Permission(true, false, false, false, false, false);

        // should revert, since bob's perms are already this
        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setPermission(bobEntityId, samePerms);
    }

    function testSetDisallowPerms() public {
        assertEq(perms.getPermission(bob).isAllowed, true);

        // disallow bob
        PermissionList.Permission memory disallowPerms = PermissionList.Permission(false, false, false, false, false, false);
        perms.setPermission(bobEntityId, disallowPerms);

        assertEq(perms.getPermission(bob).isAllowed, false);
    }

    function testUndoAllowPerms() public {
        assertEq(perms.getPermission(alice).isAllowed, false);

        // allow alice
        perms.setEntityIdForAddress(1, alice);
        perms.setPermission(1, allowPerms);
        assertEq(perms.getPermission(alice).isAllowed, true);

        // now disallow alice
        PermissionList.Permission memory disallowPerms = PermissionList.Permission(false, false, false, false, false, false);
        perms.setPermission(1, disallowPerms);
        assertEq(perms.getPermission(alice).isAllowed, false);
    }

    function testSetIsAllowedToTrue() public {
        assertEq(perms.getPermission(alice).isAllowed, false);

        perms.setEntityIdForAddress(1, alice);
        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(1, PermissionList.Permission(true, false, false, false, false, false));

        // allow alice
        perms.setIsAllowed(1, true);

        assertEq(perms.getPermission(alice).isAllowed, true);
        assertEq(perms.getPermission(alice), PermissionList.Permission(true, false, false, false, false, false));
    }

    function testSetIsAllowedRevertsZeroEntityId() public {
        vm.expectRevert(PermissionList.ZeroEntityIdNotAllowed.selector);
        perms.setIsAllowed(0, true);
    }

    function testSetIsAllowedToFalse() public {
        assertEq(perms.getPermission(bob).isAllowed, true);

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bobEntityId, PermissionList.Permission(false, false, false, false, false, false));

        // disallow bob
        perms.setIsAllowed(bobEntityId, false);

        assertEq(perms.getPermission(bob).isAllowed, false);
        assertEq(perms.getPermission(bob), PermissionList.Permission(false, false, false, false, false, false));
    }

    function testSetIsAllowedRevertsUnauthorized() public {
        vm.prank(alice);

        // should revert, since alice is not the permission admin
        vm.expectRevert(PermissionList.Unauthorized.selector);
        perms.setIsAllowed(1, true);
    }

    function testSetIsAllowedRevertsAlreadySet() public {
        // should revert, since `isAllowed` is already set to true for bob
        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setIsAllowed(bobEntityId, true);
    }

    function testSetNthPermissionRevertsZeroEntityId() public {
        vm.expectRevert(PermissionList.ZeroEntityIdNotAllowed.selector);
        perms.setNthPermission(0, 0, true);
    }

    function testSetNthPermissionToTrue() public {
        assertEq(perms.getPermission(alice).isAllowed, false);
        assertEq(perms.getPermission(alice), PermissionList.Permission(false, false, false, false, false, false));

        PermissionList.Permission memory currentPerms = PermissionList.Permission(false, false, false, false, false, false);

        /* ===== Set 0th permission ===== */
        currentPerms.isAllowed = true;

        // emits PermissionSet event
        uint aliceId = 1;
        perms.setEntityIdForAddress(1, alice);
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(aliceId, currentPerms);

        // allow alice
        perms.setNthPermission(aliceId, 0, true);

        assertEq(perms.getPermission(alice).isAllowed, true);
        assertEq(perms.getPermission(alice), currentPerms);

        /* ===== Set 1st permission ===== */
        currentPerms.state1 = true;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(aliceId, currentPerms);

        // allow alice
        perms.setNthPermission(1, 1, true);

        assertEq(perms.getPermission(alice).state1, true);
        assertEq(perms.getPermission(alice), currentPerms);

        /* ===== Set 2nd permission ===== */
        currentPerms.state2 = true;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(aliceId, currentPerms);

        // allow alice
        perms.setNthPermission(1, 2, true);

        assertEq(perms.getPermission(alice).state2, true);
        assertEq(perms.getPermission(alice), currentPerms);

        /* ===== Set 3rd permission ===== */
        currentPerms.state3 = true;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(aliceId, currentPerms);

        // allow alice
        perms.setNthPermission(1, 3, true);

        assertEq(perms.getPermission(alice).state3, true);
        assertEq(perms.getPermission(alice), currentPerms);

        /* ===== Set 4th permission ===== */
        currentPerms.state4 = true;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(aliceId, currentPerms);

        // allow alice
        perms.setNthPermission(1, 4, true);

        assertEq(perms.getPermission(alice).state4, true);
        assertEq(perms.getPermission(alice), currentPerms);

        /* ===== Set 5th permission ===== */
        currentPerms.state5 = true;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(aliceId, currentPerms);

        // allow alice
        perms.setNthPermission(1, 5, true);

        assertEq(perms.getPermission(alice).state5, true);
        assertEq(perms.getPermission(alice), currentPerms);
    }

    function testSetNthPermissionUnauthorized() public {
        hoax(alice);

        vm.expectRevert(PermissionList.Unauthorized.selector);
        perms.setNthPermission(bobEntityId, 1, true);
    }

    function testSetNthPermissionBadData() public {
        vm.expectRevert(PermissionList.BadData.selector);
        perms.setNthPermission(bobEntityId, 6, true);
    }

    function testSetNthPermissionAlreadySet() public {
        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setNthPermission(bobEntityId, 0, true);

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setNthPermission(bobEntityId, 1, false);

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setNthPermission(bobEntityId, 2, false);

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setNthPermission(bobEntityId, 3, false);

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setNthPermission(bobEntityId, 4, false);

        vm.expectRevert(PermissionList.AlreadySet.selector);
        perms.setNthPermission(bobEntityId, 5, false);
    }

    function testSetNthPermissionToFalse() public {
        perms.setPermission(bobEntityId, PermissionList.Permission(true, true, true, true, true, true));

        assertEq(perms.getPermission(bob).isAllowed, true);
        assertEq(perms.getPermission(bob), PermissionList.Permission(true, true, true, true, true, true));

        PermissionList.Permission memory currentPerms = PermissionList.Permission(true, true, true, true, true, true);

        /* ===== Set 0th permission ===== */
        currentPerms.isAllowed = false;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bobEntityId, currentPerms);

        // allow bob
        perms.setNthPermission(bobEntityId, 0, false);

        assertEq(perms.getPermission(bob).isAllowed, false);
        assertEq(perms.getPermission(bob), currentPerms);

        /* ===== Set 1st permission ===== */
        currentPerms.state1 = false;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bobEntityId, currentPerms);

        // allow bob
        perms.setNthPermission(bobEntityId, 1, false);

        assertEq(perms.getPermission(bob).state1, false);
        assertEq(perms.getPermission(bob), currentPerms);

        /* ===== Set 2nd permission ===== */
        currentPerms.state2 = false;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bobEntityId, currentPerms);

        // allow bob
        perms.setNthPermission(bobEntityId, 2, false);

        assertEq(perms.getPermission(bob).state2, false);
        assertEq(perms.getPermission(bob), currentPerms);

        /* ===== Set 3rd permission ===== */
        currentPerms.state3 = false;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bobEntityId, currentPerms);

        // allow bob
        perms.setNthPermission(bobEntityId, 3, false);

        assertEq(perms.getPermission(bob).state3, false);
        assertEq(perms.getPermission(bob), currentPerms);

        /* ===== Set 4th permission ===== */
        currentPerms.state4 = false;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bobEntityId, currentPerms);

        // allow bob
        perms.setNthPermission(bobEntityId, 4, false);

        assertEq(perms.getPermission(bob).state4, false);
        assertEq(perms.getPermission(bob), currentPerms);

        /* ===== Set 5th permission ===== */
        currentPerms.state5 = false;

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bobEntityId, currentPerms);

        // allow bob
        perms.setNthPermission(bobEntityId, 5, false);

        assertEq(perms.getPermission(bob).state5, false);
        assertEq(perms.getPermission(bob), currentPerms);
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
        permsV2.setPermission(bobEntityId, multiPerms);

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
