pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {SuperstateTokenV1} from "src/v1/SuperstateTokenV1.sol";
import {ISuperstateTokenV1} from "src/interfaces/ISuperstateTokenV1.sol";
import {USTBv1} from "src/v1/USTBv1.sol";
import {AllowList} from "src/allowlist/AllowList.sol";
import {IAllowList} from "src/interfaces/allowlist/IAllowList.sol";
import "test/AllowListV2.sol";
import "test/USTBV2.sol";
import "test/TokenTestBase.t.sol";

/*
 * Used as a test base for token upgrades to assert the storage slots and their mappings have been preserved. In cases where
 * they are not preserved, this is known and called out.
*/
abstract contract SuperstateTokenStorageLayoutTestBase is TokenTestBase {
    ProxyAdmin public permsProxyAdmin;
    TransparentUpgradeableProxy public permsProxy;
    IAllowList public perms;
    ProxyAdmin public tokenProxyAdmin;
    TransparentUpgradeableProxy public tokenProxy;

    ISuperstateTokenV1 public oldToken;
    ISuperstateTokenV1 public newToken;
    ISuperstateTokenV1 public currentToken;

    string public oldTokenVersion;
    string public newTokenVersion;

    address public alice = address(10);
    address public bob = address(11);
    address public charlie = address(12);
    address public mallory = address(13);
    uint256 public evePrivateKey = 0x353;
    address public eve; // see setup()

    uint256 public abcEntityId = 1;

    bytes32 internal constant AUTHORIZATION_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public virtual {
        eve = vm.addr(evePrivateKey);

        AllowList permsImplementation = new AllowList(address(this));

        // deploy proxy contract and point it to implementation
        permsProxy = new TransparentUpgradeableProxy(address(permsImplementation), address(this), "");

        // deploy proxy admin contract
        permsProxyAdmin = ProxyAdmin(getAdminAddress(address(permsProxy)));

        // wrap in ABI to support easier calls
        perms = AllowList(address(permsProxy));

        initializeExpectedTokenVersions();
        initializeOldToken();

        // whitelist alice bob, and charlie (so they can tranfer to each other), but not mallory
        IAllowList.Permission memory allowPerms = IAllowList.Permission(true, false, false, false, false, false);

        perms.setEntityIdForAddress(abcEntityId, alice);
        perms.setEntityIdForAddress(abcEntityId, bob);
        address[] memory addrs = new address[](1);
        addrs[0] = charlie;
        perms.setEntityPermissionAndAddresses(abcEntityId, addrs, allowPerms);
    }

    function initializeExpectedTokenVersions() public virtual;

    function initializeOldToken() public virtual;

    function upgradeAndInitializeNewToken() public virtual;

    function eveAuthorization(uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (uint8, bytes32, bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, eve, bob, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", oldToken.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(evePrivateKey, digest);
    }

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

        // bob's allowance from eve is 0
        assertEq(oldToken.allowance(alice, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = oldToken.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature
        oldToken.permit(eve, bob, allowance, expiry, v, r, s);

        // bob's allowance from eve equals allowance
        assertEq(oldToken.allowance(eve, bob), allowance);

        // eve's nonce is incremented
        assertEq(oldToken.nonces(eve), nonce + 1);

        vm.stopPrank();

        currentToken.pause();
        currentToken.accountingPause();
    }

    function loadSlot(uint256 slot) public view returns (bytes32) {
        return vm.load(address(tokenProxy), bytes32(slot));
    }

    function assertStorageLayout(bool hasUpgraded) public {
        assertSuperstateTokenStorageLayout(hasUpgraded);
        assertErc20UpgradeableStorageLayout();
        assertPausableUpgradeableStorageLayout();
        assertOwnable2StepUpgradeableStorageLayout(hasUpgraded);
    }

    function assertSuperstateTokenStorageLayout(bool) public virtual {
        /*
            Note - the following variables are not stored in contract storage, but are rather in-lined
            in the contract's bytecode as a compiler optimization:
                > VERSION
                > AUTHORIZATION_TYPEHASH
                > DOMAIN_TYPEHASH
                > _deprecatedAdmin

            Note - In the upgrade from V1 to V2, we added some fields that would corrupt
            the storage state of `nonces`, `encumberedBalanceOf`, `encumberances`, and `accountingPaused`. This is OK though
            because those features had not been used at the time of V2 deployment. This base implementation
            assumes the memory slots of V2 and beyond, which should be easier for future storage tests. `USTBv2TokenStorageLayoutTests`
            will override this method to check different storage locations depending on whether the upgrade has happened yet.
        */

        // assert nonces (stored in slot 751)
        bytes32 noncesSlot = keccak256(abi.encode(eve, uint256(751)));
        uint256 noncesSlotValue = uint256(vm.load(address(tokenProxy), noncesSlot));
        uint256 expectedNonce = 1;
        assertEq(noncesSlotValue, expectedNonce);

        // assert encumberedBalanceOf (stored in storage slot 752)
        bytes32 encumberedBalanceOfSlot = keccak256(abi.encode(alice, uint256(752)));
        uint256 encumberedBalanceOfSlotValue = uint256(vm.load(address(tokenProxy), encumberedBalanceOfSlot));
        uint256 expectedAliceEncumberedBalanceOf = 5e6;
        assertEq(encumberedBalanceOfSlotValue, expectedAliceEncumberedBalanceOf);

        // assert encumberedBalanceOf from contract method
        assertEq(currentToken.encumberedBalanceOf(alice), expectedAliceEncumberedBalanceOf);

        // assert encumbrances (stored in storage slot 753).
        bytes32 encumberancesOwnerSlot = keccak256(abi.encode(alice, uint256(753)));
        bytes32 encumberancesTakerSlot = keccak256(abi.encode(bob, uint256(encumberancesOwnerSlot)));
        uint256 encumberancesTakerSlotValue = uint256(vm.load(address(tokenProxy), encumberancesTakerSlot));
        assertEq(encumberancesTakerSlotValue, expectedAliceEncumberedBalanceOf);

        // assert encumbrances from contract method
        assertEq(currentToken.encumbrances(alice, bob), expectedAliceEncumberedBalanceOf);

        // assert accountingPaused (storage slot 754)
        uint256 accountingPausedSlotValue = uint256(loadSlot(754));
        assertEq(1, accountingPausedSlotValue);

        // assert accountingPaused from contract method
        assertEq(true, currentToken.accountingPaused());

        // ignore decimals due to being in-lined in bytecode
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

    // assuming V2 and beyond storage slot mappings
    function assertOwnable2StepUpgradeableStorageLayout(bool hasUpgraded) public virtual {}

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

    function testUpgradeStorageLayout() public {
        // do some state manipulation
        // note: not manipulating encumber/nonces to simulate current v1 state
        manipulateStateOldToken();

        // assert storage layout
        assertStorageLayout(false);

        // upgrade to newToken
        upgradeAndInitializeNewToken();

        // assert storage layout
        assertStorageLayout(true);
    }
}
