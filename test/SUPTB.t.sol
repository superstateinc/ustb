pragma solidity ^0.8.20;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/interfaces/IERC20Metadata.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import {SUPTB} from "src/SUPTB.sol";
import {SUPTBv2} from "test/SUPTBv2.sol";
import {Permissionlist} from "src/Permissionlist.sol";

contract SUPTBTest is Test {
    event Encumber(address indexed owner, address indexed taker, uint256 amount);
    event Release(address indexed owner, address indexed taker, uint256 amount);
    event EncumbranceSpend(address indexed owner, address indexed taker, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    TransparentUpgradeableProxy permsProxy;
    ProxyAdmin permsAdmin;

    Permissionlist public perms;
    Permissionlist public wrappedPerms;

    TransparentUpgradeableProxy tokenProxy;
    ProxyAdmin tokenAdmin;

    SUPTB public token;
    SUPTB public wrappedToken;

    // Storage slot with the admin of the contract.
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address alice = address(10);
    address bob = address(11);
    address charlie = address(12);
    address mallory = address(13);

    function setUp() public {
        perms = new Permissionlist(address(this));

        // deploy proxy contract and point it to implementation
        permsProxy = new TransparentUpgradeableProxy(address(perms), address(this), "");

        bytes32 permsAdminAddress = vm.load(address(permsProxy), ADMIN_SLOT);
        permsAdmin = ProxyAdmin(address(uint160(uint256(permsAdminAddress))));

        // wrap in ABI to support easier calls
        wrappedPerms = Permissionlist(address(permsProxy));

        token = new SUPTB(address(this), wrappedPerms);

        // repeat for the token contract
        tokenProxy = new TransparentUpgradeableProxy(address(token), address(this), "");

        bytes32 tokenAdminAddress = vm.load(address(tokenProxy), ADMIN_SLOT);
        tokenAdmin = ProxyAdmin(address(uint160(uint256(tokenAdminAddress))));

        // wrap in ABI to support easier calls
        wrappedToken = SUPTB(address(tokenProxy));

        // whitelist alice bob, and charlie (so they can tranfer to each other), but not mallory
        Permissionlist.Permission memory allowPerms = Permissionlist.Permission(true);
        wrappedPerms.setPermission(alice, allowPerms);
        wrappedPerms.setPermission(bob, allowPerms);
        wrappedPerms.setPermission(charlie, allowPerms);
    }

    function testTokenName() public {
        assertEq(token.name(), "Superstate Treasuries Blockchain");
    }

    function testTokenSymbol() public {
        assertEq(token.symbol(), "SUPTB");
    }

    function testTokenDecimals() public {
        assertEq(wrappedToken.decimals(), 6);
    }

    function testAvailableBalanceOf() public {
        vm.startPrank(alice);

        // availableBalanceOf is 0 by default
        assertEq(wrappedToken.availableBalanceOf(alice), 0);

        // reflects balance when there are no encumbrances
        deal(address(wrappedToken), alice, 100e6);
        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(wrappedToken.availableBalanceOf(alice), 100e6);

        // is reduced by encumbrances
        wrappedToken.encumber(bob, 20e6);
        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(wrappedToken.availableBalanceOf(alice), 80e6);

        // is reduced by transfers
        wrappedToken.transfer(bob, 20e6);
        assertEq(wrappedToken.balanceOf(alice), 80e6);
        assertEq(wrappedToken.availableBalanceOf(alice), 60e6);

        vm.stopPrank();

        vm.startPrank(bob);

        // is NOT reduced by transferFrom (from an encumbered address)
        wrappedToken.transferFrom(alice, charlie, 10e6);
        assertEq(wrappedToken.balanceOf(alice), 70e6);
        assertEq(wrappedToken.availableBalanceOf(alice), 60e6);
        assertEq(wrappedToken.encumbrances(alice, bob), 10e6);
        assertEq(wrappedToken.balanceOf(charlie), 10e6);

        // is increased by a release
        wrappedToken.release(alice, 5e6);
        assertEq(wrappedToken.balanceOf(alice), 70e6);
        assertEq(wrappedToken.availableBalanceOf(alice), 65e6);
        assertEq(wrappedToken.encumbrances(alice, bob), 5e6);

        vm.stopPrank();
    }

    function testTransferRevertInsufficentBalance() public {
        deal(address(wrappedToken), alice, 100e6);
        vm.startPrank(alice);

        // alice encumbers half her balance to charlie
        wrappedToken.encumber(charlie, 50e6);

        // alice attempts to transfer her entire balance
        vm.expectRevert("ERC7246: insufficient available balance");
        wrappedToken.transfer(bob, 100e6);

        vm.stopPrank();
    }

    function testEncumberRevert() public {
        deal(address(wrappedToken), alice, 100e6);
        vm.startPrank(alice);

        // alice encumbers half her balance to bob
        wrappedToken.encumber(bob, 50e6);

        // alice attempts to encumber more than her remaining available balance
        vm.expectRevert("ERC7246: insufficient available balance");
        wrappedToken.encumber(charlie, 60e6);

        vm.stopPrank();
    }

    function testEncumber() public {
        deal(address(wrappedToken), alice, 100e6);
        vm.startPrank(alice);

        // emits Encumber event
        vm.expectEmit(true, true, true, true);
        emit Encumber(alice, bob, 60e6);

        // alice encumbers some of her balance to bob
        wrappedToken.encumber(bob, 60e6);

        // balance is unchanged
        assertEq(wrappedToken.balanceOf(alice), 100e6);
        // available balance is reduced
        assertEq(wrappedToken.availableBalanceOf(alice), 40e6);

        // creates encumbrance for taker
        assertEq(wrappedToken.encumbrances(alice, bob), 60e6);

        // updates encumbered balance of owner
        assertEq(wrappedToken.encumberedBalanceOf(alice), 60e6);
    }

    function testTransferFromSufficientEncumbrance() public {
        deal(address(wrappedToken), alice, 100e6);
        vm.prank(alice);

        // alice encumbers some of her balance to bob
        wrappedToken.encumber(bob, 60e6);

        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(wrappedToken.availableBalanceOf(alice), 40e6);
        assertEq(wrappedToken.encumberedBalanceOf(alice), 60e6);
        assertEq(wrappedToken.encumbrances(alice, bob), 60e6);
        assertEq(wrappedToken.balanceOf(charlie), 0);

        // bob calls transfers from alice to charlie
        vm.prank(bob);
        wrappedToken.transferFrom(alice, charlie, 40e6);

        // alice balance is reduced
        assertEq(wrappedToken.balanceOf(alice), 60e6);
        // alice encumbrance to bob is reduced
        assertEq(wrappedToken.availableBalanceOf(alice), 40e6);
        assertEq(wrappedToken.encumberedBalanceOf(alice), 20e6);
        assertEq(wrappedToken.encumbrances(alice, bob), 20e6);
        // transfer is completed
        assertEq(wrappedToken.balanceOf(charlie), 40e6);
    }

    function testTransferFromEncumbranceAndAllowance() public {
        deal(address(wrappedToken), alice, 100e6);
        vm.startPrank(alice);

        // alice encumbers some of her balance to bob
        wrappedToken.encumber(bob, 20e6);

        // she also grants him an approval
        wrappedToken.approve(bob, 30e6);

        vm.stopPrank();

        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(wrappedToken.availableBalanceOf(alice), 80e6);
        assertEq(wrappedToken.encumberedBalanceOf(alice), 20e6);
        assertEq(wrappedToken.encumbrances(alice, bob), 20e6);
        assertEq(wrappedToken.allowance(alice, bob), 30e6);
        assertEq(wrappedToken.balanceOf(charlie), 0);

        // bob calls transfers from alice to charlie
        vm.prank(bob);
        wrappedToken.transferFrom(alice, charlie, 40e6);

        // alice balance is reduced
        assertEq(wrappedToken.balanceOf(alice), 60e6);

        // her encumbrance to bob has been fully spent
        assertEq(wrappedToken.availableBalanceOf(alice), 60e6);
        assertEq(wrappedToken.encumberedBalanceOf(alice), 0);
        assertEq(wrappedToken.encumbrances(alice, bob), 0);

        // her allowance to bob has been partially spent
        assertEq(wrappedToken.allowance(alice, bob), 10e6);

        // the dst receives the transfer
        assertEq(wrappedToken.balanceOf(charlie), 40e6);
    }

    function testTransferFromInsufficientAllowance() public {
        deal(address(wrappedToken), alice, 100e6);

        uint256 encumberedAmount = 10e6;
        uint256 approvedAmount = 20e6;
        uint256 transferAmount = 40e6;

        vm.startPrank(alice);

        // alice encumbers some of her balance to bob
        wrappedToken.encumber(bob, encumberedAmount);

        // she also grants him an approval
        wrappedToken.approve(bob, approvedAmount);

        vm.stopPrank();

        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(wrappedToken.availableBalanceOf(alice), 90e6);
        assertEq(wrappedToken.encumberedBalanceOf(alice), 10e6);
        assertEq(wrappedToken.encumbrances(alice, bob), encumberedAmount);
        assertEq(wrappedToken.allowance(alice, bob), approvedAmount);
        assertEq(wrappedToken.balanceOf(charlie), 0);

        // bob tries to transfer more than his encumbered and allowed balances
        vm.prank(bob);
        vm.expectRevert();
        wrappedToken.transferFrom(alice, charlie, transferAmount);
    }

    function testEncumberFromInsufficientAllowance() public {
        deal(address(wrappedToken), alice, 100e6);

        // alice grants bob an approval
        vm.prank(alice);
        wrappedToken.approve(bob, 50e6);

        // but bob tries to encumber more than his allowance
        vm.prank(bob);
        vm.expectRevert("ERC7246: insufficient allowance");
        wrappedToken.encumberFrom(alice, charlie, 60e6);
    }

    function testEncumberFrom() public {
        deal(address(wrappedToken), alice, 100e6);

        // alice grants bob an approval
        vm.prank(alice);
        wrappedToken.approve(bob, 100e6);

        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(wrappedToken.availableBalanceOf(alice), 100e6);
        assertEq(wrappedToken.encumberedBalanceOf(alice), 0e6);
        assertEq(wrappedToken.encumbrances(alice, bob), 0e6);
        assertEq(wrappedToken.allowance(alice, bob), 100e6);
        assertEq(wrappedToken.balanceOf(charlie), 0);

        // bob encumbers part of his allowance from alice to charlie
        vm.prank(bob);
        // emits an Encumber event
        vm.expectEmit(true, true, true, true);
        emit Encumber(alice, charlie, 60e6);
        wrappedToken.encumberFrom(alice, charlie, 60e6);

        // no balance is transferred
        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(wrappedToken.balanceOf(charlie), 0);
        // but available balance is reduced
        assertEq(wrappedToken.availableBalanceOf(alice), 40e6);
        // encumbrance to charlie is created
        assertEq(wrappedToken.encumberedBalanceOf(alice), 60e6);
        assertEq(wrappedToken.encumbrances(alice, bob), 0e6);
        assertEq(wrappedToken.encumbrances(alice, charlie), 60e6);
        // allowance is partially spent
        assertEq(wrappedToken.allowance(alice, bob), 40e6);
    }

    function testRelease() public {
        deal(address(wrappedToken), alice, 100e6);

        vm.prank(alice);

        // alice encumbers her balance to bob
        wrappedToken.encumber(bob, 100e6);

        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(wrappedToken.availableBalanceOf(alice), 0);
        assertEq(wrappedToken.encumberedBalanceOf(alice), 100e6);
        assertEq(wrappedToken.encumbrances(alice, bob), 100e6);

        // bob releases part of the encumbrance
        vm.prank(bob);
        // emits Release event
        vm.expectEmit(true, true, true, true);
        emit Release(alice, bob, 40e6);
        wrappedToken.release(alice, 40e6);

        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(wrappedToken.availableBalanceOf(alice), 40e6);
        assertEq(wrappedToken.encumberedBalanceOf(alice), 60e6);
        assertEq(wrappedToken.encumbrances(alice, bob), 60e6);
    }

    function testReleaseInsufficientEncumbrance() public {
        deal(address(wrappedToken), alice, 100e6);

        vm.prank(alice);

        // alice encumbers her entire balance to bob
        wrappedToken.encumber(bob, 100e6);

        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(wrappedToken.availableBalanceOf(alice), 0);
        assertEq(wrappedToken.encumberedBalanceOf(alice), 100e6);
        assertEq(wrappedToken.encumbrances(alice, bob), 100e6);

        // bob releases a greater amount than is encumbered to him
        vm.prank(bob);
        vm.expectRevert("ERC7246: insufficient encumbrance");
        wrappedToken.release(alice, 200e6);

        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(wrappedToken.availableBalanceOf(alice), 0);
        assertEq(wrappedToken.encumberedBalanceOf(alice), 100e6);
        assertEq(wrappedToken.encumbrances(alice, bob), 100e6);
    }

    function testMint() public {
        wrappedToken.mint(alice, 100e6);
        assertEq(wrappedToken.balanceOf(alice), 100e6);
    }

    function testMintRevertBadCaller() public {
        vm.prank(alice);
        vm.expectRevert(SUPTB.Unauthorized.selector);
        wrappedToken.mint(bob, 100e6);

        assertEq(wrappedToken.balanceOf(bob), 0);
    }

    function testBurn() public {
        deal(address(wrappedToken), alice, 100e6);

        assertEq(wrappedToken.balanceOf(alice), 100e6);

        wrappedToken.burn(alice, 100e6);
        assertEq(wrappedToken.balanceOf(alice), 0);
    }

    function testSelfBurnUsingTransfer() public {
        deal(address(wrappedToken), alice, 100e6);

        assertEq(wrappedToken.balanceOf(alice), 100e6);

        // emits Transfer event
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 50e6);

        // alice calls transfer(contract_address, amount) to self-burn
        vm.prank(alice);
        wrappedToken.transfer(address(wrappedToken), 50e6);

        assertEq(wrappedToken.balanceOf(alice), 50e6);
    }

    function testBurnRevertBadCaller() public {
        vm.prank(alice);
        vm.expectRevert(SUPTB.Unauthorized.selector);
        wrappedToken.burn(bob, 100e6);
    }

    function testBurnRevertInsufficientBalance() public {
        deal(address(wrappedToken), alice, 100e6);

        // alice encumbers half her balance to bob
        vm.prank(alice);
        wrappedToken.encumber(bob, 50e6);

        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(wrappedToken.availableBalanceOf(alice), 50e6);
        assertEq(wrappedToken.encumberedBalanceOf(alice), 50e6);
        assertEq(wrappedToken.encumbrances(alice, bob), 50e6);

        // alice tries to burn more than her available balance
        vm.expectRevert("ERC7246: insufficient available balance");
        wrappedToken.burn(alice, 60e6);
    }

    function testEncumberRevertOwnerInsufficientPermissions() public {
        deal(address(wrappedToken), mallory, 100e6);
        vm.startPrank(mallory);

        // mallory tries to encumber to bob, without being whitelisted
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        wrappedToken.encumber(bob, 50e6);

        vm.stopPrank();
    }

    function testEncumberFromRevertOwnerInsufficientPermissions() public {
        deal(address(wrappedToken), mallory, 100e6);

        // mallory grants bob an approval
        vm.prank(mallory);
        wrappedToken.approve(bob, 50e6);

        // bob tries to encumber to charlie on behalf of mallory, but mallory isn't whitelisted
        vm.prank(bob);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        wrappedToken.encumberFrom(mallory, charlie, 30e6);
    }

    function testTransferRevertSenderInsufficientPermissions() public {
        deal(address(wrappedToken), mallory, 100e6);

        // mallory tries to transfer tokens, but isn't whitelisted
        vm.prank(mallory);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        wrappedToken.transfer(charlie, 30e6);
    }

    function testTransferRevertReceiverInsufficientPermissions() public {
        deal(address(wrappedToken), alice, 100e6);

        // alice tries to transfer tokens to mallory, but mallory isn't whitelisted
        vm.prank(alice);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        wrappedToken.transfer(mallory, 30e6);
    }

    function testTransferFromRevertReceiverInsufficientPermissions() public {
        deal(address(wrappedToken), alice, 100e6);

        // alice grants bob an approval
        vm.prank(alice);
        wrappedToken.approve(bob, 50e6);

        // bob tries to transfer alice's tokens to mallory, but mallory isn't whitelisted
        vm.prank(bob);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        wrappedToken.transferFrom(alice, mallory, 50e6);
    }

    function testTransfersAndEncumbersRevertIfUnwhitelisted() public {
        deal(address(wrappedToken), alice, 100e6);
        deal(address(wrappedToken), bob, 100e6);

        // un-whitelist alice
        Permissionlist.Permission memory disallowPerms = Permissionlist.Permission(false);
        wrappedPerms.setPermission(alice, disallowPerms);

        // alice can't transfer tokens to a whitelisted address
        vm.prank(alice);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        wrappedToken.transfer(bob, 30e6);

        // whitelisted addresses can't transfer tokens to alice
        vm.prank(bob);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        wrappedToken.transfer(alice, 30e6);

        vm.prank(bob);
        wrappedToken.approve(charlie, 50e6);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        vm.prank(charlie);
        wrappedToken.transferFrom(bob, alice, 30e6);

        // alice can't encumber tokens to anyone
        vm.prank(alice);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        wrappedToken.encumber(bob, 30e6);

        // others can't encumber alice's tokens, even if she's approved them
        vm.prank(alice);
        wrappedToken.approve(bob, 50e6);
        vm.prank(bob);
        vm.expectRevert(SUPTB.InsufficientPermissions.selector);
        wrappedToken.encumberFrom(alice, charlie, 30e6);
    }

    function testSUPTBUpgrade() public {
        // set new token admin
        SUPTBv2 tokenV2 = new SUPTBv2(charlie, wrappedPerms);

        tokenAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenV2), "");

        SUPTBv2 wrappedTokenV2 = SUPTBv2(address(tokenProxy));

        // check permissionlist reference didn't change
        assertEq(address(wrappedTokenV2.permissionlist()), address(wrappedPerms));

        // check token admin changed
        assertEq(wrappedTokenV2.admin(), charlie);
    }
}
