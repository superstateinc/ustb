pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {SuperstateTokenV2} from "src/v2/SuperstateTokenV2.sol";
import {USTBv2} from "src/v2/USTBv2.sol";
import {AllowList} from "src/allowlist/AllowList.sol";
import {AllowListV1} from "src/allowlist/v1/AllowListV1.sol";
import {IAllowList} from "src/interfaces/allowlist/IAllowList.sol";
import {IAllowListV2} from "src/interfaces/allowlist/IAllowListV2.sol";
import "test/token/SuperstateTokenTestBase.t.sol";
import {ISuperstateTokenV4} from "src/interfaces/ISuperstateTokenV4.sol";
import {SuperstateTokenV3} from "src/v3/SuperstateTokenV3.sol";
import {SuperstateOracle} from "../../../lib/onchain-redemptions/src/oracle/SuperstateOracle.sol";
import {SuperstateTokenV4} from "src/v4/SuperstateTokenV4.sol";

contract USTBv4 is TokenTestBase {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed minter, address indexed to, uint256 amount);
    event AccountingPaused(address admin);
    event AccountingUnpaused(address admin);

    SuperstateTokenV1 public tokenV1;
    SuperstateTokenV2 public tokenV2;
    SuperstateTokenV3 public tokenV3;
    SuperstateTokenV4 public tokenV4;
    SuperstateOracle public oracle;

    ProxyAdmin permsProxyAdmin;
    TransparentUpgradeableProxy permsProxy;
    IAllowList public perms;
    ProxyAdmin tokenProxyAdmin;
    TransparentUpgradeableProxy tokenProxy;
    AllowList permsV2;
    ProxyAdmin permsProxyAdminV2;
    TransparentUpgradeableProxy permsProxyV2;

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant MAINNET_REDEMPTION_IDLE = 0x4c21B7577C8FE8b0B0669165ee7C8f67fa1454Cf;

    uint256 public constant INITIAL_MAX_ORACLE_DELAY = 1 hours;
    uint256 public constant MAXIMUM_ACCEPTABLE_PRICE_DELTA = 1_000_000;

    address alice = address(10);
    address bob = address(11);
    address charlie = address(12);
    address mallory = address(13);
    uint256 evePrivateKey = 0x353;
    address eve; // see setup()

    uint256 abcEntityId = 1;

    bytes32 internal constant AUTHORIZATION_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public virtual  {
        string memory rpcUrl = vm.envString("RPC_URL");

        uint256 mainnetFork = vm.createFork(rpcUrl, 20_993_400);
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

        vm.warp(1_726_779_601);

        eve = vm.addr(evePrivateKey);

        AllowListV1 permsImplementation = new AllowListV1(address(this));

        // deploy proxy contract and point it to implementation
        permsProxy = new TransparentUpgradeableProxy(address(permsImplementation), address(this), "");
        permsProxyAdmin = ProxyAdmin(getAdminAddress(address(permsProxy)));

        // wrap in ABI to support easier calls
        perms = AllowListV1(address(permsProxy));

        USTBv1 tokenV1Implementation = new USTBv1(address(this), AllowListV1(address(perms)));

        // repeat for the token contract
        tokenProxy = new TransparentUpgradeableProxy(address(tokenV1Implementation), address(this), "");
        tokenProxyAdmin = ProxyAdmin(getAdminAddress(address(tokenProxy)));

        // wrap in ABI to support easier calls
        tokenV1 = USTBv1(address(tokenProxy));

        // initialize token contract
        tokenV1.initialize("Superstate Short Duration US Government Securities Fund", "USTB");

        // whitelist alice bob, and charlie (so they can tranfer to each other), but not mallory
        IAllowList.Permission memory allowPerms = IAllowList.Permission(true, false, false, false, false, false);

        perms.setEntityIdForAddress(abcEntityId, alice);
        perms.setEntityIdForAddress(abcEntityId, bob);
        address[] memory addrs = new address[](1);
        addrs[0] = charlie;
        perms.setEntityPermissionAndAddresses(abcEntityId, addrs, allowPerms);

        // Now upgrade to V2
        tokenV2 = new USTBv2(address(this), AllowListV1(address(perms)));
        tokenProxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenV2), "");

        /*
            At this point, owner() is 0x00 because the upgraded contract has not
            initialized.

            admin() is the same from the prior version of the contract
        */

        // initialize v2 of the contract, specifically the new authorization
        // mechanism via owner()
        tokenV2 = USTBv2(address(tokenProxy));
        SuperstateTokenV2(address(tokenV2)).initializeV2();

        /*
            At this point, owner() is the same as admin() and is the source of truth
            for authorization. admin() will no longer be used, and for future versions of the contract it need
            not even be initialized.
        */

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

        // Now upgrade token to V3
        SuperstateTokenV3 tokenImplementation = new SuperstateTokenV3();
        tokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenImplementation), ""
        );

        tokenV3 = SuperstateTokenV3(address(tokenProxy));

        // Initialize token v3
        tokenV3.initializeV3(permsV2);

        // Set up oracle
        oracle = new SuperstateOracle(address(this), address(tokenV3), MAXIMUM_ACCEPTABLE_PRICE_DELTA);
        oracle.addCheckpoint(1726779600, 1726779601, 10_374_862, false);

        vm.warp(1726866001);

        oracle.addCheckpoint(uint64(1726866000), 1726866001, 10_379_322, false);

        // Configure token with oracle
        tokenV3.setOracle(address(oracle));
        tokenV3.setMaximumOracleDelay(INITIAL_MAX_ORACLE_DELAY);
        // USDC
        tokenV3.setStablecoinConfig(USDC, address(this), 0);

        // Upgrade to v4
        SuperstateTokenV4 tokenImplementationV4 = new SuperstateTokenV4();

        tokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenImplementationV4), ""
        );

        tokenV4 = SuperstateTokenV4(address(tokenProxy));

        vm.expectEmit(true, true, true, true);
        emit ISuperstateTokenV4.SetRedemptionContract(address(0), MAINNET_REDEMPTION_IDLE);
        tokenV4.setRedemptionContract(MAINNET_REDEMPTION_IDLE);

        vm.expectEmit(true, true, true, true);
        emit ISuperstateTokenV4.SetChainIdSupport(9000, false, true);
        tokenV4.setChainIdSupport(9000, true);

        vm.expectEmit(true, true, true, true);
        emit ISuperstateTokenV4.SetChainIdSupport(42161, false, true);
        tokenV4.setChainIdSupport(42161, true);

        vm.expectEmit(true, true, true, true);
        emit ISuperstateTokenV4.SetChainIdSupport(0, false, true);
        tokenV4.setChainIdSupport(0, true);
    }

    function testTokenName() public virtual {
        assertEq(tokenV4.name(), "Superstate Short Duration US Government Securities Fund");
    }

    function testTokenSymbol() public virtual {
        assertEq(tokenV4.symbol(), "USTB");
    }

    function testTokenDecimals() public {
        assertEq(tokenV4.decimals(), 6);
    }

    function testTokenIsInitializedAsUnpaused() public {
        assertEq(tokenV4.paused(), false);
    }

    function testTransferRevertInsufficentBalance() public {
        deal(address(tokenV4), alice, 100e6);
        vm.startPrank(alice);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        tokenV4.transfer(bob, 101e6);

        vm.stopPrank();
    }

    function testTransferFromRevertInsufficentBalance() public {
        deal(address(tokenV4), alice, 100e6);

        // someone attempts to transfer alice's entire balance
        vm.expectRevert("ERC20: insufficient allowance");
        tokenV4.transferFrom(alice, bob, 100e6);
    }

    function testTransferFromInsufficientAllowance() public {
        deal(address(tokenV4), alice, 100e6);

        uint256 approvedAmount = 20e6;
        uint256 transferAmount = 40e6;

        vm.startPrank(alice);

        // she also grants him an approval
        tokenV4.approve(bob, approvedAmount);

        vm.stopPrank();

        assertEq(tokenV4.balanceOf(alice), 100e6);
        assertEq(tokenV4.allowance(alice, bob), approvedAmount);
        assertEq(tokenV4.balanceOf(charlie), 0);

        // bob tries to transfer more than his encumbered and allowed balances
        vm.prank(bob);
        vm.expectRevert();
        tokenV4.transferFrom(alice, charlie, transferAmount);
    }

    function testTransferFromSrcRemoveFromAllowlist() public {
        deal(address(tokenV4), alice, 100e6);

        uint256 approvedAmount = 20e6;

        vm.startPrank(alice);
        // she also grants him an approval
        tokenV4.approve(bob, approvedAmount);
        vm.stopPrank();

        permsV2.setEntityAllowedForFund(IAllowListV2.EntityId.wrap(abcEntityId), tokenV4.symbol(), false);

        // bob tries to transfer from but alice is no longe ron allowed list
        vm.prank(bob);
        vm.expectRevert(ISuperstateTokenV4.InsufficientPermissions.selector);
        tokenV4.transferFrom(alice, charlie, approvedAmount);
    }

    function testMint() public {
        // emits transfer and mint events
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, 100e6);
        vm.expectEmit();
        emit Mint(address(this), alice, 100e6);

        tokenV4.mint(alice, 100e6);
        assertEq(tokenV4.balanceOf(alice), 100e6);
    }

    function testMintRevertBadCaller() public {
        vm.prank(alice);
        vm.expectRevert();
        tokenV4.mint(bob, 100e6);

        assertEq(tokenV4.balanceOf(bob), 0);
    }

    function testMintRevertInsufficientPermissions() public {
        // cannot mint to Mallory since un-whitelisted
        vm.expectRevert(ISuperstateTokenV4.InsufficientPermissions.selector);
        tokenV4.mint(mallory, 100e6);
    }

    function testBulkMint() public {
        address[] memory dsts = new address[](2);
        dsts[0] = alice;
        dsts[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = 333e6;

        // emits transfer and mint events
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, 100e6);
        vm.expectEmit();
        emit Mint(address(this), alice, 100e6);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), bob, 333e6);
        vm.expectEmit();
        emit Mint(address(this), bob, 333e6);
        tokenV4.bulkMint(dsts, amounts);
        assertEq(tokenV4.balanceOf(alice), 100e6);
        assertEq(tokenV4.balanceOf(bob), 333e6);
    }

    function testBulkMintRevertUnauthorized() public {
        address[] memory dsts = new address[](2);
        dsts[0] = alice;
        dsts[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = 333e6;

        vm.prank(alice);
        vm.expectRevert();
        tokenV4.bulkMint(dsts, amounts);

        assertEq(tokenV4.balanceOf(alice), 0);
        assertEq(tokenV4.balanceOf(bob), 0);
    }

    function testBulkMintRevertAccountingPaused() public {
        address[] memory dsts = new address[](2);
        dsts[0] = alice;
        dsts[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = 333e6;

        tokenV4.accountingPause();

        vm.expectRevert(ISuperstateTokenV4.AccountingIsPaused.selector);
        tokenV4.bulkMint(dsts, amounts);

        assertEq(tokenV4.balanceOf(alice), 0);
        assertEq(tokenV4.balanceOf(bob), 0);
    }

    function testBulkMintRevertInsufficientPermissions() public {
        address[] memory dsts = new address[](2);
        dsts[0] = mallory;
        dsts[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = 333e6;

        // cannot mint to Mallory since un-whitelisted
        vm.expectRevert(ISuperstateTokenV4.InsufficientPermissions.selector);
        tokenV4.bulkMint(dsts, amounts);

        assertEq(tokenV4.balanceOf(mallory), 0);
        assertEq(tokenV4.balanceOf(bob), 0);
    }

    function testBulkMintRevertInvalidArgumentLengths() public {
        address[] memory dsts = new address[](2);
        dsts[0] = alice;
        dsts[1] = bob;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e6;

        vm.expectRevert(ISuperstateTokenV4.InvalidArgumentLengths.selector);
        tokenV4.bulkMint(dsts, amounts);

        address[] memory dsts1 = new address[](1);
        dsts1[0] = alice;

        uint256[] memory amounts1 = new uint256[](2);
        amounts1[0] = 100e6;
        amounts1[1] = 333e6;

        vm.expectRevert(ISuperstateTokenV4.InvalidArgumentLengths.selector);
        tokenV4.bulkMint(dsts1, amounts1);

        address[] memory dsts2 = new address[](0);
        uint256[] memory amounts2 = new uint256[](0);

        vm.expectRevert(ISuperstateTokenV4.InvalidArgumentLengths.selector);
        tokenV4.bulkMint(dsts2, amounts2);
    }

    function testAdminBurn() public {
        deal(address(tokenV4), alice, 100e6);

        assertEq(tokenV4.balanceOf(alice), 100e6);

        // emits Transfer and AdminBurn events
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 100e6);
        vm.expectEmit();
        emit ISuperstateTokenV4.AdminBurn(address(this), alice, 100e6);

        tokenV4.adminBurn(alice, 100e6);
        assertEq(tokenV4.balanceOf(alice), 0);
    }

    function testOffchainRedeemUsingTransfer() public {
        deal(address(tokenV4), alice, 100e6);

        assertEq(tokenV4.balanceOf(alice), 100e6);

        // emits Transfer and OffchainRedeem events
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 50e6);
        vm.expectEmit();
        emit ISuperstateTokenV4.OffchainRedeem(alice, alice, 50e6);

        // alice calls transfer(0, amount) to self-burn
        vm.prank(alice);
        tokenV4.transfer(address(tokenProxy), 50e6);

        assertEq(tokenV4.balanceOf(alice), 50e6);
    }

    function testSelfOffchainRedeem() public {
        deal(address(tokenV4), alice, 100e6);

        assertEq(tokenV4.balanceOf(alice), 100e6);

        // emits Transfer and OffchainRedeem events
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 50e6);
        vm.expectEmit();
        emit ISuperstateTokenV4.OffchainRedeem(alice, alice, 50e6);

        // alice calls burn(amount) to self-burn
        vm.prank(alice);
        tokenV4.offchainRedeem(50e6);

        assertEq(tokenV4.balanceOf(alice), 50e6);
    }

    function testSelfOffchainRedeemUsingTransferFrom() public {
        deal(address(tokenV4), alice, 100e6);

        assertEq(tokenV4.balanceOf(alice), 100e6);

        vm.prank(alice);
        tokenV4.approve(bob, 50e6);

        // emits Transfer and OffchainRedeem events
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 50e6);
        vm.expectEmit();
        emit ISuperstateTokenV4.OffchainRedeem(bob, alice, 50e6);

        // bob calls transferFrom(alice, 0, amount) to self-burn
        vm.prank(bob);
        tokenV4.transferFrom(alice, address(tokenProxy), 50e6);

        assertEq(tokenV4.balanceOf(alice), 50e6);
        assertEq(tokenV4.allowance(alice, bob), 0e6, "bob's allowance for alice's tokens is spent");
    }

    function testAdminBurnRevertBadCaller() public {
        vm.prank(alice);
        vm.expectRevert();
        tokenV4.adminBurn(bob, 100e6);
    }

    function testSelfOffchainRedeemRevertInsufficientBalance() public {
        deal(address(tokenV4), alice, 100e6);
        assertEq(tokenV4.balanceOf(alice), 100e6);

        // alice tries to burn more than her balance
        vm.prank(alice);

        vm.expectRevert("ERC20: burn amount exceeds balance");
        tokenV4.offchainRedeem(200e6);
    }

    function testAdminBurnRevertInsufficientBalance() public {
        deal(address(tokenV4), alice, 100e6);
        assertEq(tokenV4.balanceOf(alice), 100e6);

        vm.prank(address(this));

        // alice tries to burn more than her available balance
        vm.expectRevert("ERC20: burn amount exceeds balance");
        tokenV4.adminBurn(alice, 101e6);
    }

    function testOffchainRedeemRevertOwnerInsufficientPermissions() public {
        deal(address(tokenV4), mallory, 100e6);

        // mallory tries to burn her tokens, but isn't whitelisted
        vm.prank(mallory);
        vm.expectRevert(ISuperstateTokenV4.InsufficientPermissions.selector);
        tokenV4.offchainRedeem(50e6);
    }

    function testTransferToZeroReverts() public {
        deal(address(tokenV4), alice, 100e6);
        vm.expectRevert(ISuperstateTokenV4.InsufficientPermissions.selector);
        vm.prank(alice);
        tokenV4.transfer(address(0), 10e6);
    }

    function testTransferFromToZeroReverts() public {
        deal(address(tokenV4), alice, 100e6);
        vm.prank(alice);
        tokenV4.approve(bob, 50e6);
        vm.prank(bob);
        vm.expectRevert(ISuperstateTokenV4.InsufficientPermissions.selector);
        tokenV4.transferFrom(alice, address(0), 10e6);
    }

    function testTransferRevertSenderInsufficientPermissions() public {
        deal(address(tokenV4), mallory, 100e6);

        // mallory tries to transfer tokens, but isn't whitelisted
        vm.prank(mallory);
        vm.expectRevert(ISuperstateTokenV4.InsufficientPermissions.selector);
        tokenV4.transfer(charlie, 30e6);
    }

    function testTransferRevertReceiverInsufficientPermissions() public {
        deal(address(tokenV4), alice, 100e6);

        // alice tries to transfer tokens to mallory, but mallory isn't whitelisted
        vm.prank(alice);
        vm.expectRevert(ISuperstateTokenV4.InsufficientPermissions.selector);
        tokenV4.transfer(mallory, 30e6);
    }

    function testTransferFromRevertReceiverInsufficientPermissions() public {
        deal(address(tokenV4), alice, 100e6);

        // alice grants bob an approval
        vm.prank(alice);
        tokenV4.approve(bob, 50e6);

        // bob tries to transfer alice's tokens to mallory, but mallory isn't whitelisted
        vm.prank(bob);
        vm.expectRevert(ISuperstateTokenV4.InsufficientPermissions.selector);
        tokenV4.transferFrom(alice, mallory, 50e6);
    }

    function testPauseAndUnpauseRevertIfUnauthorized() public {
        // try pausing contract from unauthorized sender
        vm.prank(charlie);
        vm.expectRevert();
        tokenV4.pause();

        // admin pauses the contract
        tokenV4.pause();

        // try unpausing contract from unauthorized sender
        vm.prank(charlie);
        vm.expectRevert();
        tokenV4.unpause();

        // admin unpauses
        tokenV4.unpause();
    }

    function testAdminPauseAndUnpauseRevertIfUnauthorized() public {
        // try pausing contract from unauthorized sender
        vm.prank(charlie);
        vm.expectRevert();
        tokenV4.accountingPause();

        // admin pauses the contract
        vm.expectEmit(false, false, false, true);
        emit AccountingPaused(address(this));
        tokenV4.accountingPause();

        // try unpausing contract from unauthorized sender
        vm.prank(charlie);
        vm.expectRevert();
        tokenV4.accountingUnpause();

        // admin unpauses
        vm.expectEmit(false, false, false, true);
        emit AccountingUnpaused(address(this));
        tokenV4.accountingUnpause();
    }

    function testFunctionsStillWorkAfterUnpause() public {
        // admin pause, then unpause, confirm a few user funcs still work
        tokenV4.accountingPause();
        tokenV4.accountingUnpause();

        tokenV4.pause();
        tokenV4.unpause();

        deal(address(tokenV4), alice, 100e6);
        deal(address(tokenV4), bob, 100e6);

        tokenV4.mint(bob, 30e6);
        tokenV4.adminBurn(bob, 30e6);

        vm.prank(alice);
        tokenV4.transfer(bob, 30e6);

        vm.prank(bob);
        tokenV4.approve(charlie, 50e6);

        vm.prank(charlie);
        tokenV4.transferFrom(bob, alice, 30e6);

        vm.prank(alice);
        tokenV4.approve(bob, 50e6);
    }

    // transfer, encumber, release should still work, but mint and burn should not
    function testAccountingPauseCorrectFunctionsWork() public {
        deal(address(tokenV4), alice, 100e6);
        deal(address(tokenV4), bob, 100e6);

        tokenV4.accountingPause();
        vm.expectRevert(ISuperstateTokenV4.AccountingIsPaused.selector);
        tokenV4.mint(alice, 30e6);
        vm.expectRevert(ISuperstateTokenV4.AccountingIsPaused.selector);
        tokenV4.adminBurn(bob, 30e6);

        vm.prank(alice);
        tokenV4.transfer(bob, 10e6);

        vm.prank(alice);
        tokenV4.approve(bob, 10e6);

        vm.prank(bob);
        tokenV4.transferFrom(alice, bob, 10e6);
    }

    // mint/burn should still work, but transfer, encumber, release should not
    function testRegularPauseCorrectFunctionsWork() public {
        tokenV4.mint(alice, 100e6);
        tokenV4.adminBurn(alice, 1e6);

        tokenV4.pause();

        vm.prank(alice);
        vm.expectRevert(bytes("Pausable: paused"));
        tokenV4.transfer(bob, 1e6);

        vm.prank(bob);
        vm.expectRevert(bytes("Pausable: paused"));
        tokenV4.transferFrom(alice, bob, 10e6);

        // burn via transfer to 0, approve & release still works
        vm.prank(alice);
        tokenV4.transfer(address(tokenProxy), 1e6);

        vm.prank(alice);
        tokenV4.offchainRedeem(1e6);

        vm.prank(alice);
        tokenV4.approve(bob, 10e6);

        vm.prank(bob);
        tokenV4.transferFrom(alice, address(tokenProxy), 1e6);
    }

    // cannot double set any pause
    function testCannotDoublePause() public {
        tokenV4.accountingPause();
        vm.expectRevert(ISuperstateTokenV4.AccountingIsPaused.selector);
        tokenV4.accountingPause();

        tokenV4.pause();
        vm.expectRevert(bytes("Pausable: paused"));
        tokenV4.pause();
    }

    function testCannotDoubleUnpause() public {
        tokenV4.accountingPause();

        tokenV4.accountingUnpause();
        vm.expectRevert(ISuperstateTokenV4.AccountingIsNotPaused.selector);
        tokenV4.accountingUnpause();

        tokenV4.pause();

        tokenV4.unpause();
        vm.expectRevert(bytes("Pausable: not paused"));
        tokenV4.unpause();
    }

    function testCannotUpdateBalancesIfBothPaused() public {
        tokenV4.mint(alice, 100e6);

        vm.startPrank(alice);
        tokenV4.approve(bob, 50e6);
        tokenV4.approve(alice, 50e6);
        vm.stopPrank();

        tokenV4.accountingPause();

        assertEq(tokenV4.balanceOf(alice), 100e6);

        vm.expectRevert(ISuperstateTokenV4.AccountingIsPaused.selector);
        tokenV4.mint(alice, 100e6);

        vm.expectRevert(ISuperstateTokenV4.AccountingIsPaused.selector);
        tokenV4.adminBurn(alice, 100e6);

        vm.prank(alice);
        vm.expectRevert(ISuperstateTokenV4.AccountingIsPaused.selector);
        tokenV4.transfer(address(tokenProxy), 50e6);

        vm.prank(alice);
        vm.expectRevert(ISuperstateTokenV4.AccountingIsPaused.selector);
        tokenV4.transferFrom(alice, address(tokenProxy), 50e6);

        vm.prank(alice);
        vm.expectRevert(ISuperstateTokenV4.AccountingIsPaused.selector);
        tokenV4.offchainRedeem(10e6);

        tokenV4.accountingUnpause();
        tokenV4.pause();

        vm.prank(alice);
        vm.expectRevert(bytes("Pausable: paused"));
        tokenV4.transfer(bob, 50e6);

        vm.prank(bob);
        vm.expectRevert(bytes("Pausable: paused"));
        tokenV4.transferFrom(alice, charlie, 50e6);

        assertEq(tokenV4.balanceOf(alice), 100e6);
    }

    function eveAuthorization(uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (uint8, bytes32, bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, eve, bob, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", tokenV4.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(evePrivateKey, digest);
    }

    function testPermit() public {
        // bob's allowance from eve is 0
        assertEq(tokenV4.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = tokenV4.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature
        vm.prank(bob);
        tokenV4.permit(eve, bob, allowance, expiry, v, r, s);

        // bob's allowance from eve equals allowance
        assertEq(tokenV4.allowance(eve, bob), allowance);

        // eve's nonce is incremented
        assertEq(tokenV4.nonces(eve), nonce + 1);
    }

    function testPermitRevertsForBadOwner() public {
        // bob's allowance from eve is 0
        assertEq(tokenV4.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = tokenV4.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the owner
        vm.prank(bob);
        vm.expectRevert(ISuperstateTokenV4.BadSignatory.selector);
        tokenV4.permit(charlie, bob, allowance, expiry, v, r, s);

        // bob's allowance from eve is unchanged
        assertEq(tokenV4.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(tokenV4.nonces(eve), nonce);
    }

    function testPermitRevertsForBadSpender() public {
        // bob's allowance from eve is 0
        assertEq(tokenV4.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = tokenV4.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the spender
        vm.prank(bob);
        vm.expectRevert(ISuperstateTokenV4.BadSignatory.selector);
        tokenV4.permit(eve, charlie, allowance, expiry, v, r, s);

        // bob's allowance from eve is unchanged
        assertEq(tokenV4.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(tokenV4.nonces(eve), nonce);
    }

    function testPermitRevertsForBadAmount() public {
        // bob's allowance from eve is 0
        assertEq(tokenV4.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = tokenV4.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the allowance
        vm.prank(bob);
        vm.expectRevert(ISuperstateTokenV4.BadSignatory.selector);
        tokenV4.permit(eve, bob, allowance + 1 wei, expiry, v, r, s);

        // bob's allowance from eve is unchanged
        assertEq(tokenV4.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(tokenV4.nonces(eve), nonce);
    }

    function testPermitRevertsForBadExpiry() public {
        // bob's allowance from eve is 0
        assertEq(tokenV4.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = tokenV4.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the expiry
        vm.prank(bob);
        vm.expectRevert(ISuperstateTokenV4.BadSignatory.selector);
        tokenV4.permit(eve, bob, allowance, expiry + 1, v, r, s);

        // bob's allowance from eve is unchanged
        assertEq(tokenV4.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(tokenV4.nonces(eve), nonce);
    }

    function testPermitRevertsForBadNonce() public {
        // bob's allowance from eve is 0
        assertEq(tokenV4.allowance(eve, bob), 0);

        // eve signs an authorization with an invalid nonce
        uint256 allowance = 123e18;
        uint256 nonce = tokenV4.nonces(eve);
        uint256 badNonce = nonce + 1;
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, badNonce, expiry);

        // bob calls permit with the signature with an invalid nonce
        vm.prank(bob);
        vm.expectRevert(ISuperstateTokenV4.BadSignatory.selector);
        tokenV4.permit(eve, bob, allowance, expiry, v, r, s);

        // bob's allowance from eve is unchanged
        assertEq(tokenV4.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(tokenV4.nonces(eve), nonce);
    }

    function testPermitRevertsOnRepeatedCall() public {
        // bob's allowance from eve is 0
        assertEq(tokenV4.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = tokenV4.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature
        vm.prank(bob);
        tokenV4.permit(eve, bob, allowance, expiry, v, r, s);

        // bob's allowance from eve equals allowance
        assertEq(tokenV4.allowance(eve, bob), allowance);

        // eve's nonce is incremented
        assertEq(tokenV4.nonces(eve), nonce + 1);

        // eve revokes bob's allowance
        vm.prank(eve);
        tokenV4.approve(bob, 0);
        assertEq(tokenV4.allowance(eve, bob), 0);

        // bob tries to reuse the same signature twice
        vm.prank(bob);
        vm.expectRevert(ISuperstateTokenV4.BadSignatory.selector);
        tokenV4.permit(eve, bob, allowance, expiry, v, r, s);

        // bob's allowance from eve is unchanged
        assertEq(tokenV4.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(tokenV4.nonces(eve), nonce + 1);
    }

    function testPermitRevertsForExpiredSignature() public {
        // bob's allowance from eve is 0
        assertEq(tokenV4.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = tokenV4.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);

        // the expiry block arrives
        vm.warp(expiry + 1);

        // bob calls permit with the signature after the expiry
        vm.prank(bob);
        vm.expectRevert(ISuperstateTokenV4.SignatureExpired.selector);
        tokenV4.permit(eve, bob, allowance, expiry, v, r, s);

        // bob's allowance from eve is unchanged
        assertEq(tokenV4.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(tokenV4.nonces(eve), nonce);
    }

    function testPermitRevertsInvalidS() public {
        // bob's allowance from eve is 0
        assertEq(tokenV4.allowance(eve, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = tokenV4.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r,) = eveAuthorization(allowance, nonce, expiry);

        // 1 greater than the max value of s
        bytes32 invalidS = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1;

        // bob calls permit with the signature with invalid `s` value
        vm.prank(bob);
        vm.expectRevert(ISuperstateTokenV4.InvalidSignatureS.selector);
        tokenV4.permit(eve, bob, allowance, expiry, v, r, invalidS);

        // bob's allowance from eve is unchanged
        assertEq(tokenV4.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(tokenV4.nonces(eve), nonce);
    }

    function testPermitRevertsForInvalidV() public {
        // bob's allowance from eve is 0
        assertEq(tokenV4.allowance(eve, bob), 0);

        // eve signs an authorization with an invalid nonce
        uint256 allowance = 123e18;
        uint256 nonce = tokenV4.nonces(eve);
        uint256 expiry = block.timestamp + 1000;

        (, bytes32 r, bytes32 s) = eveAuthorization(allowance, nonce, expiry);
        uint8 invalidV = 26; // should be 27 or 28

        // bob calls permit with the signature with an invalid nonce
        vm.prank(bob);
        vm.expectRevert(ISuperstateTokenV4.BadSignatory.selector);
        tokenV4.permit(eve, bob, allowance, expiry, invalidV, r, s);

        // bob's allowance from eve is unchanged
        assertEq(tokenV4.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(tokenV4.nonces(eve), nonce);
    }

    function testHasSufficientPermissions() public {
        assertTrue(tokenV4.isAllowed(bob));
    }

    /// v3 tests following

    function testUpdateOracleNotOwner() public {
        hoax(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenV4.setOracle(address(1));
    }

    function testUpdateOracleSameAddress() public {
        vm.expectRevert(ISuperstateTokenV4.BadArgs.selector);
        tokenV4.setOracle(address(oracle));
    }

    function testSetMaximumOracleDelayNotOwner() public {
        hoax(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenV4.setMaximumOracleDelay(1);
    }

    function testSetMaximumOracleDelaySameDelay() public {
        vm.expectRevert(ISuperstateTokenV4.BadArgs.selector);
        tokenV4.setMaximumOracleDelay(INITIAL_MAX_ORACLE_DELAY);
    }

    function testSetStablecoinConfigNotOwner() public {
        hoax(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenV4.setStablecoinConfig(address(0), address(0), 0);
    }

    function testSetStablecoinConfigFeeTooHigh() public {
        vm.expectRevert(ISuperstateTokenV4.FeeTooHigh.selector);
        tokenV4.setStablecoinConfig(address(0), address(0), 11);
    }

    function testSetStablecoinConfigAllArgsIdentical() public {
        vm.expectRevert(ISuperstateTokenV4.BadArgs.selector);
        tokenV4.setStablecoinConfig(address(0), address(0), 0);
    }

    // subscribe
    function testSubscribeInAmountZero() public {
        hoax(eve);
        vm.expectRevert(ISuperstateTokenV4.BadArgs.selector);
        tokenV4.subscribe(0, USDC);
    }

    function testSubscribeStablecoinNotSupported() public {
        hoax(eve);
        vm.expectRevert(ISuperstateTokenV4.StablecoinNotSupported.selector);
        tokenV4.subscribe(1, USDT);
    }

    function testSubscribePaused() public {
        tokenV4.pause();

        hoax(eve);
        vm.expectRevert("Pausable: paused");
        tokenV4.subscribe(1, USDC);
    }

    function testSubscribeAccountingPaused() public {
        tokenV4.accountingPause();

        hoax(eve);
        vm.expectRevert(ISuperstateTokenV4.AccountingIsPaused.selector);
        tokenV4.subscribe(1, USDC);
    }

    function testSubscribeZeroSuperstateTokensOut() public {
        uint256 amount = 10;
        deal(address(USDC), alice, amount);

        vm.startPrank(alice);

        IERC20(USDC).approve(address(tokenV4), amount);

        vm.expectRevert(ISuperstateTokenV4.ZeroSuperstateTokensOut.selector);
        tokenV4.subscribe(amount, USDC);

        vm.stopPrank();
    }

    function testSubscribeNotAllowed() public {
        vm.warp(1726866001 + 1 days);

        address faker = address(123456);

        uint256 usdcAmountIn = 10_000_000; // $10
        deal(address(USDC), faker, usdcAmountIn);

        vm.startPrank(faker);

        IERC20(USDC).approve(address(tokenV4), usdcAmountIn);

        vm.expectRevert(ISuperstateTokenV4.InsufficientPermissions.selector);
        tokenV4.subscribe(usdcAmountIn, USDC);
    }

    function testSubscribeHappyPath() public {
        vm.warp(1726866001 + 1 days);

        uint256 usdcAmountIn = 10_000_000; // $10
        uint256 ustbAmountOut = 963_040;
        deal(address(USDC), alice, usdcAmountIn);

        vm.startPrank(alice);

        IERC20(USDC).approve(address(tokenV4), usdcAmountIn);

        vm.expectEmit(true, true, true, true);
        emit ISuperstateTokenV4.Subscribe({
            subscriber: alice,
            stablecoin: USDC,
            stablecoinInAmount: usdcAmountIn,
            stablecoinInAmountAfterFee: usdcAmountIn,
            superstateTokenOutAmount: ustbAmountOut
        });
        tokenV4.subscribe(usdcAmountIn, USDC);

        vm.stopPrank();

        assertEq(tokenV4.balanceOf(alice), ustbAmountOut);
        assertEq(IERC20(USDC).balanceOf(address(this)), usdcAmountIn);
    }

    function testSubscribeHappyPathFee() public {
        vm.warp(1726866001 + 1 days);
        tokenV4.setStablecoinConfig(USDC, address(this), 10);

        uint256 usdcAmountIn = 10_000_000; // $10
        uint256 usdcAmountFee = 10_000; // 1 cent
        uint256 ustbAmountOut = 962_077; // minus 10 bps fee on the incoming usdc
        deal(address(USDC), alice, usdcAmountIn);

        vm.startPrank(alice);

        IERC20(USDC).approve(address(tokenV4), usdcAmountIn);

        vm.expectEmit(true, true, true, true);
        emit ISuperstateTokenV4.Subscribe({
            subscriber: alice,
            stablecoin: USDC,
            stablecoinInAmount: usdcAmountIn,
            stablecoinInAmountAfterFee: usdcAmountIn - usdcAmountFee,
            superstateTokenOutAmount: ustbAmountOut
        });
        tokenV4.subscribe(usdcAmountIn, USDC);

        vm.stopPrank();

        assertEq(tokenV4.balanceOf(alice), ustbAmountOut);
        assertEq(IERC20(USDC).balanceOf(address(this)), usdcAmountIn);
    }

    function testGetChainlinkPriceOnchainSubscriptionsDisabled() public {
        tokenV4.setOracle(address(0));

        vm.expectRevert(ISuperstateTokenV4.OnchainSubscriptionsDisabled.selector);
        tokenV4.getChainlinkPrice();
    }

    function testUpgradingAllowListDoesNotAffectToken() public {
        AllowList permsV2Implementation = new AllowList();
        permsProxyAdminV2.upgradeAndCall(
            ITransparentUpgradeableProxy(address(permsProxyV2)), address(permsV2Implementation), ""
        );

        AllowList permsV3 = AllowList(address(permsProxyV2));

        // check Alice, Bob, and Charlie still whitelisted
        assertTrue(permsV3.isAddressAllowedForFund(alice, "USTB"));
        assertTrue(permsV3.isAddressAllowedForFund(bob, "USTB"));
        assertTrue(permsV3.isAddressAllowedForFund(charlie, "USTB"));

        deal(address(tokenV4), alice, 100e6);
        deal(address(tokenV4), bob, 100e6);
        // check Alice, Bob, and Charlie can still do whitelisted operations (transfer, transferFrom, encumber, encumberFrom)
        vm.prank(alice);
        tokenV4.transfer(bob, 10e6);

        assertEq(tokenV4.balanceOf(alice), 90e6);
        assertEq(tokenV4.balanceOf(bob), 110e6);

        vm.prank(bob);
        tokenV4.approve(alice, 40e6);

        vm.prank(alice);
        tokenV4.transferFrom(bob, charlie, 20e6);

        assertEq(tokenV4.balanceOf(bob), 90e6);
        assertEq(tokenV4.balanceOf(charlie), 20e6);
    }

    function testRedemptionContract() public {
        assertEq(MAINNET_REDEMPTION_IDLE, tokenV4.redemptionContract());
    }

    //vm.expectEmit(true, true, true, true);
    //emitISuperstateTokenV4.SetRedemptionContract(address(0), MAINNET_REDEMPTION_IDLE);
    //tokenV4.setRedemptionContract(MAINNET_REDEMPTION_IDLE);

    function testRedemptionContractNotOwnerRevert() public {
        hoax(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenV4.setRedemptionContract(MAINNET_REDEMPTION_IDLE);
    }

    function testRedemptionContractAlreadySetRevert() public {
        vm.expectRevert(ISuperstateTokenV4.BadArgs.selector);
        tokenV4.setRedemptionContract(MAINNET_REDEMPTION_IDLE);
    }

    function testRedemptionContractSuccess() public {
        vm.expectEmit(true, true, true, true);
        emit ISuperstateTokenV4.SetRedemptionContract(MAINNET_REDEMPTION_IDLE, address(1234));
        tokenV4.setRedemptionContract(address(1234));
    }

    function testBridgeToBookEntrySuccess() public {
        tokenV4.mint(bob, 100e6);

        hoax(bob);
        vm.expectEmit(true, true, true, true);
        emit Transfer(bob, address(0), 100e6);
        emit ISuperstateTokenV4.Bridge(bob, bob, 100e6, address(0), string(new bytes(0)), 0);
        tokenV4.bridgeToBookEntry(100e6);
    }

    function testBridgeAmountZeroRevert() public {
        tokenV4.mint(bob, 100e6);

        hoax(bob);
        vm.expectRevert(ISuperstateTokenV4.ZeroSuperstateTokensOut.selector);
        tokenV4.bridge(0, bob, string(new bytes(0)), 9000);
    }

    function testBridgeOnchainDestinationSetForBridgeToBookEntryRevert() public {
        tokenV4.mint(bob, 100e6);

        hoax(bob);
        vm.expectRevert(ISuperstateTokenV4.OnchainDestinationSetForBridgeToBookEntry.selector);
        tokenV4.bridge(1, bob, string(new bytes(0)), 0);

        hoax(bob);
        vm.expectRevert(ISuperstateTokenV4.OnchainDestinationSetForBridgeToBookEntry.selector);
        tokenV4.bridge(1, address(0), "At3rMxZEKKkMeC7V52pL6WAAL9wSGpQ45usq84D3nAqv", 0);
    }

    function testBridgeTwoDestinationsRevert() public {
        tokenV4.mint(bob, 100e6);

        hoax(bob);
        vm.expectRevert(ISuperstateTokenV4.TwoDestinationsInvalid.selector);
        tokenV4.bridge(1, bob, "At3rMxZEKKkMeC7V52pL6WAAL9wSGpQ45usq84D3nAqv", 9000);

        hoax(bob);
        vm.expectRevert(ISuperstateTokenV4.TwoDestinationsInvalid.selector);
        tokenV4.bridge(1, bob, "At3rMxZEKKkMeC7V52pL6WAAL9wSGpQ45usq84D3nAqv", 0);
    }

    function testBridgeAccountingPausedRevert() public {
        tokenV4.mint(bob, 100e6);

        tokenV4.accountingPause();

        hoax(bob);
        vm.expectRevert(ISuperstateTokenV4.AccountingIsPaused.selector);
        tokenV4.bridge(1, bob, "At3rMxZEKKkMeC7V52pL6WAAL9wSGpQ45usq84D3nAqv", 9000);
    }

    function testBridgeUnauthorizedRevert() public {
        tokenV4.mint(bob, 100e6);

        permsV2.setEntityAllowedForFund(IAllowListV2.EntityId.wrap(abcEntityId), "USTB", false);

        hoax(bob);
        vm.expectRevert(ISuperstateTokenV4.InsufficientPermissions.selector);
        tokenV4.bridge(1, bob, "At3rMxZEKKkMeC7V52pL6WAAL9wSGpQ45usq84D3nAqv", 9000);
    }

    function testBridgeSuccess() public {
        tokenV4.mint(bob, 100e6);

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit Transfer(bob, address(0), 1);
        emit ISuperstateTokenV4.Bridge({
            caller: bob,
            src: bob,
            amount: 1,
            ethDestinationAddress: address(0),
            otherDestinationAddress: "At3rMxZEKKkMeC7V52pL6WAAL9wSGpQ45usq84D3nAqv",
            chainId: 9000
        });
        tokenV4.bridge(1, address(0), "At3rMxZEKKkMeC7V52pL6WAAL9wSGpQ45usq84D3nAqv", 9000);

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit Transfer(bob, address(0), 2);
        emit ISuperstateTokenV4.Bridge({
            caller: bob,
            src: bob,
            amount: 2,
            ethDestinationAddress: bob,
            otherDestinationAddress: string(new bytes(0)),
            chainId: 42161
        });
        tokenV4.bridge(2, bob, string(new bytes(0)), 42161);
    }

    function testBridgeUnsupportedChainIdRevert() public {
        tokenV4.mint(bob, 100e6);

        vm.startPrank(bob);
        vm.expectRevert(ISuperstateTokenV4.BridgeChainIdDestinationNotSupported.selector);
        tokenV4.bridge(2, bob, string(new bytes(0)), 1);
    }

    function testSetChainIdSupportSuccess() public {
        vm.expectEmit(true, true, true, true);
        emit ISuperstateTokenV4.SetChainIdSupport(9001, false, true);
        tokenV4.setChainIdSupport(9001, true);
    }

    function testSetChainIdSupportSetFalseSuccess() public {
        vm.expectEmit(true, true, true, true);
        emit ISuperstateTokenV4.SetChainIdSupport(0, true, false);
        tokenV4.setChainIdSupport(0, false);
    }

    function testSetChainIdSupportAlreadySupportedRevert() public {
        vm.expectRevert(ISuperstateTokenV4.BadArgs.selector);
        tokenV4.setChainIdSupport(0, true);
    }

    function testBridgeChainIdCantSetCurrentChainIdRevert() public {
        vm.expectRevert(ISuperstateTokenV4.BridgeChainIdDestinationNotSupported.selector);
        tokenV4.setChainIdSupport(block.chainid, true);
    }
}
