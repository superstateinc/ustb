pragma solidity ^0.8.20;

import "forge-std/StdUtils.sol";
import { Test } from "forge-std/Test.sol";
import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { Pausable } from "openzeppelin-contracts/security/Pausable.sol";
import { IERC20Metadata } from "openzeppelin-contracts/interfaces/IERC20Metadata.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import { SUPTB } from "src/SUPTB.sol";
import { PermissionList } from "src/PermissionList.sol";
import "test/PermissionListV2.sol";


contract SUPTBTest is Test {
    event Encumber(address indexed owner, address indexed taker, uint256 amount);
    event Release(address indexed owner, address indexed taker, uint256 amount);
    event EncumbranceSpend(address indexed owner, address indexed taker, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed dst, uint256 amount);
    event Burn(address indexed src, uint256 amount);

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

    function setUp() public {
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

        // whitelist alice bob, and charlie (so they can tranfer to each other), but not mallory
        PermissionList.Permission memory allowPerms = PermissionList.Permission(true, false, false, false, false, false);
        perms.setPermission(alice, allowPerms);
        perms.setPermission(bob, allowPerms);
        perms.setPermission(charlie, allowPerms);
    }

    // TODO: Resolve token.name() error
    function testTokenName() public {
        assertEq(token.name(), "Superstate Treasuries Blockchain");
    }

    // TODO: Resolve token.symbol() error
    function testTokenSymbol() public {
        assertEq(token.symbol(), "SUPTB");
    }

    function testTokenDecimals() public {
        assertEq(token.decimals(), 6);
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
        // emits mint event
        vm.expectEmit();
        emit Mint(alice, 100e6);

        token.mint(alice, 100e6);
        assertEq(token.balanceOf(alice), 100e6);
    }

    function testMintRevertBadCaller() public {
        vm.prank(alice);
        vm.expectRevert(SUPTB.Unauthorized.selector);
        token.mint(bob, 100e6);

        assertEq(token.balanceOf(bob), 0);
    }

    function testBurn() public {
        deal(address(token), alice, 100e6);

        assertEq(token.balanceOf(alice), 100e6);

       // emits Burn event
        vm.expectEmit();
        emit Burn(alice, 100e6);

        token.burn(alice, 100e6);
        assertEq(token.balanceOf(alice), 0);
    }

    function testSelfBurnUsingTransfer() public {
        deal(address(token), alice, 100e6);

        assertEq(token.balanceOf(alice), 100e6);

        // emits Burn event
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

        // emits Burn event
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

    function testTransferFromWorksIfUsingEncumbranceAndSourceIsWhitelisted() public {
        deal(address(token), mallory, 100e6);

        // whitelist mallory for setting encumbrances
        PermissionList.Permission memory allowPerms = PermissionList.Permission(true, false, false, false, false, false);
        perms.setPermission(mallory, allowPerms);

        vm.prank(mallory);
        token.encumber(bob, 20e6);

        // now un-whitelist mallory
        PermissionList.Permission memory forbidPerms = PermissionList.Permission(false, false, false, false, false, false);
        perms.setPermission(mallory, forbidPerms);

        // bob can transferFrom now-un-whitelisted mallory by spending her encumbrance to him, without issues
        vm.prank(bob);
        token.transferFrom(mallory, alice, 10e6);

        assertEq(token.balanceOf(mallory), 90e6);
        assertEq(token.balanceOf(alice), 10e6);
        assertEq(token.balanceOf(bob), 0e6);
        assertEq(token.encumbrances(mallory, bob), 10e6);
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

        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.mint(alice, 100e6);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.burn(alice, 100e6);

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transfer(bob, 50e6);

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.encumber(bob, 50e6);

        vm.prank(bob);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transferFrom(alice, charlie, 50e6);

        vm.prank(bob);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.encumberFrom(alice, charlie, 50e6);

        vm.prank(bob);
        vm.expectRevert(Pausable.EnforcedPause.selector);
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
}
