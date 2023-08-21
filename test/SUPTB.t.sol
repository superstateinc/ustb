pragma solidity ^0.8.20;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/interfaces/IERC20Metadata.sol";
import {SUPTB} from "src/SUPTB.sol";
import {Permissionlist} from "src/Permissionlist.sol";

contract SUPTBTest is Test {
    event Encumber(address indexed owner, address indexed taker, uint256 amount);
    event Release(address indexed owner, address indexed taker, uint256 amount);
    event EncumbranceSpend(address indexed owner, address indexed taker, uint256 amount);

    Permissionlist public perms;
    SUPTB public token;

    address alice = address(10);
    address bob = address(11);
    address charlie = address(12);
    address mallory = address(13);

    function setUp() public {
        perms = new Permissionlist(address(this));
        token = new SUPTB(address(this), perms);

        // whitelist alice bob, and charlie (so they can tranfer to each other), but not mallory
        Permissionlist.Permission memory allowPerms = Permissionlist.Permission(true);
        perms.setPermission(alice, allowPerms);
        perms.setPermission(bob, allowPerms);
        perms.setPermission(charlie, allowPerms);
    }

    function testTokenName() public {
        assertEq(token.name(), "Superstate Treasuries Blockchain");
    }

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
        vm.expectRevert("ERC7246: insufficient available balance");
        token.transfer(bob, 100e6);

        vm.stopPrank();
    }

    function testEncumberRevert() public {
        deal(address(token), alice, 100e6);
        vm.startPrank(alice);

        // alice encumbers half her balance to bob
        token.encumber(bob, 50e6);

        // alice attempts to encumber more than her remaining available balance
        vm.expectRevert("ERC7246: insufficient available balance");
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

    // TODO: Test failing (Error != expected error)
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
        vm.expectRevert("ERC7246: insufficient allowance");
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
        vm.expectRevert("ERC7246: insufficient encumbrance");
        token.release(alice, 200e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 0);
        assertEq(token.encumberedBalanceOf(alice), 100e6);
        assertEq(token.encumbrances(alice, bob), 100e6);
    }

    function testMint() public {
        token.mint(alice, 100e6);
        assertEq(token.balanceOf(alice), 100e6);
    }

    function testMintRevertBadCaller() public {
        vm.prank(alice);
        vm.expectRevert("Bad caller; only admin can mint");
        token.mint(bob, 100e6);

        assertEq(token.balanceOf(bob), 0);
    }

    function testBurn() public {
        deal(address(token), alice, 100e6);

        assertEq(token.balanceOf(alice), 100e6);

        token.burn(alice, 100e6);
        assertEq(token.balanceOf(alice), 0);
    }

    function testBurnRevertBadCaller() public {
        vm.prank(alice);
        vm.expectRevert("Bad caller; only admin can burn");
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
        vm.expectRevert("ERC7246: insufficient available balance");
        token.burn(alice, 60e6);
    }

    function testEncumberRevertOwnerInsufficientPermissions() public {
        deal(address(token), mallory, 100e6);
        vm.startPrank(mallory);

        // mallory tries to encumber to bob, without being whitelisted
        vm.expectRevert("Insufficient Permissions");
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
        vm.expectRevert("Insufficient Permissions");
        token.encumberFrom(mallory, charlie, 30e6);
    }

    function testTransferRevertSenderInsufficientPermissions() public {
        deal(address(token), mallory, 100e6);

        // mallory tries to transfer tokens, but isn't whitelisted
        vm.prank(mallory);
        vm.expectRevert("Insufficient Permissions");
        token.transfer(charlie, 30e6);
    }

    function testTransferRevertReceiverInsufficientPermissions() public {
        deal(address(token), alice, 100e6);

        // alice tries to transfer tokens to mallory, but mallory isn't whitelisted
        vm.prank(alice);
        vm.expectRevert("Insufficient Permissions");
        token.transfer(mallory, 30e6);
    }

    function testTransferFromRevertReceiverInsufficientPermissions() public {
        deal(address(token), alice, 100e6);

        // alice grants bob an approval
        vm.prank(alice);
        token.approve(bob, 50e6);

        // bob tries to transfer alice's tokens to mallory, but mallory isn't whitelisted
        vm.prank(bob);
        vm.expectRevert("Insufficient Permissions");
        token.transferFrom(alice, mallory, 50e6);
    }

    function testTransfersAndEncumbersRevertIfUnwhitelisted() public {
        deal(address(token), alice, 100e6);
        deal(address(token), bob, 100e6);

        // un-whitelist alice
        Permissionlist.Permission memory disallowPerms = Permissionlist.Permission(false);
        perms.setPermission(alice, disallowPerms);

        // alice can't transfer tokens to a whitelisted address
        vm.prank(alice);
        vm.expectRevert("Insufficient Permissions");
        token.transfer(bob, 30e6);

        // whitelisted addresses can't transfer tokens to alice
        vm.prank(bob);
        vm.expectRevert("Insufficient Permissions");
        token.transfer(alice, 30e6);

        vm.prank(bob);
        token.approve(charlie, 50e6);
        vm.expectRevert("Insufficient Permissions");
        vm.prank(charlie);
        token.transferFrom(bob, alice, 30e6);

        // alice can't encumber tokens to anyone
        vm.prank(alice);
        vm.expectRevert("Insufficient Permissions");
        token.encumber(bob, 30e6);

        // others can't encumber alice's tokens, even if she's approved them
        vm.prank(alice);
        token.approve(bob, 50e6);
        vm.prank(bob);
        vm.expectRevert("Insufficient Permissions");
        token.encumberFrom(alice, charlie, 30e6);
    }
}
