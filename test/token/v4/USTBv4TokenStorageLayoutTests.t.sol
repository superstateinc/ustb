pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {SuperstateTokenV1} from "src/v1/SuperstateTokenV1.sol";
import {ISuperstateTokenV2} from "src/interfaces/ISuperstateTokenV2.sol";
import {ISuperstateTokenV3} from "src/interfaces/ISuperstateTokenV3.sol";
import {SuperstateTokenV2} from "src/v2/SuperstateTokenV2.sol";
import {USTBv2} from "src/v2/USTBv2.sol";
import {AllowList} from "src/allowlist/AllowList.sol";
import {AllowListV1} from "src/allowlist/v1/AllowListV1.sol";
import {IAllowListV2} from "src/interfaces/allowlist/IAllowListV2.sol";
import {SuperstateTokenV3} from "src/v3/SuperstateTokenV3.sol";
import {SuperstateToken} from "src/SuperstateToken.sol";
import "test/token/SuperstateTokenStorageLayoutTestBaseV4Plus.t.sol";

import {console} from "forge-std/console.sol";


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
 *  Slot 758: SuperstateToken.allowListV2
 *  Slot 758-854: SuperstateToken.__additionalFieldsGap
 *
 *  SuperstateV4 Token storage layout:
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
 *  Slot 752: SuperstateToken._deprecatedEncumberedBalanceOf
 *  Slot 753: SuperstateToken._deprecatedEncumbrances
 *  Slot 754: SuperstateToken.accountingPaused
 *  Slot 755: SuperstateToken.maximumOracleDelay
 *  Slot 756: SuperstateToken.superstateOracle
 *  Slot 757: SuperstateToken.supportedStablecoins
 *  Slot 758: SuperstateToken.allowListV2
 *  Slot 759: SuperstateToken.redemptionContract
 *  Slot 759-854: SuperstateToken.__additionalFieldsGap
 */

contract USTBv4TokenStorageLayoutTests is SuperstateTokenStorageLayoutTestBaseV4Plus {
    AllowList permsV2;
    ProxyAdmin permsProxyAdminV2;
    TransparentUpgradeableProxy permsProxyV2;

    address public constant MAINNET_REDEMPTION_IDLE = 0x4c21B7577C8FE8b0B0669165ee7C8f67fa1454Cf;


    function initializeExpectedTokenVersions() public override {
        oldTokenVersion = "3";
        newTokenVersion = "4";
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

        currentToken = ISuperstateToken(address(oldToken));

        // In preparation for token v3, create and deploy AllowListV2
        AllowList permsImplementationV2 = new AllowList();

        permsProxyV2 = new TransparentUpgradeableProxy(address(permsImplementationV2), address(this), "");
        permsProxyAdminV2 = ProxyAdmin(getAdminAddress(address(permsProxyV2)));
        permsV2 = AllowList(address(permsProxyV2));

        // Initialize AllowListV2
        permsV2.initialize();

        // Re-populate AllowList state
        address[] memory addrsToSet = new address[](3);
        addrsToSet[0] = alice;
        addrsToSet[1] = bob;
        addrsToSet[2] = charlie;
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

        newToken = ISuperstateToken(address(tokenProxy));
        currentToken = newToken;

        SuperstateTokenV3(address(tokenProxy)).initializeV3(permsV2);
    }

    function upgradeAndInitializeNewToken() public override {
        SuperstateToken newTokenImplementation = new SuperstateToken();
        tokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenProxy)), address(newTokenImplementation), ""
        );

        newToken = SuperstateToken(address(tokenProxy));
        currentToken = newToken;

        SuperstateToken(address(tokenProxy)).setRedemptionContract(MAINNET_REDEMPTION_IDLE);
    }

    function assertSuperstateTokenStorageLayout(bool hasUpgraded) public override {
        super.assertSuperstateTokenStorageLayout(hasUpgraded);

        uint256 allowlistV2ContractSlotValue = uint256(loadSlot(758));
        uint256 expectedAllowlistV2ContractSlotValue = uint256(uint160(address(permsV2)));
        assertEq(allowlistV2ContractSlotValue, expectedAllowlistV2ContractSlotValue);

        uint256 maximumOracleDelaySlotValue = uint256(loadSlot(755));
        uint256 expectedMaximumOracleDelayValue = 0;
        assertEq(maximumOracleDelaySlotValue, expectedMaximumOracleDelayValue);

        uint256 superstateOracleSlotValue = uint256(loadSlot(756));
        uint256 expectedSuperstateOracleValue = 0;
        assertEq(superstateOracleSlotValue, expectedSuperstateOracleValue);

        bytes32 supportedStablecoinsSlot = keccak256(abi.encode(eve, uint256(757))); // address should be usdc instead of eve
        uint256 supportedStablecoinsSlotValue = uint256(vm.load(address(tokenProxy), supportedStablecoinsSlot));
        uint256 expectedSupportedStablecoinsValue = 0;
        assertEq(supportedStablecoinsSlotValue, expectedSupportedStablecoinsValue);

        if (!hasUpgraded) {
            // should be zero'ed before upgrade
            uint256 redemptionContractContractSlotValue = uint256(loadSlot(759));
            uint256 expectedRedemptionContractSlotValue = 0;
            assertEq(redemptionContractContractSlotValue, expectedRedemptionContractSlotValue);
        } else {
            uint256 redemptionContractContractSlotValue = uint256(loadSlot(759));
            uint256 expectedRedemptionContractSlotValue = uint256(uint160(MAINNET_REDEMPTION_IDLE));
            assertEq(redemptionContractContractSlotValue, expectedRedemptionContractSlotValue);
        }
    }

    // verbatim from old version
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
