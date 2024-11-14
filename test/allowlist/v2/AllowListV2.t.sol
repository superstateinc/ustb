pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {SuperstateTokenV1} from "src/v1/SuperstateTokenV1.sol";
import {ISuperstateTokenV1} from "src/interfaces/ISuperstateTokenV1.sol";
import {USTBv1} from "src/v1/USTBv1.sol";
import {AllowListV1} from "src/allowlist/v1/AllowListV1.sol";
import {IAllowList} from "src/interfaces/allowlist/IAllowList.sol";
import {IAllowListV2} from "src/interfaces/allowlist/IAllowListV2.sol";
import "test/allowlist/mocks/MockAllowList.sol";
import "test/token/mocks/MockUSTBv1.sol";
import "test/token/TokenTestBase.t.sol";
import {AllowList} from "src/allowlist/AllowList.sol";
import {AllowListTestBase} from "../AllowListTestBase.t.sol";
import {MockContract} from "../mocks/MockContract.sol";

contract AllowListV2Test is AllowListTestBase {
    MockContract public mockProtocol;
    MockContract public mockProtocol2;

    function setUp() public override {
        super.setUp();
        mockProtocol = new MockContract();
        mockProtocol2 = new MockContract();
    }

    function testSetProtocolAddressPermission() public {
        // Test setting permission for a single fund
        allowList.setProtocolAddressPermission(address(mockProtocol), "USTB", true);

        assertEq(allowList.isAddressAllowedForFund(address(mockProtocol), "USTB"), true);
        assertEq(allowList.protocolPermissionsForFunds(address(mockProtocol)), 1);

        // Test setting permission for another fund
        allowList.setProtocolAddressPermission(address(mockProtocol), "USCC", true);
        assertEq(allowList.isAddressAllowedForFund(address(mockProtocol), "USCC"), true);
        assertEq(allowList.protocolPermissionsForFunds(address(mockProtocol)), 2);

        // Test removing permission
        allowList.setProtocolAddressPermission(address(mockProtocol), "USTB", false);
        assertEq(allowList.isAddressAllowedForFund(address(mockProtocol), "USTB"), false);
        assertEq(allowList.protocolPermissionsForFunds(address(mockProtocol)), 1);

        allowList.setProtocolAddressPermission(address(mockProtocol), "USCC", false);
        assertEq(allowList.isAddressAllowedForFund(address(mockProtocol), "USCC"), false);
        assertEq(allowList.protocolPermissionsForFunds(address(mockProtocol)), 0);
    }

    function testSetProtocolAddressPermissionRevertsForEOA() public {
        vm.expectRevert(IAllowListV2.CodeSizeZero.selector);
        allowList.setProtocolAddressPermission(alice, "USTB", true);
    }

    function testSetProtocolAddressPermissionRevertsForAddressWithEntityId() public {
        // First set entity ID
        allowList.setEntityIdForAddress(IAllowListV2.EntityId.unwrap(bobEntityId), bob);

        vm.expectRevert(IAllowListV2.AddressHasEntityId.selector);
        allowList.setProtocolAddressPermission(bob, "USTB", true);
    }

    function testSetProtocolAddressPermissionRevertsForSameValue() public {
        // Set initial value
        allowList.setProtocolAddressPermission(address(mockProtocol), "USTB", true);

        // Try to set same value again
        vm.expectRevert(IAllowList.AlreadySet.selector);
        allowList.setProtocolAddressPermission(address(mockProtocol), "USTB", true);

        // Set to false
        allowList.setProtocolAddressPermission(address(mockProtocol), "USTB", false);

        // Try to set to false again
        vm.expectRevert(IAllowList.AlreadySet.selector);
        allowList.setProtocolAddressPermission(address(mockProtocol), "USTB", false);
    }

    function testSetProtocolAddressPermissions() public {
        address[] memory protocols = new address[](2);
        protocols[0] = address(mockProtocol);
        protocols[1] = address(mockProtocol2);

        // Test setting permissions for multiple protocols
        allowList.setProtocolAddressPermissions(protocols, "USTB", true);

        assertEq(allowList.isAddressAllowedForFund(address(mockProtocol), "USTB"), true);
        assertEq(allowList.isAddressAllowedForFund(address(mockProtocol2), "USTB"), true);
        assertEq(allowList.protocolPermissionsForFunds(address(mockProtocol)), 1);
        assertEq(allowList.protocolPermissionsForFunds(address(mockProtocol2)), 1);
    }

    function testSetProtocolAddressPermissionsRevertsForAddressWithEntityId() public {
        address[] memory protocols = new address[](2);
        protocols[0] = address(mockProtocol);
        protocols[1] = bob; // bob will have an entity ID

        allowList.setEntityIdForAddress(IAllowListV2.EntityId.unwrap(bobEntityId), bob);

        vm.expectRevert(IAllowListV2.AddressHasEntityId.selector);
        allowList.setProtocolAddressPermissions(protocols, "USTB", true);
    }

    function testHasAnyProtocolPermissions() public {
        assertEq(allowList.hasAnyProtocolPermissions(address(mockProtocol)), false);

        allowList.setProtocolAddressPermission(address(mockProtocol), "USTB", true);
        assertEq(allowList.hasAnyProtocolPermissions(address(mockProtocol)), true);

        allowList.setProtocolAddressPermission(address(mockProtocol), "USTB", false);
        assertEq(allowList.hasAnyProtocolPermissions(address(mockProtocol)), false);
    }

    function testSetEntityIdRevertsForAddressWithProtocolPermissions() public {
        allowList.setProtocolAddressPermission(address(mockProtocol), "USTB", true);

        vm.expectRevert(IAllowListV2.AddressHasProtocolPermissions.selector);
        allowList.setEntityIdForAddress(IAllowListV2.EntityId.unwrap(bobEntityId), address(mockProtocol));
    }

    function testProtocolPermissionsAndEntityPermissions() public {
        // Test entity permissions work
        allowList.setEntityIdForAddress(IAllowListV2.EntityId.unwrap(bobEntityId), bob);
        allowList.setEntityAllowedForFund(bobEntityId, "USTB", true);
        assertEq(allowList.isAddressAllowedForFund(bob, "USTB"), true);

        // Test protocol permissions work separately
        allowList.setProtocolAddressPermission(address(mockProtocol), "USTB", true);
        assertEq(allowList.isAddressAllowedForFund(address(mockProtocol), "USTB"), true);

        allowList.setProtocolAddressPermission(address(mockProtocol), "USTB", false);
        assertEq(allowList.isAddressAllowedForFund(address(mockProtocol), "USTB"), false);
    }

    function testSetEntityPermissionsAndAddressesRevertsBadData() public {
        address[] memory addrs = new address[](1);
        addrs[0] = bob;
        string[] memory fundSymbols = new string[](2);
        fundSymbols[0] = "USTB";
        fundSymbols[1] = "USCC";
        bool[] memory fundPerms = new bool[](1);
        fundPerms[0] = true;

        vm.expectRevert(IAllowList.BadData.selector);
        allowList.setEntityPermissionsAndAddresses(
            bobEntityId,
            addrs,
            fundSymbols, // length 2
            fundPerms // length 1
        );
    }

    function testSetProtocolAddressPermissionRevertsUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        allowList.setProtocolAddressPermission(address(mockProtocol), "USTB", true);
    }

    function testSetProtocolAddressPermissionsRevertsUnauthorized() public {
        address[] memory protocols = new address[](1);
        protocols[0] = address(mockProtocol);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        allowList.setProtocolAddressPermissions(protocols, "USTB", true);
    }

    function testProtocolAddressPermissionEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IAllowListV2.ProtocolAddressPermissionSet(address(mockProtocol), "USTB", true);
        allowList.setProtocolAddressPermission(address(mockProtocol), "USTB", true);

        vm.expectEmit(true, false, false, true);
        emit IAllowListV2.ProtocolAddressPermissionSet(address(mockProtocol), "USTB", false);
        allowList.setProtocolAddressPermission(address(mockProtocol), "USTB", false);
    }

    function testSetProtocolAddressPermissionsEmitsEvents() public {
        address[] memory protocols = new address[](2);
        protocols[0] = address(mockProtocol);
        protocols[1] = address(mockProtocol2);

        vm.expectEmit(true, false, false, true);
        emit IAllowListV2.ProtocolAddressPermissionSet(address(mockProtocol), "USTB", true);
        vm.expectEmit(true, false, false, true);
        emit IAllowListV2.ProtocolAddressPermissionSet(address(mockProtocol2), "USTB", true);

        allowList.setProtocolAddressPermissions(protocols, "USTB", true);
    }
}
