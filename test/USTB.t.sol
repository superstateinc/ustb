pragma solidity ^0.8.20;

import "forge-std/StdUtils.sol";
import { Test } from "forge-std/Test.sol";
import { PausableUpgradeable } from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import { USTB } from "src/USTB.sol";
import { AllowList } from "src/AllowList.sol";
import "test/AllowListV2.sol";
import "test/USTBV2.sol";

contract USTBTest is Test {
    event Pledge(address indexed owner, address indexed taker, uint256 amount);
    event Release(address indexed owner, address indexed taker, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed minter, address indexed to, uint256 amount);
    event Burn(address indexed burner, address indexed from, uint256 amount);
    event AccountingPaused(address admin);
    event AccountingUnpaused(address admin);

    ProxyAdmin proxyAdmin;
    TransparentUpgradeableProxy permsProxy;
    AllowList public perms;
    TransparentUpgradeableProxy tokenProxy;
    USTB public token;

    address alice = address(10);
    address bob = address(11);
    address charlie = address(12);
    address mallory = address(13);
    uint256 evePrivateKey = 0x353;
    address eve; // see setup()

    uint abcEntityId = 1;

    bytes32 internal constant AUTHORIZATION_TYPEHASH = keccak256("Authorization(address owner,address spender,uint256 amount,uint256 nonce,uint256 expiry)");

    function setUp() public {
        eve = vm.addr(evePrivateKey);

        AllowList permsImplementation = new AllowList(address(this));

        // deploy proxy admin contract
        proxyAdmin = new ProxyAdmin();

        // deploy proxy contract and point it to implementation
        permsProxy = new TransparentUpgradeableProxy(address(permsImplementation), address(proxyAdmin), "");

        // wrap in ABI to support easier calls
        perms = AllowList(address(permsProxy));

        USTB tokenImplementation = new USTB(address(this), perms);

        // repeat for the token contract
        tokenProxy = new TransparentUpgradeableProxy(address(tokenImplementation), address(proxyAdmin), "");

        // wrap in ABI to support easier calls
        token = USTB(address(tokenProxy));

        // initialize token contract
        token.initialize("Superstate Short Duration US Government Securities Fund", "USTB");

        // whitelist alice bob, and charlie (so they can tranfer to each other), but not mallory
        AllowList.Permission memory allowPerms = AllowList.Permission(true, false, false, false, false, false);

        perms.setEntityIdForAddress(abcEntityId, alice);
        perms.setEntityIdForAddress(abcEntityId, bob);
        address[] memory addrs = new address[](1);
        addrs[0] = charlie;
        perms.setEntityPermissionAndAddresses(abcEntityId, addrs, allowPerms);
    }

    function testTokenName() public {
        assertEq(token.name(), "Superstate Short Duration US Government Securities Fund");
    }

    function testTokenSymbol() public {
        assertEq(token.symbol(), "USTB");
    }

    function testTokenDecimals() public {
        assertEq(token.decimals(), 6);
    }

    function testEntityMaxPercent() public {
        assertEq(token.entityMaxBalance(), 0);
        token.mint(alice, 100e6);
        assertEq(token.entityMaxBalance(), 20e6);
    }

    function testTokenIsInitializedAsUnpaused() public {
        assertEq(token.paused(), false);
    }

    function testInitializeRevertIfCalledAgain() public {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        token.initialize("new name", "new symbol");
    }

    function testAvailableBalanceOf() public {
        vm.startPrank(alice);

        // availableBalanceOf is 0 by default
        assertEq(token.availableBalanceOf(alice), 0);

        // reflects balance when there are no pledgedAmounts
        deal(address(token), alice, 100e6);
        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 100e6);

        // is reduced by pledgedAmounts
        token.pledge(bob, 20e6);
        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 80e6);

        // is reduced by transfers
        token.transfer(bob, 20e6);
        assertEq(token.balanceOf(alice), 80e6);
        assertEq(token.availableBalanceOf(alice), 60e6);

        vm.stopPrank();

        vm.startPrank(bob);

        // is NOT reduced by transferFrom (from an pledged address)
        token.transferFrom(alice, charlie, 10e6);
        assertEq(token.balanceOf(alice), 70e6);
        assertEq(token.availableBalanceOf(alice), 60e6);
        assertEq(token.pledgedAmounts(alice, bob), 10e6);
        assertEq(token.balanceOf(charlie), 10e6);

        // is increased by a release
        token.release(alice, 5e6);
        assertEq(token.balanceOf(alice), 70e6);
        assertEq(token.availableBalanceOf(alice), 65e6);
        assertEq(token.pledgedAmounts(alice, bob), 5e6);

        vm.stopPrank();
    }

    function testTransferRevertInsufficentBalance() public {
        deal(address(token), alice, 100e6);
        vm.startPrank(alice);

        // alice pledges half her balance to charlie
        token.pledge(charlie, 50e6);

        // alice attempts to transfer her entire balance
        vm.expectRevert(USTB.InsufficientAvailableBalance.selector);
        token.transfer(bob, 100e6);

        vm.stopPrank();
    }

    function testTransferFromRevertInsufficentBalance() public {
        deal(address(token), alice, 100e6);
        vm.startPrank(alice);

        // alice pledges half her balance to charlie
        token.pledge(charlie, 50e6);
        vm.stopPrank();

        // someone attempts to transfer alice's entire balance
        vm.expectRevert(USTB.InsufficientAvailableBalance.selector);
        token.transferFrom(alice, bob, 100e6);
    }

    function testPledgeRevert() public {
        deal(address(token), alice, 100e6);
        vm.startPrank(alice);

        // alice pledges half her balance to bob
        token.pledge(bob, 50e6);

        // alice attempts to pledge more than her remaining available balance
        vm.expectRevert(USTB.InsufficientAvailableBalance.selector);
        token.pledge(charlie, 60e6);

        vm.stopPrank();
    }

    function testPledge() public {
        deal(address(token), alice, 100e6);
        vm.startPrank(alice);

        // emits Pledge event
        vm.expectEmit(true, true, true, true);
        emit Pledge(alice, bob, 60e6);

        // alice pledges some of her balance to bob
        token.pledge(bob, 60e6);

        // balance is unchanged
        assertEq(token.balanceOf(alice), 100e6);
        // available balance is reduced
        assertEq(token.availableBalanceOf(alice), 40e6);

        // creates pledgedAmount for taker
        assertEq(token.pledgedAmounts(alice, bob), 60e6);

        // updates pledged balance of owner
        assertEq(token.pledgedBalanceOf(alice), 60e6);
    }

    function testSelfPledgeReverts() public {
        deal(address(token), alice, 100e6);

        assertEq(token.balanceOf(alice), 100e6);

        vm.prank(alice);
        vm.expectRevert(USTB.SelfPledgeNotAllowed.selector);
        token.pledge(alice, 50e6);

        vm.prank(alice);
        token.approve(bob, 50e6);

        vm.prank(bob);
        vm.expectRevert(USTB.SelfPledgeNotAllowed.selector);
        token.pledgeFrom(alice, alice, 10e6);
    }

    function testTransferFromSufficientPledgedAmount() public {
        deal(address(token), alice, 100e6);
        vm.prank(alice);

        // alice pledges some of her balance to bob
        token.pledge(bob, 60e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 40e6);
        assertEq(token.pledgedBalanceOf(alice), 60e6);
        assertEq(token.pledgedAmounts(alice, bob), 60e6);
        assertEq(token.balanceOf(charlie), 0);

        // bob calls transfers from alice to charlie
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Release(alice, bob, 40e6);
        token.transferFrom(alice, charlie, 40e6);

        // alice balance is reduced
        assertEq(token.balanceOf(alice), 60e6);
        // alice pledgedAmount to bob is reduced
        assertEq(token.availableBalanceOf(alice), 40e6);
        assertEq(token.pledgedBalanceOf(alice), 20e6);
        assertEq(token.pledgedAmounts(alice, bob), 20e6);
        // transfer is completed
        assertEq(token.balanceOf(charlie), 40e6);
    }

    function testTransferFromPledgedAmountAndAllowance() public {
        deal(address(token), alice, 100e6);
        vm.startPrank(alice);

        // alice pledges some of her balance to bob
        token.pledge(bob, 20e6);

        // she also grants him an approval
        token.approve(bob, 30e6);

        vm.stopPrank();

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 80e6);
        assertEq(token.pledgedBalanceOf(alice), 20e6);
        assertEq(token.pledgedAmounts(alice, bob), 20e6);
        assertEq(token.allowance(alice, bob), 30e6);
        assertEq(token.balanceOf(charlie), 0);

        // bob calls transfers from alice to charlie
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Release(alice, bob, 20e6);
        token.transferFrom(alice, charlie, 40e6);

        // alice balance is reduced
        assertEq(token.balanceOf(alice), 60e6);

        // her pledgedAmount to bob has been fully spent
        assertEq(token.availableBalanceOf(alice), 60e6);
        assertEq(token.pledgedBalanceOf(alice), 0);
        assertEq(token.pledgedAmounts(alice, bob), 0);

        // her allowance to bob has been partially spent
        assertEq(token.allowance(alice, bob), 10e6);

        // the dst receives the transfer
        assertEq(token.balanceOf(charlie), 40e6);
    }

    function testTransferFromInsufficientAllowance() public {
        deal(address(token), alice, 100e6);

        uint256 pledgedAmount = 10e6;
        uint256 approvedAmount = 20e6;
        uint256 transferAmount = 40e6;

        vm.startPrank(alice);

        // alice pledges some of her balance to bob
        token.pledge(bob, pledgedAmount);

        // she also grants him an approval
        token.approve(bob, approvedAmount);

        vm.stopPrank();

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 90e6);
        assertEq(token.pledgedBalanceOf(alice), 10e6);
        assertEq(token.pledgedAmounts(alice, bob), pledgedAmount);
        assertEq(token.allowance(alice, bob), approvedAmount);
        assertEq(token.balanceOf(charlie), 0);

        // bob tries to transfer more than his pledged and allowed balances
        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, charlie, transferAmount);
    }

    function testPledgeFromInsufficientAllowance() public {
        deal(address(token), alice, 100e6);

        // alice grants bob an approval
        vm.prank(alice);
        token.approve(bob, 50e6);

        // but bob tries to pledge more than his allowance
        vm.prank(bob);
        vm.expectRevert();
        token.pledgeFrom(alice, charlie, 60e6);
    }

    function testPledgeFrom() public {
        deal(address(token), alice, 100e6);

        // alice grants bob an approval
        vm.prank(alice);
        token.approve(bob, 100e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 100e6);
        assertEq(token.pledgedBalanceOf(alice), 0e6);
        assertEq(token.pledgedAmounts(alice, bob), 0e6);
        assertEq(token.allowance(alice, bob), 100e6);
        assertEq(token.balanceOf(charlie), 0);

        // bob pledges part of his allowance from alice to charlie
        vm.prank(bob);
        // emits an Pledge event
        vm.expectEmit(true, true, true, true);
        emit Pledge(alice, charlie, 60e6);
        token.pledgeFrom(alice, charlie, 60e6);

        // no balance is transferred
        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.balanceOf(charlie), 0);
        // but available balance is reduced
        assertEq(token.availableBalanceOf(alice), 40e6);
        // pledgedAmount to charlie is created
        assertEq(token.pledgedBalanceOf(alice), 60e6);
        assertEq(token.pledgedAmounts(alice, bob), 0e6);
        assertEq(token.pledgedAmounts(alice, charlie), 60e6);
        // allowance is partially spent
        assertEq(token.allowance(alice, bob), 40e6);
    }

    function testRelease() public {
        deal(address(token), alice, 100e6);

        vm.prank(alice);

        // alice pledges her balance to bob
        token.pledge(bob, 100e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 0);
        assertEq(token.pledgedBalanceOf(alice), 100e6);
        assertEq(token.pledgedAmounts(alice, bob), 100e6);

        // bob releases part of the pledgedAmount
        vm.prank(bob);
        // emits Release event
        vm.expectEmit(true, true, true, true);
        emit Release(alice, bob, 40e6);
        token.release(alice, 40e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 40e6);
        assertEq(token.pledgedBalanceOf(alice), 60e6);
        assertEq(token.pledgedAmounts(alice, bob), 60e6);
    }

    function testReleaseInsufficientPledgedAmount() public {
        deal(address(token), alice, 100e6);

        vm.prank(alice);

        // alice pledges her entire balance to bob
        token.pledge(bob, 100e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 0);
        assertEq(token.pledgedBalanceOf(alice), 100e6);
        assertEq(token.pledgedAmounts(alice, bob), 100e6);

        // bob releases a greater amount than is pledged to him
        vm.prank(bob);
        vm.expectRevert(USTB.InsufficientPledgedAmount.selector);
        token.release(alice, 200e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 0);
        assertEq(token.pledgedBalanceOf(alice), 100e6);
        assertEq(token.pledgedAmounts(alice, bob), 100e6);
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
        vm.expectRevert(USTB.Unauthorized.selector);
        token.mint(bob, 100e6);

        assertEq(token.balanceOf(bob), 0);
    }

    function testMintRevertInsufficientPermissions() public {
        // cannot mint to Mallory since un-whitelisted
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        token.mint(mallory, 100e6);
    }

    function testBurn() public {
        deal(address(token), alice, 100e6);

        assertEq(token.balanceOf(alice), 100e6);

       // emits Transfer and Burn events
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 100e6);
        vm.expectEmit();
        emit Burn(address(this), alice, 100e6);

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
        emit Burn(alice, alice, 50e6);

        // alice calls transfer(0, amount) to self-burn
        vm.prank(alice);
        token.transfer(address(tokenProxy), 50e6);

        assertEq(token.balanceOf(alice), 50e6);
    }

    function testSelfBurnUsingBurn() public {
        deal(address(token), alice, 100e6);

        assertEq(token.balanceOf(alice), 100e6);

        // emits Transfer and Burn events
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 50e6);
        vm.expectEmit();
        emit Burn(alice, alice, 50e6);

        // alice calls burn(amount) to self-burn
        vm.prank(alice);
        token.burn(50e6);

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
        emit Burn(bob, alice, 50e6);

        // bob calls transferFrom(alice, 0, amount) to self-burn
        vm.prank(bob);
        token.transferFrom(alice, address(tokenProxy), 50e6);

        assertEq(token.balanceOf(alice), 50e6);
        assertEq(token.allowance(alice, bob), 0e6);
    }

    function testBurnRevertBadCaller() public {
        vm.prank(alice);
        vm.expectRevert(USTB.Unauthorized.selector);
        token.burn(bob, 100e6);
    }

    function testSelfBurnRevertInsufficientBalance() public {
        deal(address(token), alice, 100e6);

        // alice tries to burn more than her balance
        vm.prank(alice);
        token.pledge(bob, 50e6);
        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 50e6);
        assertEq(token.pledgedBalanceOf(alice), 50e6);
        assertEq(token.pledgedAmounts(alice, bob), 50e6);
        
        vm.expectRevert(USTB.InsufficientAvailableBalance.selector);
        token.burn(200e6);
    }

    function testBurnRevertInsufficientBalance() public {
        deal(address(token), alice, 100e6);

        // alice pledges half her balance to bob
        vm.prank(alice);
        token.pledge(bob, 50e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.availableBalanceOf(alice), 50e6);
        assertEq(token.pledgedBalanceOf(alice), 50e6);
        assertEq(token.pledgedAmounts(alice, bob), 50e6);

        // alice tries to burn more than her available balance
        vm.expectRevert(USTB.InsufficientAvailableBalance.selector);
        token.burn(alice, 60e6);
    }

    function testSelfBurnRevertOwnerInsufficientPermissions() public {
        deal(address(token), mallory, 100e6);

        // mallory tries to burn her tokens, but isn't whitelisted
        vm.prank(mallory);
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        token.burn(50e6);
    }

    function testPledgeRevertOwnerInsufficientPermissions() public {
        deal(address(token), mallory, 100e6);
        vm.startPrank(mallory);

        // mallory tries to pledge to bob, without being whitelisted
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        token.pledge(bob, 50e6);

        vm.stopPrank();
    }

    function testPledgeFromRevertOwnerInsufficientPermissions() public {
        deal(address(token), mallory, 100e6);

        // mallory grants bob an approval
        vm.prank(mallory);
        token.approve(bob, 50e6);

        // bob tries to pledge to charlie on behalf of mallory, but mallory isn't whitelisted
        vm.prank(bob);
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        token.pledgeFrom(mallory, charlie, 30e6);
    }

    function testTransferToZeroReverts() public {
        deal(address(token), alice, 100e6);
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        vm.prank(alice);
        token.transfer(address(0), 10e6);
    }

    function testTransferFromToZeroReverts() public {
        deal(address(token), alice, 100e6);
        vm.prank(alice);
        token.approve(bob, 50e6);
        vm.prank(bob);
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        token.transferFrom(alice, address(0), 10e6);
    }

    function testTransferRevertSenderInsufficientPermissions() public {
        deal(address(token), mallory, 100e6);

        // mallory tries to transfer tokens, but isn't whitelisted
        vm.prank(mallory);
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        token.transfer(charlie, 30e6);
    }

    function testTransferRevertReceiverInsufficientPermissions() public {
        deal(address(token), alice, 100e6);

        // alice tries to transfer tokens to mallory, but mallory isn't whitelisted
        vm.prank(alice);
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        token.transfer(mallory, 30e6);
    }

    function testTransferFromRevertReceiverInsufficientPermissions() public {
        deal(address(token), alice, 100e6);

        // alice grants bob an approval
        vm.prank(alice);
        token.approve(bob, 50e6);

        // bob tries to transfer alice's tokens to mallory, but mallory isn't whitelisted
        vm.prank(bob);
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        token.transferFrom(alice, mallory, 50e6);
    }

    function testTransferFromRevertsIfSpendingTokensPledgeedToOthers() public {
        deal(address(token), alice, 200e18);
        vm.startPrank(alice);

        // alice pledges some of her balance to bob
        token.pledge(bob, 50e18);

        // she also grants him an approval
        token.approve(bob, type(uint256).max);

        // alice pledges the remainder of her balance to charlie
        token.pledge(charlie, 150e18);

        vm.stopPrank();

        assertEq(token.balanceOf(alice), 200e18);
        assertEq(token.availableBalanceOf(alice), 0);
        assertEq(token.pledgedBalanceOf(alice), 200e18);
        assertEq(token.pledgedAmounts(alice, bob), 50e18);
        assertEq(token.pledgedAmounts(alice, charlie), 150e18);
        assertEq(token.allowance(alice, bob), type(uint256).max);

        // bob calls transfers from alice, attempting to transfer his pledged
        // tokens and also transfer tokens pledged to charlie
        vm.prank(bob);
        vm.expectRevert(USTB.InsufficientAvailableBalance.selector);
        token.transferFrom(alice, bob, 100e18);
    }

    function testTransferFromWorksIfUsingPledgedAmountAndSourceIsNotWhitelisted() public {
        deal(address(token), mallory, 100e6);

        // whitelist mallory for setting pledgedAmounts
        AllowList.Permission memory allowPerms = AllowList.Permission(true, false, false, false, false, false);
        address[] memory addrs = new address[](1);
        addrs[0] = mallory;
        perms.setEntityPermissionAndAddresses(2, addrs, allowPerms);
        vm.startPrank(mallory);
        token.pledge(bob, 20e6);
        token.approve(bob, 10e6);
        vm.stopPrank();

        // now un-whitelist mallory
        AllowList.Permission memory forbidPerms = AllowList.Permission(false, false, false, false, false, false);
        perms.setPermission(2, forbidPerms);

        // bob can transferFrom now-un-whitelisted mallory by spending her pledgedAmount to him, without issues
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Release(mallory, bob, 15e6);
        vm.expectEmit(true, true, true, true);
        emit Transfer(mallory, alice, 15e6);
        token.transferFrom(mallory, alice, 15e6);

        assertEq(token.balanceOf(mallory), 85e6);
        assertEq(token.balanceOf(alice), 15e6);
        assertEq(token.balanceOf(bob), 0e6);
        assertEq(token.pledgedAmounts(mallory, bob), 5e6);
    }

    function testTransferFromRevertsIfNotUsingPledgedAmountsAndSourceNotWhitelisted() public {
        deal(address(token), mallory, 100e6);

        vm.prank(mallory);
        token.approve(bob, 50e6);

        // reverts because pledgedAmounts[src][bob] == 0 and src (mallory) is not whitelisted
        vm.prank(bob);
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        token.transferFrom(mallory, alice, 10e6);
    }

    function testTransferFromRevertsIfPledgedAmountLessThanAmountAndSourceNotWhitelisted() public {
        deal(address(token), mallory, 100e6);

        // whitelist mallory for setting pledgedAmounts
        AllowList.Permission memory allowPerms = AllowList.Permission(true, false, false, false, false, false);
        address[] memory addrs = new address[](1);
        addrs[0] = mallory;
        perms.setEntityPermissionAndAddresses(2, addrs, allowPerms);
        vm.startPrank(mallory);
        token.pledge(bob, 20e6);
        token.approve(bob, 10e6);
        vm.stopPrank();

        // now un-whitelist mallory
        AllowList.Permission memory forbidPerms = AllowList.Permission(false, false, false, false, false, false);
        perms.setPermission(2, forbidPerms);


        // reverts because pledgedAmounts[src][bob] = 20 < amount and src (mallory) is not whitelisted
        vm.prank(bob);
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        token.transferFrom(mallory, alice, 30e6);
    }

    function testTransfersAndPledgesRevertIfUnwhitelisted() public {
        deal(address(token), bob, 100e6);
        deal(address(token), mallory, 100e6);

        // mallory can't transfer tokens to a whitelisted address
        vm.prank(mallory);
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        token.transfer(bob, 30e6);

        // whitelisted addresses can't transfer tokens to mallory
        vm.prank(bob);
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        token.transfer(mallory, 30e6);

        vm.prank(bob);
        token.approve(charlie, 50e6);
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        vm.prank(charlie);
        token.transferFrom(bob, mallory, 30e6);

        // mallory can't pledge tokens to anyone
        vm.prank(mallory);
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        token.pledge(bob, 30e6);

        // others can't pledge mallory's tokens, even if she's approved them
        vm.prank(mallory);
        token.approve(bob, 50e6);
        vm.prank(bob);
        vm.expectRevert(USTB.InsufficientPermissions.selector);
        token.pledgeFrom(mallory, charlie, 30e6);
    }

    function testPauseAndUnpauseRevertIfUnauthorized() public {
        // try pausing contract from unauthorized sender
        vm.prank(charlie);
        vm.expectRevert(USTB.Unauthorized.selector);
        token.pause();

        // admin pauses the contract
        token.pause();

        // try unpausing contract from unauthorized sender
        vm.prank(charlie);
        vm.expectRevert(USTB.Unauthorized.selector);
        token.unpause();

        // admin unpauses
        token.unpause();
    }

    function testAdminPauseAndUnpauseRevertIfUnauthorized() public {
        // try pausing contract from unauthorized sender
        vm.prank(charlie);
        vm.expectRevert(USTB.Unauthorized.selector);
        token.accountingPause();

        // admin pauses the contract
        vm.expectEmit(false, false, false, true);
        emit AccountingPaused(address(this));
        token.accountingPause();

        // try unpausing contract from unauthorized sender
        vm.prank(charlie);
        vm.expectRevert(USTB.Unauthorized.selector);
        token.accountingUnpause();

        // admin unpauses
        vm.expectEmit(false, false, false, true);
        emit AccountingUnpaused(address(this));
        token.accountingUnpause();
    }

    function testFunctionsStillWorkAfterUnpause() public {
        // admin pause, then unpause, confirm a few user funcs still work
        token.accountingPause();
        token.accountingUnpause();

        token.pause();  
        token.unpause();

        deal(address(token), alice, 100e6);
        deal(address(token), bob, 100e6);

        token.mint(bob, 30e6);
        token.burn(bob, 30e6);

        vm.prank(alice);
        token.transfer(bob, 30e6);

        vm.prank(bob);
        token.approve(charlie, 50e6);

        vm.prank(charlie);
        token.transferFrom(bob, alice, 30e6);

        vm.prank(alice);
        token.pledge(bob, 30e6);

        vm.prank(alice);
        token.approve(bob, 50e6);
        vm.prank(bob);
        token.pledgeFrom(alice, charlie, 30e6);

        vm.prank(bob);
        token.release(alice, 30e6);
    }

    // transfer, pledge, release should still work, but mint and burn should not
    function testAccountingPauseCorrectFunctionsWork() public {
        deal(address(token), alice, 100e6);
        deal(address(token), bob, 100e6);

        token.accountingPause();
        vm.expectRevert(USTB.AccountingIsPaused.selector);
        token.mint(alice, 30e6);
        vm.expectRevert(USTB.AccountingIsPaused.selector);
        token.burn(bob, 30e6);

        vm.prank(alice);
        token.pledge(bob, 10e6);

        vm.prank(alice);
        token.transfer(bob, 10e6);
    
        vm.prank(alice);
        token.approve(bob, 10e6);

        vm.prank(bob);
        token.pledgeFrom(alice, charlie, 10e6);

        vm.prank(charlie);
        token.release(alice, 10e6);

        vm.prank(bob);
        token.transferFrom(alice, bob, 10e6);
    }

    // mint/burn should still work, but transfer, pledge, release should not
    function testRegularPauseCorrectFunctionsWork() public {
        token.mint(alice, 100e6);
        token.burn(alice, 1e6);

        vm.prank(alice);
        token.pledge(bob, 20e6);

        token.pause();
        
        vm.prank(alice);
        vm.expectRevert(bytes("Pausable: paused"));
        token.transfer(bob, 1e6);

        vm.prank(bob);
        vm.expectRevert(bytes("Pausable: paused"));
        token.transferFrom(alice, bob, 10e6);

        vm.prank(alice);
        vm.expectRevert(bytes("Pausable: paused"));
        token.pledge(bob, 10e6);

        vm.prank(bob);
        vm.expectRevert(bytes("Pausable: paused"));
        token.pledgeFrom(alice, charlie, 10e6);

        // burn via transfer to 0, approve & release still works
        vm.prank(alice);
        token.transfer(address(tokenProxy), 1e6);

        vm.prank(alice);
        token.burn(1e6);

        vm.prank(alice);
        token.approve(bob, 10e6);

        vm.prank(bob);
        token.transferFrom(alice, address(tokenProxy), 1e6);

        vm.prank(bob);
        token.release(alice, 10e6);
    }

    // cannot double set any pause
    function testCannotDoublePause() public {
        token.accountingPause();
        vm.expectRevert(USTB.AccountingIsPaused.selector);
        token.accountingPause();

        token.pause();
        vm.expectRevert(bytes("Pausable: paused"));
        token.pause();
    }

    function testCannotDoubleUnpause() public {
        token.accountingPause();

        token.accountingUnpause();
        vm.expectRevert(USTB.AccountingIsNotPaused.selector);
        token.accountingUnpause();

        token.pause();

        token.unpause();
        vm.expectRevert(bytes("Pausable: not paused"));
        token.unpause();
    }

    function testCannotUpdateBalancesIfBothPaused() public {
        token.mint(alice, 100e6);

        vm.startPrank(alice);
        token.approve(bob, 50e6);
        token.approve(alice, 50e6);
        token.pledge(bob, 50e6);
        vm.stopPrank();

        token.accountingPause();

        assertEq(token.balanceOf(alice), 100e6);

        vm.expectRevert(USTB.AccountingIsPaused.selector);
        token.mint(alice, 100e6);

        vm.expectRevert(USTB.AccountingIsPaused.selector);
        token.burn(alice, 100e6);

        vm.prank(alice);
        vm.expectRevert(USTB.AccountingIsPaused.selector);
        token.transfer(address(tokenProxy), 50e6);

        vm.prank(alice);
        vm.expectRevert(USTB.AccountingIsPaused.selector);
        token.transferFrom(alice, address(tokenProxy), 50e6);

        vm.prank(alice);
        vm.expectRevert(USTB.AccountingIsPaused.selector);
        token.burn(10e6);

        token.accountingUnpause();
        token.pause();

        vm.prank(alice);
        vm.expectRevert(bytes("Pausable: paused"));
        token.transfer(bob, 50e6);

        vm.prank(alice);
        vm.expectRevert(bytes("Pausable: paused"));
        token.pledge(bob, 50e6);

        vm.prank(bob);
        vm.expectRevert(bytes("Pausable: paused"));
        token.transferFrom(alice, charlie, 50e6);

        vm.prank(bob);
        vm.expectRevert(bytes("Pausable: paused"));
        token.pledgeFrom(alice, charlie, 50e6);

        vm.prank(bob);
        token.release(alice, 50e6);

        assertEq(token.balanceOf(alice), 100e6);
    }

    function testUpgradingAllowListDoesNotAffectToken() public {
        AllowListV2 permsV2Implementation = new AllowListV2(address(this));
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(permsProxy)), address(permsV2Implementation));

        AllowListV2 permsV2 = AllowListV2(address(permsProxy));

        assertEq(address(token.allowList()), address(permsProxy));

        // check Alice, Bob, and Charlie still whitelisted
        assertEq(permsV2.getPermission(alice).isAllowed, true);
        assertEq(permsV2.getPermission(bob).isAllowed, true);
        assertEq(permsV2.getPermission(charlie).isAllowed, true);

        deal(address(token), alice, 100e6);
        deal(address(token), bob, 100e6);
        // check Alice, Bob, and Charlie can still do whitelisted operations (transfer, transferFrom, pledge, pledgeFrom)
        vm.prank(alice);
        token.transfer(bob, 10e6);

        assertEq(token.balanceOf(alice), 90e6);
        assertEq(token.balanceOf(bob), 110e6);

        vm.prank(bob);
        token.approve(alice, 40e6);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Release(bob, alice, 0e6);
        token.transferFrom(bob, charlie, 20e6);

        assertEq(token.balanceOf(bob), 90e6);
        assertEq(token.balanceOf(charlie), 20e6);

        vm.prank(bob);
        token.pledge(charlie, 20e6);

        vm.prank(alice);
        token.pledgeFrom(bob, charlie, 10e6);

        assertEq(token.pledgedAmounts(bob, charlie), 30e6);
    }

    function testUpgradingAllowListAndTokenWorks() public {
        AllowListV2 permsV2Implementation = new AllowListV2(address(this));
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(permsProxy)), address(permsV2Implementation));
        AllowListV2 permsV2 = AllowListV2(address(permsProxy));

        USTBV2 tokenV2Implementation = new USTBV2(address(this), permsV2);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenV2Implementation));
        USTBV2 tokenV2 = USTBV2(address(tokenProxy));

        // Whitelisting criteria now requires `state7` (newly added state) be true,
        // so Alice, Bob, and Charlie no longer have sufficient permissions...
        assertEq(tokenV2.hasSufficientPermissions(alice), false);
        assertEq(tokenV2.hasSufficientPermissions(bob), false);
        assertEq(tokenV2.hasSufficientPermissions(charlie), false);

        deal(address(tokenV2), alice, 100e6);
        deal(address(tokenV2), bob, 100e6);

        // ...and cannot do regular token operations (transfer, transferFrom, pledge, pledgeFrom)
        vm.prank(alice);
        vm.expectRevert(USTBV2.InsufficientPermissions.selector);
        tokenV2.transfer(bob, 10e6);

        vm.prank(charlie);
        vm.expectRevert("ERC20: insufficient allowance");
        tokenV2.transferFrom(alice, bob, 10e6);

        vm.prank(bob);
        vm.expectRevert(USTBV2.InsufficientPermissions.selector);
        tokenV2.pledge(charlie, 10e6);

        vm.prank(bob);
        tokenV2.approve(alice, 40e6);
        vm.prank(alice);
        vm.expectRevert(USTBV2.InsufficientPermissions.selector);
        tokenV2.pledgeFrom(bob, charlie, 10e6);

        // But when we whitelist all three according to the new criteria...
        AllowListV2.Permission memory newPerms = AllowListV2.Permission(true, false, false, false, false, false, false, true);
        permsV2.setPermission(abcEntityId, newPerms);

        // ...they now have sufficient permissions
        assertEq(tokenV2.hasSufficientPermissions(alice), true);
        assertEq(tokenV2.hasSufficientPermissions(bob), true);
        assertEq(tokenV2.hasSufficientPermissions(charlie), true);

        // ...and can now do regular token operations (transfer, transferFrom, pledge, pledgeFrom) without reverts
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
        tokenV2.pledge(charlie, 20e6);

        vm.prank(alice);
        tokenV2.pledgeFrom(bob, charlie, 10e6);

        assertEq(tokenV2.pledgedAmounts(bob, charlie), 30e6);
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
        vm.expectRevert(USTB.BadSignatory.selector);
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
        vm.expectRevert(USTB.BadSignatory.selector);
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
        vm.expectRevert(USTB.BadSignatory.selector);
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
        vm.expectRevert(USTB.BadSignatory.selector);
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
        vm.expectRevert(USTB.BadSignatory.selector);
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
        vm.expectRevert(USTB.BadSignatory.selector);
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
        vm.expectRevert(USTB.SignatureExpired.selector);
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
        vm.expectRevert(USTB.InvalidSignatureS.selector);
        token.permit(eve, bob, allowance, expiry, v, r, invalidS);

        // bob's allowance from eve is unchanged
        assertEq(token.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(token.nonces(eve), nonce);
    }

    function testPermitRevertsForInvalidV() public {
        // bob's allowance from eve is 0
        assertEq(token.allowance(eve, bob), 0);

        // eve signs an authorization with an invalid nonce
        uint256 allowance = 123e18;
        uint256 nonce = token.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);
        uint8 invalidV = 26; // should be 27 or 28

        // bob calls permit with the signature with an invalid nonce
        vm.prank(bob);
        vm.expectRevert(USTB.BadSignatory.selector);
        token.permit(eve, bob, allowance, expiry, invalidV, r, s);

        // bob's allowance from eve is unchanged
        assertEq(token.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(token.nonces(eve), nonce);
    }

    function testHasSufficientPermissions() public {
        assertTrue(token.hasSufficientPermissions(bob));
    }

    function testFuzzPledgedAmountMustBeRespected(uint amt, address spender, address recipient, address recipient2) public {
        AllowList.Permission memory allowPerms = AllowList.Permission(true, false, false, false, false, false);

        // cannot be address 0 - ERC20: transfer from the zero address
        // spender cannot be alice bob or charlie, they already have their permissions set
        vm.assume(spender != address(0) && spender != alice && spender != bob && spender != charlie);
        vm.assume(recipient != alice && recipient != bob && recipient != charlie);
        vm.assume(recipient2 != alice && recipient2 != bob && recipient2 != charlie);
        vm.assume(spender != recipient && recipient != recipient2 && spender != recipient2);
        vm.assume(recipient != address(0) && recipient2 != address(0));
        // proxy admin cant use protocol
        vm.assume(address(proxyAdmin) != spender && address(proxyAdmin) != recipient && address(proxyAdmin) != recipient2);

        // whitelist spender and recipients
        address[] memory addrs = new address[](3);
        addrs[0] = spender;
        addrs[1] = recipient;
        addrs[2] = recipient2;

        perms.setEntityIdForMultipleAddresses(2, addrs);
        perms.setPermission(2, allowPerms);

        // limit range of amount
        uint256 amount = bound(amt, 1, type(uint128).max -1);
        deal(address(token), spender, amount*2);

        // pledge tokens to spender
        vm.prank(spender);
        token.pledge(recipient, amount);

        // pledge tokens to spender
        vm.prank(spender);
        token.pledge(recipient2, amount);

        // recipient calls transferFrom on spender
        vm.prank(recipient);
        token.transferFrom(spender, recipient, amount);

        // recipient calls transferFrom on spender
        vm.prank(recipient2);
        token.transferFrom(spender, recipient2, amount);
    }
}
