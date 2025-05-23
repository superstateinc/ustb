pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {IAllowList} from "src/interfaces/allowlist/IAllowList.sol";
import {AllowListV1} from "src/allowlist/v1/AllowListV1.sol";
import "test/allowlist/mocks/MockAllowList.sol";

contract AllowListV1Test is Test {
    event PermissionSet(uint256 indexed addr, IAllowList.Permission permission);
    event EntityIdSet(address indexed addr, uint256 indexed entityId);

    TransparentUpgradeableProxy proxy;
    ProxyAdmin proxyAdmin;

    AllowListV1 public perms;

    address alice = address(10);
    address bob = address(11);
    uint256 bobEntityId = 11;

    IAllowList.Permission public allowPerms = IAllowList.Permission(true, false, false, false, false, false);

    function getAdminAddress(address _proxy) internal view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 adminSlot = vm.load(_proxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }

    function setUp() public {
        AllowListV1 permsImplementation = new AllowListV1(address(this));

        // deploy proxy contract and point it to implementation
        proxy = new TransparentUpgradeableProxy(address(permsImplementation), address(this), "");
        proxyAdmin = ProxyAdmin(getAdminAddress(address(proxy)));

        // wrap in ABI to support easier calls
        perms = AllowListV1(address(proxy));

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

        uint256 aliceEntityId = 1;

        vm.expectEmit(true, true, false, true);
        emit EntityIdSet(alice, aliceEntityId);
        perms.setEntityIdForAddress(aliceEntityId, alice);

        assertEq(perms.addressEntityIds(alice), aliceEntityId);

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(aliceEntityId, allowPerms);

        // allow alice's entity
        perms.setPermission(aliceEntityId, allowPerms);

        assertEq(perms.getPermission(alice).isAllowed, true);
        assertEq(perms.getPermission(alice), allowPerms);
    }

    function testSetPermissionRevertsZeroEntityId() public {
        vm.expectRevert(IAllowList.ZeroEntityIdNotAllowed.selector);
        perms.setPermission(0, allowPerms);
    }

    function testSetEntityIdRevertsChangedNonZero() public {
        perms.setEntityIdForAddress(1, alice);

        vm.expectRevert(IAllowList.NonZeroEntityIdMustBeChangedToZero.selector);
        perms.setEntityIdForAddress(2, alice);
    }

    function testSetEntityIdRevertsAlreadySet() public {
        perms.setEntityIdForAddress(4, alice);

        vm.expectRevert(IAllowList.AlreadySet.selector);
        perms.setEntityIdForAddress(4, alice);
    }

    function testSetEntityIdRevertsAlreadySetZero() public {
        perms.setEntityIdForAddress(0, bob);

        vm.expectRevert(IAllowList.AlreadySet.selector);
        perms.setEntityIdForAddress(0, bob);
    }

    function testRemoveAddressFromEntityRevertsUnauthorized() public {
        vm.prank(alice);

        // should revert, since alice is not the permission admin
        vm.expectRevert(IAllowList.Unauthorized.selector);
        perms.setEntityIdForAddress(0, alice);
    }

    function testRemoveAddressFromEntity() public {
        IAllowList.Permission memory newPerms = IAllowList.Permission(true, false, false, true, false, true);

        perms.setEntityIdForAddress(1, alice);
        perms.setPermission(1, newPerms);
        assertEq(perms.getPermission(alice).isAllowed, true);

        perms.setEntityIdForAddress(0, alice);
        assertEq(perms.addressEntityIds(alice), 0);

        assertEq(perms.getPermission(alice).isAllowed, false);

        perms.setEntityIdForAddress(2, alice);
        assertEq(perms.getPermission(alice).isAllowed, false);
        assertEq(perms.addressEntityIds(alice), 2);
    }

    function testSetEntityIdForMultipleAddresses() public {
        address[] memory addrs = new address[](2);

        uint256 entityId = 1;

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
        vm.expectRevert(IAllowList.Unauthorized.selector);
        perms.setEntityIdForMultipleAddresses(1, addrs);
    }

    function testSetEntityIdForMultipleAddressesRevertsCorrectly() public {
        address charlie = address(2);

        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = charlie;

        address[] memory addrsReversed = new address[](2);
        addrsReversed[0] = charlie;
        addrsReversed[1] = alice;

        perms.setEntityIdForAddress(2, alice);
        perms.setEntityIdForAddress(1, charlie);

        // test setting alice's perms revert because changing from 2 => 1
        vm.expectRevert(IAllowList.NonZeroEntityIdMustBeChangedToZero.selector);
        perms.setEntityIdForMultipleAddresses(1, addrs);

        // test setting charlie's perms revert because changing from 1 => 1
        vm.expectRevert(IAllowList.AlreadySet.selector);
        perms.setEntityIdForMultipleAddresses(1, addrsReversed);
    }

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
        vm.expectRevert(IAllowList.Unauthorized.selector);
        perms.setEntityPermissionAndAddresses(1, addrs, allowPerms);
    }

    function testSetPermissionRevertsUnauthorized() public {
        vm.prank(alice);

        // should revert, since alice is not the permission admin
        vm.expectRevert(IAllowList.Unauthorized.selector);
        IAllowList.Permission memory newPerms = IAllowList.Permission(true, false, false, false, false, false);
        perms.setPermission(1, newPerms);
    }

    function testSetPermissionRevertsAlreadySet() public {
        IAllowList.Permission memory samePerms = IAllowList.Permission(true, false, false, false, false, false);

        // should revert, since bob's perms are already this
        vm.expectRevert(IAllowList.AlreadySet.selector);
        perms.setPermission(bobEntityId, samePerms);
    }

    function testSetDisallowPerms() public {
        assertEq(perms.getPermission(bob).isAllowed, true);

        // disallow bob
        IAllowList.Permission memory disallowPerms = IAllowList.Permission(false, false, false, false, false, false);
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
        IAllowList.Permission memory disallowPerms = IAllowList.Permission(false, false, false, false, false, false);
        perms.setPermission(1, disallowPerms);
        assertEq(perms.getPermission(alice).isAllowed, false);
    }

    function testSetIsAllowedToTrue() public {
        assertEq(perms.getPermission(alice).isAllowed, false);

        perms.setEntityIdForAddress(1, alice);
        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(1, IAllowList.Permission(true, false, false, false, false, false));

        // allow alice
        perms.setIsAllowed(1, true);

        assertEq(perms.getPermission(alice).isAllowed, true);
        assertEq(perms.getPermission(alice), IAllowList.Permission(true, false, false, false, false, false));
    }

    function testSetIsAllowedRevertsZeroEntityId() public {
        vm.expectRevert(IAllowList.ZeroEntityIdNotAllowed.selector);
        perms.setIsAllowed(0, true);
    }

    function testSetIsAllowedToFalse() public {
        assertEq(perms.getPermission(bob).isAllowed, true);

        // emits PermissionSet event
        vm.expectEmit(true, true, true, true);
        emit PermissionSet(bobEntityId, IAllowList.Permission(false, false, false, false, false, false));

        // disallow bob
        perms.setIsAllowed(bobEntityId, false);

        assertEq(perms.getPermission(bob).isAllowed, false);
        assertEq(perms.getPermission(bob), IAllowList.Permission(false, false, false, false, false, false));
    }

    function testSetIsAllowedRevertsUnauthorized() public {
        vm.prank(alice);

        // should revert, since alice is not the permission admin
        vm.expectRevert(IAllowList.Unauthorized.selector);
        perms.setIsAllowed(1, true);
    }

    function testSetIsAllowedRevertsAlreadySet() public {
        // should revert, since `isAllowed` is already set to true for bob
        vm.expectRevert(IAllowList.AlreadySet.selector);
        perms.setIsAllowed(bobEntityId, true);
    }

    function testSetNthPermissionRevertsZeroEntityId() public {
        vm.expectRevert(IAllowList.ZeroEntityIdNotAllowed.selector);
        perms.setNthPermission(0, 0, true);
    }

    function testSetNthPermissionToTrue() public {
        assertEq(perms.getPermission(alice).isAllowed, false);
        assertEq(perms.getPermission(alice), IAllowList.Permission(false, false, false, false, false, false));

        IAllowList.Permission memory currentPerms = IAllowList.Permission(false, false, false, false, false, false);

        /* ===== Set 0th permission ===== */
        currentPerms.isAllowed = true;

        // emits PermissionSet event
        uint256 aliceId = 1;
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

        vm.expectRevert(IAllowList.Unauthorized.selector);
        perms.setNthPermission(bobEntityId, 1, true);
    }

    function testSetNthPermissionBadData() public {
        vm.expectRevert(IAllowList.BadData.selector);
        perms.setNthPermission(bobEntityId, 6, true);
    }

    function testSetNthPermissionAlreadySet() public {
        vm.expectRevert(IAllowList.AlreadySet.selector);
        perms.setNthPermission(bobEntityId, 0, true);

        vm.expectRevert(IAllowList.AlreadySet.selector);
        perms.setNthPermission(bobEntityId, 1, false);

        vm.expectRevert(IAllowList.AlreadySet.selector);
        perms.setNthPermission(bobEntityId, 2, false);

        vm.expectRevert(IAllowList.AlreadySet.selector);
        perms.setNthPermission(bobEntityId, 3, false);

        vm.expectRevert(IAllowList.AlreadySet.selector);
        perms.setNthPermission(bobEntityId, 4, false);

        vm.expectRevert(IAllowList.AlreadySet.selector);
        perms.setNthPermission(bobEntityId, 5, false);
    }

    function testSetNthPermissionToFalse() public {
        perms.setPermission(bobEntityId, IAllowList.Permission(true, true, true, true, true, true));

        assertEq(perms.getPermission(bob).isAllowed, true);
        assertEq(perms.getPermission(bob), IAllowList.Permission(true, true, true, true, true, true));

        IAllowList.Permission memory currentPerms = IAllowList.Permission(true, true, true, true, true, true);

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
        assertEq(perms.getPermission(alice), IAllowList.Permission(false, false, false, false, false, false));
        assertEq(perms.getPermission(bob), IAllowList.Permission(true, false, false, false, false, false));

        MockAllowList permsV2Implementation = new MockAllowList(address(this));
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(permsV2Implementation), "");
        MockAllowList permsV2 = MockAllowList(address(proxy));

        // check Permissions struct values are unchanged after upgrade
        assertEq(
            permsV2.getPermission(alice),
            MockAllowList.Permission(false, false, false, false, false, false, false, false)
        );
        assertEq(
            permsV2.getPermission(bob), MockAllowList.Permission(true, false, false, false, false, false, false, false)
        );

        // check permission admin didn't change
        assertEq(permsV2.permissionAdmin(), address(this));

        // check bob's whitelisting hasn't changed
        assertEq(permsV2.getPermission(bob).isAllowed, true);

        // check bob's new statuses are at default false values
        assertEq(permsV2.getPermission(bob).state1, false);
        assertEq(permsV2.getPermission(bob).state2, false);

        // set new multi-permission values for bob
        MockAllowList.Permission memory multiPerms =
            MockAllowList.Permission(true, true, false, false, false, false, false, false);
        permsV2.setPermission(bobEntityId, multiPerms);

        assertEq(permsV2.getPermission(bob).isAllowed, true);
        assertEq(permsV2.getPermission(bob).state1, true);
        assertEq(permsV2.getPermission(bob).state2, false);
    }

    function assertEq(IAllowList.Permission memory expected, IAllowList.Permission memory actual) internal {
        bytes memory expectedBytes = abi.encode(expected);
        bytes memory actualBytes = abi.encode(actual);
        assertEq(expectedBytes, actualBytes); // use the forge-std/Test assertEq(bytes, bytes) function
    }

    function assertEq(MockAllowList.Permission memory expected, MockAllowList.Permission memory actual) internal {
        bytes memory expectedBytes = abi.encode(expected);
        bytes memory actualBytes = abi.encode(actual);
        assertEq(expectedBytes, actualBytes); // use the forge-std/Test assertEq(bytes, bytes) function
    }
}
