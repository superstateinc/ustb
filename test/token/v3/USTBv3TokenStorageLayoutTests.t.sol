pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {SuperstateTokenV1} from "src/v1/SuperstateTokenV1.sol";
import {ISuperstateTokenV2} from "src/interfaces/ISuperstateTokenV2.sol";
import {SuperstateTokenV2} from "src/v2/SuperstateTokenV2.sol";
import {USTBv2} from "src/v2/USTBv2.sol";
import {AllowList} from "src/allowlist/AllowList.sol";
import {AllowListV1} from "src/allowlist/v1/AllowListV1.sol";
import {IAllowListV2} from "src/interfaces/allowlist/IAllowListV2.sol";
import {SuperstateTokenV3} from "src/v3/SuperstateTokenV3.sol";
import "test/token/SuperstateTokenStorageLayoutTestBase.t.sol";

/**
 *  SuperstateV2 Token storage layout:
 *
 *  Slot 51: ERC20Upgradeable._balances
 *  Slot 52: Erc20Upgradeable._allowances
 *  Slot 53: Erc20Upgradeable._totalSupply
 *  Slot 54: Erc20Upgradeable._name
 *  Slot 55: Erc20Upgradeable._symbol
 *  Slot 101: PausableUpgradeable._paused
 * .Slot 102-150: PausableUpgradeable.__gap
 *  Slot 151: OwnableUpgradeable.__owner
 *  Slot 152-200: OwnableUpgradeable.__gap
 *  Slot 201: Ownable2StepUpgradeable._pendingOwner
 *  Slot 202-250: Ownable2StepUpgradeable.__gap
 * .Slot 251-750: SuperstateToken.__inheritanceGap
 *  Slot 751: SuperstateToken.nonces
 *  Slot 752: SuperstateToken.encumberedBalanceOf
 *  Slot 753: SuperstateToken.encumbrances
 *  Slot 754: SuperstateToken.accountingPaused
 *  Slot 755-854: SuperstateToken.__additionalFieldsGap
 *
 *  SuperstateV3 Token storage layout:
 *
 *  Slot 51: ERC20Upgradeable._balances
 *  Slot 52: Erc20Upgradeable._allowances
 *  Slot 53: Erc20Upgradeable._totalSupply
 *  Slot 54: Erc20Upgradeable._name
 *  Slot 55: Erc20Upgradeable._symbol
 *  Slot 101: PausableUpgradeable._paused
 * .Slot 102-150: PausableUpgradeable.__gap
 *  Slot 151: OwnableUpgradeable.__owner
 *  Slot 152-200: OwnableUpgradeable.__gap
 *  Slot 201: Ownable2StepUpgradeable._pendingOwner
 *  Slot 202-250: Ownable2StepUpgradeable.__gap
 * .Slot 251-750: SuperstateToken.__inheritanceGap
 *  Slot 751: SuperstateToken.nonces
 *  Slot 752: SuperstateToken.encumberedBalanceOf
 *  Slot 753: SuperstateToken.encumbrances
 *  Slot 754: SuperstateToken.accountingPaused
 *  Slot 755: SuperstateToken.maximumOracleDelay
 *  Slot 756: SuperstateToken.superstateOracle
 *  Slot 757: SuperstateToken.supportedStablecoins
 *  Slot 758: SuperstateToken.allowList
 *  Slot 758-854: SuperstateToken.__additionalFieldsGap
 */
contract USTBv3TokenStorageLayoutTests is SuperstateTokenStorageLayoutTestBase {
    AllowList permsV2;
    ProxyAdmin permsProxyAdminV2;
    TransparentUpgradeableProxy permsProxyV2;

    function initializeExpectedTokenVersions() public override {
        oldTokenVersion = "2";
        newTokenVersion = "3";
    }

    function initializeOldToken() public override {
        USTBv1 oldTokenImplementation = new USTBv1(address(this), AllowListV1(address(perms)));
        tokenProxy = new TransparentUpgradeableProxy(address(oldTokenImplementation), address(this), "");
        tokenProxyAdmin = ProxyAdmin(getAdminAddress(address(tokenProxy)));

        // wrap in ABI to support easier calls
        oldToken = USTBv1(address(tokenProxy));

        oldToken.initialize("Superstate Short Duration US Government Securities Fund", "USTB");

        USTBv2 oldTokenImplementationV2 = new USTBv2(address(this), AllowListV1(address(perms)));
        tokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenProxy)), address(oldTokenImplementationV2), ""
        );

        // wrap in ABI to support easier calls
        oldToken = USTBv2(address(tokenProxy));

        ISuperstateTokenV2(address(oldToken)).initializeV2();

        currentToken = oldToken;
    }

    function upgradeAndInitializeNewToken() public override {
        // In preparation for token v3, create and deploy AllowListV2
        AllowList permsImplementationV2 = new AllowList();

        permsProxyV2 = new TransparentUpgradeableProxy(address(permsImplementationV2), address(this), "");
        permsProxyAdminV2 = ProxyAdmin(getAdminAddress(address(permsProxyV2)));
        permsV2 = AllowList(address(permsProxyV2));

        // Initialize AllowListV2
        permsV2.initialize();

        // Re-populate AllowList state
        address[] memory addrsToSet = new address[](2);
        addrsToSet[0] = alice;
        addrsToSet[1] = bob;
        string[] memory fundsToSet = new string[](1);
        fundsToSet[0] = "USTB";
        bool[] memory fundPermissionsToSet = new bool[](1);
        fundPermissionsToSet[0] = true;
        permsV2.setEntityPermissionsAndAddresses(
            IAllowListV2.EntityId.wrap(abcEntityId), addrsToSet, fundsToSet, fundPermissionsToSet
        );

        // Now upgrade to V3
        SuperstateTokenV3 newTokenImplementation = new SuperstateTokenV3();
        tokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenProxy)), address(newTokenImplementation), ""
        );

        /*
            At this point, owner() is 0x00 because the upgraded contract has not
            initialized.

            admin() is the same from the prior version of the contract
        */

        // Initialize tokenV3

        newToken = SuperstateTokenV3(address(tokenProxy));
        currentToken = newToken;

        SuperstateTokenV3(address(tokenProxy)).initializeV3(permsV2);
    }

    function assertSuperstateTokenStorageLayout(bool hasUpgraded) public override {
        super.assertSuperstateTokenStorageLayout(hasUpgraded);

        if (hasUpgraded) {
            bytes32 maximumOracleDelaySlot = keccak256(abi.encode(eve, uint256(755)));
            uint256 maximumOracleDelaySlotValue = uint256(vm.load(address(tokenProxy), maximumOracleDelaySlot));
            uint256 expectedMaximumOracleDelayValue = 0;
            assertEq(maximumOracleDelaySlotValue, expectedMaximumOracleDelayValue);

            bytes32 superstateOracleSlot = keccak256(abi.encode(eve, uint256(756)));
            uint256 superstateOracleSlotValue = uint256(vm.load(address(tokenProxy), superstateOracleSlot));
            uint256 expectedSuperstateOracleValue = 0;
            assertEq(superstateOracleSlotValue, expectedSuperstateOracleValue);

            bytes32 supportedStablecoinsSlot = keccak256(abi.encode(eve, uint256(757)));
            uint256 supportedStablecoinsSlotValue = uint256(vm.load(address(tokenProxy), supportedStablecoinsSlot));
            uint256 expectedSupportedStablecoinsValue = 0;
            assertEq(supportedStablecoinsSlotValue, expectedSupportedStablecoinsValue);
        }
    }

    function assertOwnable2StepUpgradeableStorageLayout(bool) public override {
        // V2 and V3 does support this field, and the __owner is set within `upgradeAndInitializeNewToken`

        // assert __owner (stored in storage slot 151)
        address ownerSlotValue = address(uint160(uint256(loadSlot(151))));
        address expectedOwner = address(this);
        assertEq(ownerSlotValue, expectedOwner);

        // assert __owner from contract method
        assertEq(SuperstateTokenV2(address(currentToken)).owner(), expectedOwner);

        // assert _pendingOwner (storage slot 201)
        address pendingOwnerSlotValue = address(uint160(uint256(loadSlot(201))));
        address expectedPendingOwner = address(0x0);
        assertEq(pendingOwnerSlotValue, expectedPendingOwner);

        // assert _pendingOwner from contract methods
        assertEq(SuperstateTokenV2(address(currentToken)).pendingOwner(), expectedPendingOwner);
    }
}
