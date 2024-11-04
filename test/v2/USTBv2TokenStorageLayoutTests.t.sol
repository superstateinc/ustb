pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {SuperstateTokenV1} from "src/v1/SuperstateTokenV1.sol";
import {ISuperstateTokenV2} from "src/interfaces/ISuperstateTokenV2.sol";
import {SuperstateTokenV2} from "src/v2/SuperstateTokenV2.sol";
import {USTBv1} from "src/v1/USTBv1.sol";
import {USTBv2} from "src/v2/USTBv2.sol";
import {AllowList} from "src/allowlist/AllowList.sol";
import "test/AllowListV2.sol";
import "test/USTBV2.sol";
import "test/SuperstateTokenStorageLayoutTestBase.t.sol";

/**
 *  SuperstateV1 Token storage layout:
 *
 *  Slot 51: ERC20Upgradeable._balances
 *  Slot 52: Erc20Upgradeable._allowances
 *  Slot 53: Erc20Upgradeable._totalSupply
 *  Slot 54: Erc20Upgradeable._name
 *  Slot 55: Erc20Upgradeable._symbol
 *  Slot 101: PausableUpgradeable._paused
 *  Slot 151: SuperstateToken.nonces
 *  Slot 152: SuperstateToken.encumberedBalanceOf
 *  Slot 153: SuperstateToken.encumbrances
 *  Slot 154: SuperstateToken.accountingPaused
 *
 *
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
 */
contract USTBv2TokenStorageLayoutTests is SuperstateTokenStorageLayoutTestBase {
    function initializeExpectedTokenVersions() public override {
        oldTokenVersion = "1";
        newTokenVersion = "2";
    }

    function initializeOldToken() public override {
        USTBv1 oldTokenImplementation = new USTBv1(address(this), perms);
        tokenProxy = new TransparentUpgradeableProxy(address(oldTokenImplementation), address(this), "");
        tokenProxyAdmin = ProxyAdmin(getAdminAddress(address(tokenProxy)));

        // wrap in ABI to support easier calls
        oldToken = USTBv1(address(tokenProxy));

        oldToken.initialize("Superstate Short Duration US Government Securities Fund", "USTB");

        currentToken = USTBv1(address(tokenProxy));
    }

    function upgradeAndInitializeNewToken() public override {
        // Now upgrade to V2
        USTBv2 newTokenImplementation = new USTBv2(address(this), perms);
        tokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenProxy)), address(newTokenImplementation), ""
        );

        /*
            At this point, owner() is 0x00 because the upgraded contract has not
            initialized.

            admin() is the same from the prior version of the contract
        */

        // initialize v2 of the contract, specifically the new authorization
        // mechanism via owner()
        newToken = USTBv2(address(tokenProxy));
        SuperstateTokenV2(address(newToken)).initializeV2();

        currentToken = newToken;
    }

    function assertOwnable2StepUpgradeableStorageLayout(bool hasUpgraded) public override {
        if (hasUpgraded) {
            // V2 does support this field, and the __owner is set within `upgradeAndInitializeNewToken`

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
        } else {
            // V1 did not support this field, and so ignoring
        }
    }

    // See note in `SuperstateTokenStorageLayoutTestBase` to see why this is being overwritten
    function assertSuperstateTokenStorageLayout(bool hasUpgraded) public override {
        if (hasUpgraded) {
            // V2 storage layout, ignore encumberances/nonces/accountingPaused as they are corrupted (this is known and accepted)
        } else {
            // V1 storage layout

            // assert nonces (stored in storage slot 151)
            bytes32 noncesSlot = keccak256(abi.encode(eve, uint256(151)));
            uint256 noncesSlotValue = uint256(vm.load(address(tokenProxy), noncesSlot));
            uint256 expectedNonce = 1;
            assertEq(noncesSlotValue, expectedNonce);

            // assert nonces from contract method
            assertEq(currentToken.nonces(eve), 1);

            // assert encumberedBalanceOf (stored in storage slot 152)
            bytes32 encumberedBalanceOfSlot = keccak256(abi.encode(alice, uint256(152)));
            uint256 encumberedBalanceOfSlotValue = uint256(vm.load(address(tokenProxy), encumberedBalanceOfSlot));
            uint256 expectedAliceEncumberedBalanceOf = 5e6;
            assertEq(encumberedBalanceOfSlotValue, expectedAliceEncumberedBalanceOf);

            // assert encumberedBalanceOf from contract method
            assertEq(currentToken.encumberedBalanceOf(alice), expectedAliceEncumberedBalanceOf);

            // assert encumbrances (stored in storage slot 153).
            bytes32 encumberancesOwnerSlot = keccak256(abi.encode(alice, uint256(153)));
            bytes32 encumberancesTakerSlot = keccak256(abi.encode(bob, uint256(encumberancesOwnerSlot)));
            uint256 encumberancesTakerSlotValue = uint256(vm.load(address(tokenProxy), encumberancesTakerSlot));
            assertEq(encumberancesTakerSlotValue, expectedAliceEncumberedBalanceOf);

            // assert encumbrances from contract method
            assertEq(currentToken.encumbrances(alice, bob), expectedAliceEncumberedBalanceOf);

            // assert accountingPaused (storage slot 154)
            uint256 accountingPausedSlotValue = uint256(loadSlot(154));
            assertEq(1, accountingPausedSlotValue);

            // assert accountingPaused from contract method
            assertEq(true, currentToken.accountingPaused());

            // ignore decimals due to being in-lined in bytecode
        }
    }
}
