pragma solidity ^0.8.20;

import "forge-std/StdUtils.sol";
import { Test } from "forge-std/Test.sol";
import { PausableUpgradeable } from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import { SUPTB } from "src/SUPTB.sol";
import { PermissionList } from "src/PermissionList.sol";
import "test/PermissionListV2.sol";
import "test/SUPTBV2.sol";

contract SUPTBTest is Test {
    event Encumber(address indexed owner, address indexed taker, uint256 amount);
    event Release(address indexed owner, address indexed taker, uint256 amount);
    event EncumbranceSpend(address indexed owner, address indexed taker, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed minter, address indexed to, uint256 amount);
    event Burn(address indexed burner, uint256 amount);

    TransparentUpgradeableProxy permsProxy;
    ProxyAdmin permsAdmin;

    PermissionList public perms;

    TransparentUpgradeableProxy tokenProxy;
    ProxyAdmin tokenAdmin;

    SUPTB public token;

    // Storage slot with the admin of the contract.
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address alice = address(10);
    address bob = address(11);
    address charlie = address(12);
    address mallory = address(13);
    uint256 evePrivateKey = 0x353;
    address eve; // see setup()

    bytes32 internal constant AUTHORIZATION_TYPEHASH = keccak256("Authorization(address owner,address spender,uint256 amount,uint256 nonce,uint256 expiry)");

    function setUp() public {
        eve = vm.addr(evePrivateKey);

        PermissionList permsImplementation = new PermissionList(address(this));

        // deploy proxy contract and point it to implementation
        permsProxy = new TransparentUpgradeableProxy(address(permsImplementation), address(this), "");

        bytes32 permsAdminAddress = vm.load(address(permsProxy), ADMIN_SLOT);
        permsAdmin = ProxyAdmin(address(uint160(uint256(permsAdminAddress))));

        // wrap in ABI to support easier calls
        perms = PermissionList(address(permsProxy));

        SUPTB tokenImplementation = new SUPTB(address(this), perms);

        // repeat for the token contract
        tokenProxy = new TransparentUpgradeableProxy(address(tokenImplementation), address(this), "");

        bytes32 tokenAdminAddress = vm.load(address(tokenProxy), ADMIN_SLOT);
        tokenAdmin = ProxyAdmin(address(uint160(uint256(tokenAdminAddress))));

        // wrap in ABI to support easier calls
        token = SUPTB(address(tokenProxy));

        // initialize token contract
        token.initialize("Superstate Short-Term Government Securities Fund", "SUPTB");

        // whitelist alice bob, and charlie (so they can tranfer to each other), but not mallory
        PermissionList.Permission memory allowPerms = PermissionList.Permission(true, false, false, false, false, false);
        perms.setPermission(alice, allowPerms);
        perms.setPermission(bob, allowPerms);
        perms.setPermission(charlie, allowPerms);
    }

    function testTokenName() public {
        assertEq(token.name(), "Superstate Short-Term Government Securities Fund");
    }

    function testTokenSymbol() public {
        assertEq(token.symbol(), "SUPTB");
    }

    function testTokenDecimals() public {
        assertEq(token.decimals(), 6);
    }

    function testInitializeRevertIfCalledAgain() public {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        token.initialize("new name", "new symbol");
    }

    function testAvailableBalanceOf() public {
        vm.startPrank(alice);

        // availableBalanceOf is 0 by default
        assertEq(token.availableBalanceOf(alice), 0);

        // reflects balance when there are no encumbrances
        deal(address(token), alice, 100e6);
        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 100e6);

        // is reduced by encumbrances
        token.encumber(bob, 20e6);
        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 80e6);

        // is reduced by transfers
        token.transfer(bob, 20e6);
        assertEq(token.balanceOf(alice), 80e6);
        assertEq(token.availableBalanceOf(alice), 60e6);

        vm.stopPrank();

        vm.startPrank(bob);

        // is NOT reduced by transferFrom (from an encumbered address)
        token.transferFrom(alice, charlie, 10e6);
        assertEq(token.balanceOf(alice), 70e6);
        assertEq(token.availableBalanceOf(alice), 60e6);
        assertEq(token.encumbrances(alice, bob), 10e6);
        assertEq(token.balanceOf(charlie), 10e6);

        // is increased by a release
        token.release(alice, 5e6);
        assertEq(token.balanceOf(alice), 70e6);
        assertEq(token.availableBalanceOf(alice), 65e6);
        assertEq(token.encumbrances(alice, bob), 5e6);

        vm.stopPrank();
    }

    function testTransferRevertInsufficentBalance() public {
        deal(address(token), alice, 100e6);
        vm.startPrank(alice);

        // alice encumbers half her balance to charlie
        token.encumber(charlie, 50e6);

        // alice attempts to transfer her entire balance
        vm.expectRevert(SUPTB.InsufficientAvailableBalance.selector);
        token.transfer(bob, 100e6);

        vm.stopPrank();
    }

    function testEncumberRevert() public {
        deal(address(token), alice, 100e6);
        vm.startPrank(alice);

        // alice encumbers half her balance to bob
        token.encumber(bob, 50e6);

        // alice attempts to encumber more than her remaining available balance
        vm.expectRevert(SUPTB.InsufficientAvailableBalance.selector);
        token.encumber(charlie, 60e6);

        vm.stopPrank();
    }

    function testEncumber() public {
        deal(address(token), alice, 100e6);
        vm.startPrank(alice);

        // emits Encumber event
        vm.expectEmit(true, true, true, true);
        emit Encumber(alice, bob, 60e6);

        // alice encumbers some of her balance to bob
        token.encumber(bob, 60e6);

        // balance is unchanged
        assertEq(token.balanceOf(alice), 100e6);
        // available balance is reduced
        assertEq(token.availableBalanceOf(alice), 40e6);

        // creates encumbrance for taker
        assertEq(token.encumbrances(alice, bob), 60e6);

        // updates encumbered balance of owner
        assertEq(token.encumberedBalanceOf(alice), 60e6);
    }

    function testTransferFromSufficientEncumbrance() public {
        deal(address(token), alice, 100e6);
        vm.prank(alice);

        // alice encumbers some of her balance to bob
        token.encumber(bob, 60e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 40e6);
        assertEq(token.encumberedBalanceOf(alice), 60e6);
        assertEq(token.encumbrances(alice, bob), 60e6);
        assertEq(token.balanceOf(charlie), 0);

        // bob calls transfers from alice to charlie
        vm.prank(bob);
        token.transferFrom(alice, charlie, 40e6);

        // alice balance is reduced
        assertEq(token.balanceOf(alice), 60e6);
        // alice encumbrance to bob is reduced
        assertEq(token.availableBalanceOf(alice), 40e6);
        assertEq(token.encumberedBalanceOf(alice), 20e6);
        assertEq(token.encumbrances(alice, bob), 20e6);
        // transfer is completed
        assertEq(token.balanceOf(charlie), 40e6);
    }

    function testTransferFromEncumbranceAndAllowance() public {
        deal(address(token), alice, 100e6);
        vm.startPrank(alice);

        // alice encumbers some of her balance to bob
        token.encumber(bob, 20e6);

        // she also grants him an approval
        token.approve(bob, 30e6);

        vm.stopPrank();

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 80e6);
        assertEq(token.encumberedBalanceOf(alice), 20e6);
        assertEq(token.encumbrances(alice, bob), 20e6);
        assertEq(token.allowance(alice, bob), 30e6);
        assertEq(token.balanceOf(charlie), 0);

        // bob calls transfers from alice to charlie
        vm.prank(bob);
        token.transferFrom(alice, charlie, 40e6);

        // alice balance is reduced
        assertEq(token.balanceOf(alice), 60e6);

        // her encumbrance to bob has been fully spent
        assertEq(token.availableBalanceOf(alice), 60e6);
        assertEq(token.encumberedBalanceOf(alice), 0);
        assertEq(token.encumbrances(alice, bob), 0);

        // her allowance to bob has been partially spent
        assertEq(token.allowance(alice, bob), 10e6);

        // the dst receives the transfer
        assertEq(token.balanceOf(charlie), 40e6);
    }

    function testTransferFromInsufficientAllowance() public {
        deal(address(token), alice, 100e6);

        uint256 encumberedAmount = 10e6;
        uint256 approvedAmount = 20e6;
        uint256 transferAmount = 40e6;

        vm.startPrank(alice);

        // alice encumbers some of her balance to bob
        token.encumber(bob, encumberedAmount);

        // she also grants him an approval
        token.approve(bob, approvedAmount);

        vm.stopPrank();

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 90e6);
        assertEq(token.encumberedBalanceOf(alice), 10e6);
        assertEq(token.encumbrances(alice, bob), encumberedAmount);
        assertEq(token.allowance(alice, bob), approvedAmount);
        assertEq(token.balanceOf(charlie), 0);

        // bob tries to transfer more than his encumbered and allowed balances
        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, charlie, transferAmount);
    }

    function testEncumberFromInsufficientAllowance() public {
        deal(address(token), alice, 100e6);

        // alice grants bob an approval
        vm.prank(alice);
        token.approve(bob, 50e6);

        // but bob tries to encumber more than his allowance
        vm.prank(bob);
        vm.expectRevert();
        token.encumberFrom(alice, charlie, 60e6);
    }

    function testEncumberFrom() public {
        deal(address(token), alice, 100e6);

        // alice grants bob an approval
        vm.prank(alice);
        token.approve(bob, 100e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 100e6);
        assertEq(token.encumberedBalanceOf(alice), 0e6);
        assertEq(token.encumbrances(alice, bob), 0e6);
        assertEq(token.allowance(alice, bob), 100e6);
        assertEq(token.balanceOf(charlie), 0);

        // bob encumbers part of his allowance from alice to charlie
        vm.prank(bob);
        // emits an Encumber event
        vm.expectEmit(true, true, true, true);
        emit Encumber(alice, charlie, 60e6);
        token.encumberFrom(alice, charlie, 60e6);

        // no balance is transferred
        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.balanceOf(charlie), 0);
        // but available balance is reduced
        assertEq(token.availableBalanceOf(alice), 40e6);
        // encumbrance to charlie is created
        assertEq(token.encumberedBalanceOf(alice), 60e6);
        assertEq(token.encumbrances(alice, bob), 0e6);
        assertEq(token.encumbrances(alice, charlie), 60e6);
        // allowance is partially spent
        assertEq(token.allowance(alice, bob), 40e6);
    }

    function testRelease() public {
        deal(address(token), alice, 100e6);

        vm.prank(alice);

        // alice encumbers her balance to bob
        token.encumber(bob, 100e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 0);
        assertEq(token.encumberedBalanceOf(alice), 100e6);
        assertEq(token.encumbrances(alice, bob), 100e6);

        // bob releases part of the encumbrance
        vm.prank(bob);
        // emits Release event
        vm.expectEmit(true, true, true, true);
        emit Release(alice, bob, 40e6);
        token.release(alice, 40e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 40e6);
        assertEq(token.encumberedBalanceOf(alice), 60e6);
        assertEq(token.encumbrances(alice, bob), 60e6);
    }

    function testReleaseInsufficientEncumbrance() public {
        deal(address(token), alice, 100e6);

        vm.prank(alice);

        // alice encumbers her entire balance to bob
        token.encumber(bob, 100e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 0);
        assertEq(token.encumberedBalanceOf(alice), 100e6);
        assertEq(token.encumbrances(alice, bob), 100e6);

        // bob releases a greater amount than is encumbered to him
        vm.prank(bob);
        vm.expectRevert(SUPTB.InsufficientEncumbrance.selector);
        token.release(alice, 200e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 0);
        assertEq(token.encumberedBalanceOf(alice), 100e6);
        assertEq(token.encumbrances(alice, bob), 100e6);
    }

    function testMint() public {
        // emits transfer and mint events
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, 100e6);
        vm.expectEmit();
        emit Mint(address(this), alice, 100e6);

        token.mint(alice, 100e6);
        assertEq(token.balanceOf(alice), 100e6);
    }

    function testMintRevertBadCaller() public {
        vm.prank(alice);
        vm.expectRevert(SUPTB.Unauthorized.selector);
        token.mint(bob, 100e6);

        assertEq(token.balanceOf(bob), 0);
    }

    function testMintRevertInsufficientPermissions() public {
        // cannot mint to Mallory since un-whitelisted
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        token.mint(mallory, 100e6);
    }

    function testBurn() public {
        deal(address(token), alice, 100e6);

        assertEq(token.balanceOf(alice), 100e6);

       // emits Transfer and Burn events
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 100e6);
        vm.expectEmit();
        emit Burn(alice, 100e6);

        token.burn(alice, 100e6);
        assertEq(token.balanceOf(alice), 0);
    }

    function testSelfBurnUsingTransfer() public {
        deal(address(token), alice, 100e6);

        assertEq(token.balanceOf(alice), 100e6);

        // emits Transfer and Burn events
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 50e6);
        vm.expectEmit();
        emit Burn(alice, 50e6);

        // alice calls transfer(0, amount) to self-burn
        vm.prank(alice);
        token.transfer(address(0), 50e6);

        assertEq(token.balanceOf(alice), 50e6);
    }

    function testSelfBurnUsingTransferFrom() public {
        deal(address(token), alice, 100e6);

        assertEq(token.balanceOf(alice), 100e6);

        vm.prank(alice);
        token.approve(bob, 50e6);

        // emits Transfer and Burn events
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 50e6);
        vm.expectEmit();
        emit Burn(alice, 50e6);

        // bob calls transferFrom(alice, 0, amount) to self-burn
        vm.prank(bob);
        token.transferFrom(alice, address(0), 50e6);

        assertEq(token.balanceOf(alice), 50e6);
        assertEq(token.allowance(alice, bob), 0e6);
    }

    function testBurnRevertBadCaller() public {
        vm.prank(alice);
        vm.expectRevert(SUPTB.Unauthorized.selector);
        token.burn(bob, 100e6);
    }

    function testBurnRevertInsufficientBalance() public {
        deal(address(token), alice, 100e6);

        // alice encumbers half her balance to bob
        vm.prank(alice);
        token.encumber(bob, 50e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 50e6);
        assertEq(token.encumberedBalanceOf(alice), 50e6);
        assertEq(token.encumbrances(alice, bob), 50e6);

        // alice tries to burn more than her available balance
        vm.expectRevert(SUPTB.InsufficientAvailableBalance.selector);
        token.burn(alice, 60e6);
    }

    function testEncumberRevertOwnerInsufficientPermissions() public {
        deal(address(token), mallory, 100e6);
        vm.startPrank(mallory);

        // mallory tries to encumber to bob, without being whitelisted
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        token.encumber(bob, 50e6);

        vm.stopPrank();
    }

    function testEncumberFromRevertOwnerInsufficientPermissions() public {
        deal(address(token), mallory, 100e6);

        // mallory grants bob an approval
        vm.prank(mallory);
        token.approve(bob, 50e6);

        // bob tries to encumber to charlie on behalf of mallory, but mallory isn't whitelisted
        vm.prank(bob);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        token.encumberFrom(mallory, charlie, 30e6);
    }

    function testTransferRevertSenderInsufficientPermissions() public {
        deal(address(token), mallory, 100e6);

        // mallory tries to transfer tokens, but isn't whitelisted
        vm.prank(mallory);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        token.transfer(charlie, 30e6);
    }

    function testTransferRevertReceiverInsufficientPermissions() public {
        deal(address(token), alice, 100e6);

        // alice tries to transfer tokens to mallory, but mallory isn't whitelisted
        vm.prank(alice);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        token.transfer(mallory, 30e6);
    }

    function testTransferFromRevertReceiverInsufficientPermissions() public {
        deal(address(token), alice, 100e6);

        // alice grants bob an approval
        vm.prank(alice);
        token.approve(bob, 50e6);

        // bob tries to transfer alice's tokens to mallory, but mallory isn't whitelisted
        vm.prank(bob);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        token.transferFrom(alice, mallory, 50e6);
    }

    function testTransferFromWorksIfUsingEncumbranceAndSourceIsNotWhitelisted() public {
        deal(address(token), mallory, 100e6);

        // whitelist mallory for setting encumbrances
        PermissionList.Permission memory allowPerms = PermissionList.Permission(true, false, false, false, false, false);
        perms.setPermission(mallory, allowPerms);

        vm.startPrank(mallory);
        token.encumber(bob, 20e6);
        token.approve(bob, 10e6);
        vm.stopPrank();

        // now un-whitelist mallory
        PermissionList.Permission memory forbidPerms = PermissionList.Permission(false, false, false, false, false, false);
        perms.setPermission(mallory, forbidPerms);

        // bob can transferFrom now-un-whitelisted mallory by spending her encumbrance to him, without issues
        vm.prank(bob);
        token.transferFrom(mallory, alice, 30e6);

        assertEq(token.balanceOf(mallory), 70e6);
        assertEq(token.balanceOf(alice), 30e6);
        assertEq(token.balanceOf(bob), 0e6);
        assertEq(token.encumbrances(mallory, bob), 0e6);
    }

    function testTransferFromRevertsIfNotUsingEncumbrancesAndSourceNotWhitelisted() public {
        deal(address(token), mallory, 100e6);

        vm.prank(mallory);
        token.approve(bob, 50e6);

        // reverts because encumbrances[src][bob] == 0 and src (mallory) is not whitelisted
        vm.prank(bob);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        token.transferFrom(mallory, alice, 10e6);
    }

    function testTransfersAndEncumbersRevertIfUnwhitelisted() public {
        deal(address(token), alice, 100e6);
        deal(address(token), bob, 100e6);

        // un-whitelist alice
        PermissionList.Permission memory disallowPerms = PermissionList.Permission(false, false, false, false, false, false);
        perms.setPermission(alice, disallowPerms);

        // alice can't transfer tokens to a whitelisted address
        vm.prank(alice);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        token.transfer(bob, 30e6);

        // whitelisted addresses can't transfer tokens to alice
        vm.prank(bob);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        token.transfer(alice, 30e6);

        vm.prank(bob);
        token.approve(charlie, 50e6);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        vm.prank(charlie);
        token.transferFrom(bob, alice, 30e6);

        // alice can't encumber tokens to anyone
        vm.prank(alice);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        token.encumber(bob, 30e6);

        // others can't encumber alice's tokens, even if she's approved them
        vm.prank(alice);
        token.approve(bob, 50e6);
        vm.prank(bob);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        token.encumberFrom(alice, charlie, 30e6);
    }

    function testPauseAndUnpauseRevertIfUnauthorized() public {
        // try pausing contract from unauthorized sender
        vm.prank(charlie);
        vm.expectRevert(SUPTB.Unauthorized.selector);
        token.pause();

        // admin pauses the contract
        token.pause();

        // try unpausing contract from unauthorized sender
        vm.prank(charlie);
        vm.expectRevert(SUPTB.Unauthorized.selector);
        token.unpause();
    }

    function testCannotUpdateBalancesIfTokenPaused() public {
        token.mint(alice, 100e6);

        token.pause();

        assertEq(token.balanceOf(alice), 100e6);

        vm.expectRevert(bytes("Pausable: paused"));
        token.mint(alice, 100e6);

        vm.expectRevert(bytes("Pausable: paused"));
        token.burn(alice, 100e6);

        vm.prank(alice);
        vm.expectRevert(bytes("Pausable: paused"));
        token.transfer(bob, 50e6);

        vm.prank(alice);
        vm.expectRevert(bytes("Pausable: paused"));
        token.encumber(bob, 50e6);

        vm.prank(bob);
        vm.expectRevert(bytes("Pausable: paused"));
        token.transferFrom(alice, charlie, 50e6);

        vm.prank(bob);
        vm.expectRevert(bytes("Pausable: paused"));
        token.encumberFrom(alice, charlie, 50e6);

        vm.prank(bob);
        vm.expectRevert(bytes("Pausable: paused"));
        token.release(alice, 50e6);

        assertEq(token.balanceOf(alice), 100e6);
    }

    function testUpgradingPermissionListDoesNotAffectToken() public {
        PermissionListV2 permsV2Implementation = new PermissionListV2(address(this));
        permsAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(permsProxy)), address(permsV2Implementation), "");

        PermissionListV2 permsV2 = PermissionListV2(address(permsProxy));

        assertEq(address(token.permissionList()), address(permsProxy));

        // check Alice, Bob, and Charlie still whitelisted
        assertEq(permsV2.getPermission(alice).isAllowed, true);
        assertEq(permsV2.getPermission(bob).isAllowed, true);
        assertEq(permsV2.getPermission(charlie).isAllowed, true);

        deal(address(token), alice, 100e6);
        deal(address(token), bob, 100e6);

        // check Alice, Bob, and Charlie can still do whitelisted operations (transfer, transferFrom, encumber, encumberFrom)
        vm.prank(alice);
        token.transfer(bob, 10e6);

        assertEq(token.balanceOf(alice), 90e6);
        assertEq(token.balanceOf(bob), 110e6);

        vm.prank(bob);
        token.approve(alice, 40e6);

        vm.prank(alice);
        token.transferFrom(bob, charlie, 20e6);

        assertEq(token.balanceOf(bob), 90e6);
        assertEq(token.balanceOf(charlie), 20e6);

        vm.prank(bob);
        token.encumber(charlie, 20e6);

        vm.prank(alice);
        token.encumberFrom(bob, charlie, 10e6);

        assertEq(token.encumbrances(bob, charlie), 30e6);
    }

    function testUpgradingPermissionListAndTokenWorks() public {
        PermissionListV2 permsV2Implementation = new PermissionListV2(address(this));
        permsAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(permsProxy)), address(permsV2Implementation), "");
        PermissionListV2 permsV2 = PermissionListV2(address(permsProxy));

        SUPTBV2 tokenV2Implementation = new SUPTBV2(address(this), permsV2);
        tokenAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenV2Implementation), "");
        SUPTBV2 tokenV2 = SUPTBV2(address(tokenProxy));

        // Whitelisting criteria now requires `state7` (newly added state) be true,
        // so Alice, Bob, and Charlie no longer have sufficient permissions...
        assertEq(tokenV2.hasSufficientPermissions(alice), false);
        assertEq(tokenV2.hasSufficientPermissions(bob), false);
        assertEq(tokenV2.hasSufficientPermissions(charlie), false);

        deal(address(tokenV2), alice, 100e6);
        deal(address(tokenV2), bob, 100e6);

        // ...and cannot do regular token operations (transfer, transferFrom, encumber, encumberFrom)
        vm.prank(alice);
        vm.expectRevert(SUPTBV2.InsufficientPermissions.selector);
        tokenV2.transfer(bob, 10e6);

        vm.prank(charlie);
        vm.expectRevert(SUPTBV2.InsufficientPermissions.selector);
        tokenV2.transferFrom(alice, bob, 10e6);

        vm.prank(bob);
        vm.expectRevert(SUPTBV2.InsufficientPermissions.selector);
        tokenV2.encumber(charlie, 10e6);

        vm.prank(bob);
        tokenV2.approve(alice, 40e6);
        vm.prank(alice);
        vm.expectRevert(SUPTBV2.InsufficientPermissions.selector);
        tokenV2.encumberFrom(bob, charlie, 10e6);

        // But when we whitelist all three according to the new criteria...
        PermissionListV2.Permission memory newPerms = PermissionListV2.Permission(true, false, false, false, false, false, false, true);
        permsV2.setPermission(alice, newPerms);
        permsV2.setPermission(bob, newPerms);
        permsV2.setPermission(charlie, newPerms);

        // ...they now have sufficient permissions
        assertEq(tokenV2.hasSufficientPermissions(alice), true);
        assertEq(tokenV2.hasSufficientPermissions(bob), true);
        assertEq(tokenV2.hasSufficientPermissions(charlie), true);

        // ...and can now do regular token operations (transfer, transferFrom, encumber, encumberFrom) without reverts
        vm.prank(alice);
        tokenV2.transfer(bob, 10e6);

        assertEq(tokenV2.balanceOf(alice), 90e6);
        assertEq(tokenV2.balanceOf(bob), 110e6);

        vm.prank(bob);
        tokenV2.approve(alice, 40e6);

        vm.prank(alice);
        tokenV2.transferFrom(bob, charlie, 20e6);

        assertEq(tokenV2.balanceOf(bob), 90e6);
        assertEq(tokenV2.balanceOf(charlie), 20e6);

        vm.prank(bob);
        tokenV2.encumber(charlie, 20e6);

        vm.prank(alice);
        tokenV2.encumberFrom(bob, charlie, 10e6);

        assertEq(tokenV2.encumbrances(bob, charlie), 30e6);
    }

    /* ===== Permit Tests ===== */

    function eveAuthorization(uint256 amount, uint256 nonce, uint256 expiry) internal view returns (uint8, bytes32, bytes32) {
        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, eve, bob, amount, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(evePrivateKey, digest);
    }

    function testPermit() public {
        // bob's allowance from eve is 0
        assertEq(token.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = token.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature
        vm.prank(bob);
        token.permit(eve, bob, allowance, expiry, v, r, s);

        // bob's allowance from eve equals allowance
        assertEq(token.allowance(eve, bob), allowance);

        // eve's nonce is incremented
        assertEq(token.nonces(eve), nonce + 1);
    }

    function testPermitRevertsForBadOwner() public {
        // bob's allowance from eve is 0
        assertEq(token.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = token.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the owner
        vm.prank(bob);
        vm.expectRevert(SUPTB.BadSignatory.selector);
        token.permit(charlie, bob, allowance, expiry, v, r, s);

        // bob's allowance from eve is unchanged
        assertEq(token.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(token.nonces(eve), nonce);
    }

    function testPermitRevertsForBadSpender() public {
        // bob's allowance from eve is 0
        assertEq(token.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = token.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the spender
        vm.prank(bob);
        vm.expectRevert(SUPTB.BadSignatory.selector);
        token.permit(eve, charlie, allowance, expiry, v, r, s);

        // bob's allowance from eve is unchanged
        assertEq(token.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(token.nonces(eve), nonce);
    }

    function testPermitRevertsForBadAmount() public {
        // bob's allowance from eve is 0
        assertEq(token.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = token.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the allowance
        vm.prank(bob);
        vm.expectRevert(SUPTB.BadSignatory.selector);
        token.permit(eve, bob, allowance + 1 wei, expiry, v, r, s);

        // bob's allowance from eve is unchanged
        assertEq(token.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(token.nonces(eve), nonce);
    }

    function testPermitRevertsForBadExpiry() public {
        // bob's allowance from eve is 0
        assertEq(token.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = token.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the expiry
        vm.prank(bob);
        vm.expectRevert(SUPTB.BadSignatory.selector);
        token.permit(eve, bob, allowance, expiry + 1, v, r, s);

        // bob's allowance from eve is unchanged
        assertEq(token.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(token.nonces(eve), nonce);
    }

    function testPermitRevertsForBadNonce() public {
        // bob's allowance from eve is 0
        assertEq(token.allowance(eve, bob), 0);

        // eve signs an authorization with an invalid nonce
        uint256 allowance = 123e18;
        uint256 nonce = token.nonces(eve);
        uint256 badNonce = nonce + 1;
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, badNonce, expiry);

        // bob calls permit with the signature with an invalid nonce
        vm.prank(bob);
        vm.expectRevert(SUPTB.BadSignatory.selector);
        token.permit(eve, bob, allowance, expiry, v, r, s);

        // bob's allowance from eve is unchanged
        assertEq(token.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(token.nonces(eve), nonce);
    }

    function testPermitRevertsOnRepeatedCall() public {
        // bob's allowance from eve is 0
        assertEq(token.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = token.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature
        vm.prank(bob);
        token.permit(eve, bob, allowance, expiry, v, r, s);

        // bob's allowance from eve equals allowance
        assertEq(token.allowance(eve, bob), allowance);

        // eve's nonce is incremented
        assertEq(token.nonces(eve), nonce + 1);

        // eve revokes bob's allowance
        vm.prank(eve);
        token.approve(bob, 0);
        assertEq(token.allowance(eve, bob), 0);

        // bob tries to reuse the same signature twice
        vm.prank(bob);
        vm.expectRevert(SUPTB.BadSignatory.selector);
        token.permit(eve, bob, allowance, expiry, v, r, s);

        // bob's allowance from eve is unchanged
        assertEq(token.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(token.nonces(eve), nonce + 1);
    }

    function testPermitRevertsForExpiredSignature() public {
        // bob's allowance from eve is 0
        assertEq(token.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = token.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // the expiry block arrives
        vm.warp(expiry);

        // bob calls permit with the signature after the expiry
        vm.prank(bob);
        vm.expectRevert(SUPTB.SignatureExpired.selector);
        token.permit(eve, bob, allowance, expiry, v, r, s);

        // bob's allowance from eve is unchanged
        assertEq(token.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(token.nonces(eve), nonce);
    }

    function testPermitRevertsInvalidS() public {
        // bob's allowance from eve is 0
        assertEq(token.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = token.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, ) = eveAuthorization(allowance, nonce, expiry);

        // 1 greater than the max value of s
        bytes32 invalidS = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1;

        // bob calls permit with the signature with invalid `s` value
        vm.prank(bob);
        vm.expectRevert(SUPTB.InvalidSignatureS.selector);
        token.permit(eve, bob, allowance, expiry, v, r, invalidS);

        // bob's allowance from eve is unchanged
        assertEq(token.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(token.nonces(eve), nonce);
    }

    function testPermitRevertsWhenTokenPaused() public {
        token.pause();

        uint256 allowance = 123e18;
        uint256 nonce = token.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // bob calls permit when token is paused
        vm.prank(bob);
        vm.expectRevert(bytes("Pausable: paused"));
        token.permit(eve, bob, allowance, expiry, v, r, s);
    }
}
