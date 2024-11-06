pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {AllowListV1} from "src/allowlist/v1/AllowListV1.sol";
import {IAllowList} from "src/interfaces/allowlist/IAllowList.sol";
import {IAllowListV2} from "src/interfaces/allowlist/IAllowListV2.sol";
import "test/token/TokenTestBase.t.sol";
import {AllowList} from "src/allowlist/AllowList.sol";

/*
* Note: This is used for v2 and beyond, as v1 is incompatible
*/
abstract contract AllowListTestBase is TokenTestBase {
    ProxyAdmin allowListProxyAdmin;
    TransparentUpgradeableProxy allowListProxy;
    IAllowListV2 allowList;

    address alice = address(10);
    address bob = address(11);
    address charlie = address(12);

    IAllowListV2.EntityId aliceEntityId = IAllowListV2.EntityId.wrap(10);
    IAllowListV2.EntityId bobEntityId = IAllowListV2.EntityId.wrap(11);

    IAllowList.Permission public allowPerms = IAllowList.Permission(true, false, false, false, false, false);

    function setUp() public virtual {
        initializeAllowList();
    }

    function initializeAllowList() public virtual {
        AllowList allowListImplementation = new AllowList();

        allowListProxy = new TransparentUpgradeableProxy(address(allowListImplementation), address(this), "");

        allowListProxyAdmin = ProxyAdmin(getAdminAddress(address(allowListProxy)));

        allowList = IAllowListV2(address(allowListProxy));

        allowList.initialize();
    }

    function testSetEntityAllowedForFund() public virtual {
        // allowlist bob
        allowList.setEntityIdForAddress(IAllowListV2.EntityId.unwrap(bobEntityId), bob);
        allowList.setEntityAllowedForFund(bobEntityId, "USTB", true);

        // bob approved for USTB
        assertEq(allowList.isAddressAllowedForFund(bob, "USTB"), true);
        assertEq(allowList.isEntityAllowedForFund(bobEntityId, "USTB"), true);

        // but not approved for USCC
        assertEq(allowList.isAddressAllowedForFund(bob, "USCC"), false);
        assertEq(allowList.isEntityAllowedForFund(bobEntityId, "USCC"), false);

        // alice approved for neither USTB/USCC
        allowList.setEntityIdForAddress(IAllowListV2.EntityId.unwrap(aliceEntityId), alice);
        assertEq(allowList.isAddressAllowedForFund(alice, "USTB"), false);
        assertEq(allowList.isEntityAllowedForFund(aliceEntityId, "USTB"), false);
        assertEq(allowList.isAddressAllowedForFund(alice, "USCC"), false);
        assertEq(allowList.isEntityAllowedForFund(aliceEntityId, "USCC"), false);
    }

    function testSingleSetEntityPermissionsAndAddresses() public virtual {
        // allowlist bob
        address[] memory addrsToSet = new address[](1);
        addrsToSet[0] = bob;
        string[] memory fundsToSet = new string[](1);
        fundsToSet[0] = "USTB";
        bool[] memory fundPermissionsToSet = new bool[](1);
        fundPermissionsToSet[0] = true;
        allowList.setEntityPermissionsAndAddresses(bobEntityId, addrsToSet, fundsToSet, fundPermissionsToSet);

        // bob approved for USTB
        assertEq(allowList.isAddressAllowedForFund(bob, "USTB"), true);
        assertEq(allowList.isEntityAllowedForFund(bobEntityId, "USTB"), true);

        // but not approved for USCC
        assertEq(allowList.isAddressAllowedForFund(bob, "USCC"), false);
        assertEq(allowList.isEntityAllowedForFund(bobEntityId, "USCC"), false);

        // alice approved for neither USTB/USCC
        allowList.setEntityIdForAddress(IAllowListV2.EntityId.unwrap(aliceEntityId), alice);
        assertEq(allowList.isAddressAllowedForFund(alice, "USTB"), false);
        assertEq(allowList.isEntityAllowedForFund(aliceEntityId, "USTB"), false);
        assertEq(allowList.isAddressAllowedForFund(alice, "USCC"), false);
        assertEq(allowList.isEntityAllowedForFund(aliceEntityId, "USCC"), false);
    }

    function testMultipleEntityPermissionsAndAddresses() public virtual {
        // allowlist bob and charlie to the same entity
        address[] memory addrsToSet = new address[](2);
        addrsToSet[0] = bob;
        addrsToSet[1] = charlie;
        string[] memory fundsToSet = new string[](2);
        fundsToSet[0] = "USTB";
        fundsToSet[1] = "USCC";
        bool[] memory fundPermissionsToSet = new bool[](2);
        fundPermissionsToSet[0] = true;
        fundPermissionsToSet[1] = false;
        allowList.setEntityPermissionsAndAddresses(bobEntityId, addrsToSet, fundsToSet, fundPermissionsToSet);

        // bob approved for USTB
        assertEq(allowList.isAddressAllowedForFund(bob, "USTB"), true);
        assertEq(allowList.isEntityAllowedForFund(bobEntityId, "USTB"), true);

        // but not approved for USCC
        assertEq(allowList.isAddressAllowedForFund(bob, "USCC"), false);
        assertEq(allowList.isEntityAllowedForFund(bobEntityId, "USCC"), false);

        // charlie approved for USTB
        assertEq(allowList.isAddressAllowedForFund(charlie, "USTB"), true);

        // but not approved for USCC
        assertEq(allowList.isAddressAllowedForFund(charlie, "USCC"), false);

        // alice approved for neither USTB/USCC
        allowList.setEntityIdForAddress(IAllowListV2.EntityId.unwrap(aliceEntityId), alice);
        assertEq(allowList.isAddressAllowedForFund(alice, "USTB"), false);
        assertEq(allowList.isEntityAllowedForFund(aliceEntityId, "USTB"), false);
        assertEq(allowList.isAddressAllowedForFund(alice, "USCC"), false);
        assertEq(allowList.isEntityAllowedForFund(aliceEntityId, "USCC"), false);
    }

    function testSetEntityIdForMultipleAddresses() public {
        address[] memory addrsToSet = new address[](2);
        addrsToSet[0] = bob;
        addrsToSet[1] = charlie;
        allowList.setEntityIdForMultipleAddresses(IAllowListV2.EntityId.unwrap(bobEntityId), addrsToSet);

        AllowList allowListV2 = AllowList(address(allowListProxy));
        assertEq(
            IAllowListV2.EntityId.unwrap(allowListV2.addressEntityIds(bob)), IAllowListV2.EntityId.unwrap(bobEntityId)
        );
        assertEq(
            IAllowListV2.EntityId.unwrap(allowListV2.addressEntityIds(charlie)),
            IAllowListV2.EntityId.unwrap(bobEntityId)
        );
    }

    function testSetEntityIdRevertsChangedNonZero() public {
        // allowlist bob
        allowList.setEntityIdForAddress(IAllowListV2.EntityId.unwrap(bobEntityId), bob);
        allowList.setEntityAllowedForFund(bobEntityId, "USTB", true);

        // block setting again
        vm.expectRevert(IAllowList.NonZeroEntityIdMustBeChangedToZero.selector);
        allowList.setEntityIdForAddress(2, bob);
    }

    function testSetEntityIdRevertsAlreadySet() public {
        // allowlist bob
        allowList.setEntityIdForAddress(IAllowListV2.EntityId.unwrap(bobEntityId), bob);
        allowList.setEntityAllowedForFund(bobEntityId, "USTB", true);

        // block setting to the same again
        vm.expectRevert(IAllowList.AlreadySet.selector);
        allowList.setEntityIdForAddress(IAllowListV2.EntityId.unwrap(bobEntityId), bob);
    }

    function testSetEntityIdRevertsAlreadySetZero() public {
        // allowlist bob
        allowList.setEntityIdForAddress(IAllowListV2.EntityId.unwrap(bobEntityId), bob);
        allowList.setEntityAllowedForFund(bobEntityId, "USTB", true);

        // set to zero
        allowList.setEntityIdForAddress(0, bob);

        // blocking setting to zero again
        vm.expectRevert(IAllowList.AlreadySet.selector);
        allowList.setEntityIdForAddress(0, bob);
    }

    function testSetEntityAllowedForFundRevertsUnauthorized() public {
        vm.prank(alice);

        // should revert, since alice is not the permission admin
        vm.expectRevert("Ownable: caller is not the owner");
        allowList.setEntityIdForAddress(0, alice);
    }

    function testSetEntityPermissionsAndAddressesRevertsUnauthorized() public {
        // allowlist bob
        address[] memory addrsToSet = new address[](1);
        addrsToSet[0] = bob;
        string[] memory fundsToSet = new string[](1);
        fundsToSet[0] = "USTB";
        bool[] memory fundPermissionsToSet = new bool[](1);
        fundPermissionsToSet[0] = true;

        // should revert, since alice is not the permission admin
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        allowList.setEntityPermissionsAndAddresses(bobEntityId, addrsToSet, fundsToSet, fundPermissionsToSet);
    }

    function testV1FunctionsDeprecated() public {
        vm.expectRevert(IAllowListV2.Deprecated.selector);
        allowList.getPermission(bob);

        vm.expectRevert(IAllowListV2.Deprecated.selector);
        allowList.setPermission(0, allowPerms);

        vm.expectRevert(IAllowListV2.Deprecated.selector);
        address[] memory addrsToSet = new address[](1);
        addrsToSet[0] = bob;
        allowList.setEntityPermissionAndAddresses(0, addrsToSet, allowPerms);

        vm.expectRevert(IAllowListV2.Deprecated.selector);
        allowList.setIsAllowed(0, true);

        vm.expectRevert(IAllowListV2.Deprecated.selector);
        allowList.setNthPermission(0, 0, true);
    }
}
