pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import {SuperstateTokenV1} from "src/v1/SuperstateTokenV1.sol";
import {ISuperstateToken} from "src/interfaces/ISuperstateToken.sol";
import {USTBv1} from "src/v1/USTBv1.sol";
import {AllowList} from "src/AllowList.sol";
import "test/AllowListV2.sol";
import "test/USTBV2.sol";

/**
 * Superstate Token storage layout:
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
 */
abstract contract SuperstateTokenStorageLayoutTestBase is Test {
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public permsProxy;
    AllowList public perms;
    TransparentUpgradeableProxy public tokenProxy;

    ISuperstateToken public oldToken;
    ISuperstateToken public newToken;
    ISuperstateToken public currentToken;

    string public oldTokenVersion;
    string public newTokenVersion;

    address public alice = address(10);
    address public bob = address(11);
    address public charlie = address(12);
    address public mallory = address(13);

    uint256 public abcEntityId = 1;

    function setUp() public virtual {
        AllowList permsImplementation = new AllowList(address(this));

        // deploy proxy admin contract
        proxyAdmin = new ProxyAdmin();

        // deploy proxy contract and point it to implementation
        permsProxy = new TransparentUpgradeableProxy(address(permsImplementation), address(proxyAdmin), "");

        // wrap in ABI to support easier calls
        perms = AllowList(address(permsProxy));

        initializeExpectedTokenVersions();
        initializeOldToken();

        // whitelist alice bob, and charlie (so they can tranfer to each other), but not mallory
        AllowList.Permission memory allowPerms = AllowList.Permission(true, false, false, false, false, false);

        perms.setEntityIdForAddress(abcEntityId, alice);
        perms.setEntityIdForAddress(abcEntityId, bob);
        address[] memory addrs = new address[](1);
        addrs[0] = charlie;
        perms.setEntityPermissionAndAddresses(abcEntityId, addrs, allowPerms);
    }

    function initializeExpectedTokenVersions() public virtual;

    function initializeOldToken() public virtual;

    function upgradeAndInitializeNewToken() public virtual;

    function manipulateStateOldToken() public {
        // availableBalanceOf is 0 by default
        assertEq(oldToken.availableBalanceOf(alice), 0);

        // mint some to alice
        currentToken.mint(alice, 100e6);

        // reflects balance when there are no encumbrances
        vm.startPrank(alice);
        assertEq(oldToken.balanceOf(alice), 100e6);
        assertEq(oldToken.availableBalanceOf(alice), 100e6);

        // is reduced by encumbrances
        oldToken.encumber(bob, 20e6);
        assertEq(oldToken.balanceOf(alice), 100e6);
        assertEq(oldToken.availableBalanceOf(alice), 80e6);

        // is reduced by transfers
        oldToken.transfer(bob, 20e6);
        assertEq(oldToken.balanceOf(alice), 80e6);
        assertEq(oldToken.availableBalanceOf(alice), 60e6);

        vm.stopPrank();

        vm.startPrank(bob);

        // is NOT reduced by transferFrom (from an encumbered address)
        oldToken.transferFrom(alice, charlie, 10e6);
        assertEq(oldToken.balanceOf(alice), 70e6);
        assertEq(oldToken.availableBalanceOf(alice), 60e6);
        assertEq(oldToken.encumbrances(alice, bob), 10e6);
        assertEq(oldToken.balanceOf(charlie), 10e6);

        // is increased by a release
        oldToken.release(alice, 5e6);
        assertEq(oldToken.balanceOf(alice), 70e6);
        assertEq(oldToken.availableBalanceOf(alice), 65e6);
        assertEq(oldToken.encumbrances(alice, bob), 5e6);

        vm.stopPrank();

        currentToken.pause();
        currentToken.accountingPause();
    }

    function loadSlot(uint256 slot) public view returns (bytes32) {
        return vm.load(address(tokenProxy), bytes32(slot));
    }

    function assertStorageLayout() public {
        assertSuperstateTokenStorageLayout();
        assertErc20UpgradeableStorageLayout();
        assertPausableUpgradeableStorageLayout();
        assertOwnable2StepUpgradeableStorageLayout();
    }

    function assertSuperstateTokenStorageLayout() public {
        /*
            Note - the following variables are not stored in contract storage, but are rather in-lined
            in the contract's bytecode as a compiler optimization:
                > VERSION
                > AUTHORIZATION_TYPEHASH
                > DOMAIN_TYPEHASH
                > _deprecatedAdmin
        */

        // assert nonces

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

        // assert decimals
    }

    function assertErc20UpgradeableStorageLayout() public {
        // assert balances storage slot (stored in storage slot 51)
        bytes32 balanceSlot = keccak256(abi.encode(alice, uint256(51)));
        uint256 balanceSlotValue = uint256(vm.load(address(tokenProxy), balanceSlot));
        uint256 expectedAliceBalance = 70e6;
        assertEq(balanceSlotValue, expectedAliceBalance);

        // assert balances from contract method
        assertEq(currentToken.balanceOf(alice), expectedAliceBalance);

        // assert name slot (stored in storage slot 54)
        // note: this is complex due to how strings are stored in solidity. they are dynamic and can potentially take up more than one slot,
        // and so we need to read a pointer to its actual memory location
        uint256 nameSlotData = uint256(keccak256(abi.encode(bytes32(uint256(54)))));

        bytes memory storedData = new bytes(64);
        for (uint256 i = 0; i < storedData.length / 32; i++) {
            bytes32 chunk = loadSlot(nameSlotData + i);
            for (uint256 j = 0; j < 32; j++) {
                storedData[i * 32 + j] = chunk[j];
            }
        }
        bytes memory cleanedStoredData = new bytes(55); // name is 55 bytes
        for (uint256 i = 0; i < cleanedStoredData.length; i++) {
            cleanedStoredData[i] = storedData[i];
        }
        string memory nameSlotValue = string(cleanedStoredData);

        assertEq("Superstate Short Duration US Government Securities Fund", nameSlotValue);

        // assert name slot from contract method
        assertEq(
            "Superstate Short Duration US Government Securities Fund", SuperstateTokenV1(address(tokenProxy)).name()
        );

        // assert symbol slot (stored in storage slot 55)
        // note: ths is simpler than `name` because the value is small and be stored in a single 32 byte slot.
        bytes32 symbolSlot = loadSlot(55);
        assertEq("USTB", bytes32ToString(symbolSlot));

        // assert symbol slot from contract method
        assertEq("USTB", SuperstateTokenV1(address(tokenProxy)).symbol());
    }

    function assertPausableUpgradeableStorageLayout() public {
        // assert _paused stora slot (stored in stora slot 101)
        uint256 pausedSlotValue = uint256(loadSlot(101));
        assertEq(1, pausedSlotValue);
    }

    function assertOwnable2StepUpgradeableStorageLayout() public {}

    function testUpgradeStorageLayout() public {
        // do some state manipulation
        manipulateStateOldToken();

        // assert storage layout
        assertStorageLayout();

        // upgrade to newToken
        upgradeAndInitializeNewToken();

        // assert storage layout
        assertStorageLayout();
    }

    // Helper function to convert bytes32 to a string
    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
}

contract A {
    uint256 public a;
}

contract B {
    uint256 public b;
}

contract TokenV1 is A {
    uint256 public c;
}

contract TokenV2 is A, B {
    uint256 public c;
}

/*
    V1 Storage:
    Slot 0: a
    Slot 1: c

    V2 Storage:
    Slot 0: a
    Slot 1: b (corruption)
    Slot 2: c
*/
