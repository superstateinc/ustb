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
import {ISuperstateToken} from "src/interfaces/ISuperstateToken.sol";
import {SuperstateTokenV3} from "src/v3/SuperstateTokenV3.sol";
import {SuperstateOracle} from "../../../lib/onchain-redemptions/src/oracle/SuperstateOracle.sol";
import {SuperstateToken} from "src/SuperstateToken.sol";

contract USTBv4 is TokenTestBase {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed minter, address indexed to, uint256 amount);
    event AccountingPaused(address admin);
    event AccountingUnpaused(address admin);

    SuperstateTokenV1 public tokenV1;
    SuperstateTokenV2 public tokenV2;
    SuperstateTokenV3 public tokenV3;
    SuperstateToken public token;
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

    function setUp() public virtual {
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

        token = SuperstateToken(address(tokenProxy));
        tokenV3 = SuperstateTokenV3(address(token));

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
        SuperstateToken tokenImplementationV4 = new SuperstateToken();

        tokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenImplementationV4), ""
        );

        token = SuperstateToken(address(tokenProxy));

        vm.expectEmit(true, true, true, true);
        emit ISuperstateToken.SetRedemptionContract(address(0), MAINNET_REDEMPTION_IDLE);
        token.setRedemptionContract(MAINNET_REDEMPTION_IDLE);
    }

    function testTokenName() public virtual {
        assertEq(token.name(), "Superstate Short Duration US Government Securities Fund");
    }

    function testTokenSymbol() public virtual {
        assertEq(token.symbol(), "USTB");
    }

    function testTokenDecimals() public {
        assertEq(token.decimals(), 6);
    }

    function testTokenIsInitializedAsUnpaused() public {
        assertEq(token.paused(), false);
    }

    function testTransferRevertInsufficentBalance() public {
        deal(address(token), alice, 100e6);
        vm.startPrank(alice);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        token.transfer(bob, 101e6);

        vm.stopPrank();
    }

    function testTransferFromRevertInsufficentBalance() public {
        deal(address(token), alice, 100e6);

        // someone attempts to transfer alice's entire balance
        vm.expectRevert("ERC20: insufficient allowance");
        token.transferFrom(alice, bob, 100e6);
    }

    function testTransferFromInsufficientAllowance() public {
        deal(address(token), alice, 100e6);

        uint256 approvedAmount = 20e6;
        uint256 transferAmount = 40e6;

        vm.startPrank(alice);

        // she also grants him an approval
        token.approve(bob, approvedAmount);

        vm.stopPrank();

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.allowance(alice, bob), approvedAmount);
        assertEq(token.balanceOf(charlie), 0);

        // bob tries to transfer more than his encumbered and allowed balances
        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, charlie, transferAmount);
    }

    function testTransferFromSrcRemoveFromAllowlist() public {
        deal(address(token), alice, 100e6);

        uint256 approvedAmount = 20e6;

        vm.startPrank(alice);
        // she also grants him an approval
        token.approve(bob, approvedAmount);
        vm.stopPrank();

        permsV2.setEntityAllowedForFund(IAllowListV2.EntityId.wrap(abcEntityId), token.symbol(), false);

        // bob tries to transfer from but alice is no longe ron allowed list
        vm.prank(bob);
        vm.expectRevert(ISuperstateToken.InsufficientPermissions.selector);
        token.transferFrom(alice, charlie, approvedAmount);
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
        vm.expectRevert();
        token.mint(bob, 100e6);

        assertEq(token.balanceOf(bob), 0);
    }

    function testMintRevertInsufficientPermissions() public {
        // cannot mint to Mallory since un-whitelisted
        vm.expectRevert(ISuperstateToken.InsufficientPermissions.selector);
        token.mint(mallory, 100e6);
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
        token.bulkMint(dsts, amounts);
        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.balanceOf(bob), 333e6);
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
        token.bulkMint(dsts, amounts);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testBulkMintRevertAccountingPaused() public {
        address[] memory dsts = new address[](2);
        dsts[0] = alice;
        dsts[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = 333e6;

        token.accountingPause();

        vm.expectRevert(ISuperstateToken.AccountingIsPaused.selector);
        token.bulkMint(dsts, amounts);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testBulkMintRevertInsufficientPermissions() public {
        address[] memory dsts = new address[](2);
        dsts[0] = mallory;
        dsts[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = 333e6;

        // cannot mint to Mallory since un-whitelisted
        vm.expectRevert(ISuperstateToken.InsufficientPermissions.selector);
        token.bulkMint(dsts, amounts);

        assertEq(token.balanceOf(mallory), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testBulkMintRevertInvalidArgumentLengths() public {
        address[] memory dsts = new address[](2);
        dsts[0] = alice;
        dsts[1] = bob;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e6;

        vm.expectRevert(ISuperstateToken.InvalidArgumentLengths.selector);
        token.bulkMint(dsts, amounts);

        address[] memory dsts1 = new address[](1);
        dsts1[0] = alice;

        uint256[] memory amounts1 = new uint256[](2);
        amounts1[0] = 100e6;
        amounts1[1] = 333e6;

        vm.expectRevert(ISuperstateToken.InvalidArgumentLengths.selector);
        token.bulkMint(dsts1, amounts1);

        address[] memory dsts2 = new address[](0);
        uint256[] memory amounts2 = new uint256[](0);

        vm.expectRevert(ISuperstateToken.InvalidArgumentLengths.selector);
        token.bulkMint(dsts2, amounts2);
    }

    function testAdminBurn() public {
        deal(address(token), alice, 100e6);

        assertEq(token.balanceOf(alice), 100e6);

        // emits Transfer and AdminBurn events
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 100e6);
        vm.expectEmit();
        emit ISuperstateToken.AdminBurn(address(this), alice, 100e6);

        token.adminBurn(alice, 100e6);
        assertEq(token.balanceOf(alice), 0);
    }

    function testOffchainRedeemUsingTransfer() public {
        deal(address(token), alice, 100e6);

        assertEq(token.balanceOf(alice), 100e6);

        // emits Transfer and OffchainRedeem events
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 50e6);
        vm.expectEmit();
        emit ISuperstateToken.OffchainRedeem(alice, alice, 50e6);

        // alice calls transfer(0, amount) to self-burn
        vm.prank(alice);
        token.transfer(address(tokenProxy), 50e6);

        assertEq(token.balanceOf(alice), 50e6);
    }

    function testSelfOffchainRedeem() public {
        deal(address(token), alice, 100e6);

        assertEq(token.balanceOf(alice), 100e6);

        // emits Transfer and OffchainRedeem events
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 50e6);
        vm.expectEmit();
        emit ISuperstateToken.OffchainRedeem(alice, alice, 50e6);

        // alice calls burn(amount) to self-burn
        vm.prank(alice);
        token.offchainRedeem(50e6);

        assertEq(token.balanceOf(alice), 50e6);
    }

    function testSelfOffchainRedeemUsingTransferFrom() public {
        deal(address(token), alice, 100e6);

        assertEq(token.balanceOf(alice), 100e6);

        vm.prank(alice);
        token.approve(bob, 50e6);

        // emits Transfer and OffchainRedeem events
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 50e6);
        vm.expectEmit();
        emit ISuperstateToken.OffchainRedeem(bob, alice, 50e6);

        // bob calls transferFrom(alice, 0, amount) to self-burn
        vm.prank(bob);
        token.transferFrom(alice, address(tokenProxy), 50e6);

        assertEq(token.balanceOf(alice), 50e6);
        assertEq(token.allowance(alice, bob), 0e6, "bob's allowance for alice's tokens is spent");
    }

    function testAdminBurnRevertBadCaller() public {
        vm.prank(alice);
        vm.expectRevert();
        token.adminBurn(bob, 100e6);
    }

    function testSelfOffchainRedeemRevertInsufficientBalance() public {
        deal(address(token), alice, 100e6);
        assertEq(token.balanceOf(alice), 100e6);

        // alice tries to burn more than her balance
        vm.prank(alice);

        vm.expectRevert("ERC20: burn amount exceeds balance");
        token.offchainRedeem(200e6);
    }

    function testAdminBurnRevertInsufficientBalance() public {
        deal(address(token), alice, 100e6);
        assertEq(token.balanceOf(alice), 100e6);

        vm.prank(address(this));

        // alice tries to burn more than her available balance
        vm.expectRevert("ERC20: burn amount exceeds balance");
        token.adminBurn(alice, 101e6);
    }

    function testOffchainRedeemRevertOwnerInsufficientPermissions() public {
        deal(address(token), mallory, 100e6);

        // mallory tries to burn her tokens, but isn't whitelisted
        vm.prank(mallory);
        vm.expectRevert(ISuperstateToken.InsufficientPermissions.selector);
        token.offchainRedeem(50e6);
    }

    function testTransferToZeroReverts() public {
        deal(address(token), alice, 100e6);
        vm.expectRevert(ISuperstateToken.InsufficientPermissions.selector);
        vm.prank(alice);
        token.transfer(address(0), 10e6);
    }

    function testTransferFromToZeroReverts() public {
        deal(address(token), alice, 100e6);
        vm.prank(alice);
        token.approve(bob, 50e6);
        vm.prank(bob);
        vm.expectRevert(ISuperstateToken.InsufficientPermissions.selector);
        token.transferFrom(alice, address(0), 10e6);
    }

    function testTransferRevertSenderInsufficientPermissions() public {
        deal(address(token), mallory, 100e6);

        // mallory tries to transfer tokens, but isn't whitelisted
        vm.prank(mallory);
        vm.expectRevert(ISuperstateToken.InsufficientPermissions.selector);
        token.transfer(charlie, 30e6);
    }

    function testTransferRevertReceiverInsufficientPermissions() public {
        deal(address(token), alice, 100e6);

        // alice tries to transfer tokens to mallory, but mallory isn't whitelisted
        vm.prank(alice);
        vm.expectRevert(ISuperstateToken.InsufficientPermissions.selector);
        token.transfer(mallory, 30e6);
    }

    function testTransferFromRevertReceiverInsufficientPermissions() public {
        deal(address(token), alice, 100e6);

        // alice grants bob an approval
        vm.prank(alice);
        token.approve(bob, 50e6);

        // bob tries to transfer alice's tokens to mallory, but mallory isn't whitelisted
        vm.prank(bob);
        vm.expectRevert(ISuperstateToken.InsufficientPermissions.selector);
        token.transferFrom(alice, mallory, 50e6);
    }

    function testPauseAndUnpauseRevertIfUnauthorized() public {
        // try pausing contract from unauthorized sender
        vm.prank(charlie);
        vm.expectRevert();
        token.pause();

        // admin pauses the contract
        token.pause();

        // try unpausing contract from unauthorized sender
        vm.prank(charlie);
        vm.expectRevert();
        token.unpause();

        // admin unpauses
        token.unpause();
    }

    function testAdminPauseAndUnpauseRevertIfUnauthorized() public {
        // try pausing contract from unauthorized sender
        vm.prank(charlie);
        vm.expectRevert();
        token.accountingPause();

        // admin pauses the contract
        vm.expectEmit(false, false, false, true);
        emit AccountingPaused(address(this));
        token.accountingPause();

        // try unpausing contract from unauthorized sender
        vm.prank(charlie);
        vm.expectRevert();
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
        token.adminBurn(bob, 30e6);

        vm.prank(alice);
        token.transfer(bob, 30e6);

        vm.prank(bob);
        token.approve(charlie, 50e6);

        vm.prank(charlie);
        token.transferFrom(bob, alice, 30e6);

        vm.prank(alice);
        token.approve(bob, 50e6);
    }

    // transfer, encumber, release should still work, but mint and burn should not
    function testAccountingPauseCorrectFunctionsWork() public {
        deal(address(token), alice, 100e6);
        deal(address(token), bob, 100e6);

        token.accountingPause();
        vm.expectRevert(ISuperstateToken.AccountingIsPaused.selector);
        token.mint(alice, 30e6);
        vm.expectRevert(ISuperstateToken.AccountingIsPaused.selector);
        token.adminBurn(bob, 30e6);

        vm.prank(alice);
        token.transfer(bob, 10e6);

        vm.prank(alice);
        token.approve(bob, 10e6);

        vm.prank(bob);
        token.transferFrom(alice, bob, 10e6);
    }

    // mint/burn should still work, but transfer, encumber, release should not
    function testRegularPauseCorrectFunctionsWork() public {
        token.mint(alice, 100e6);
        token.adminBurn(alice, 1e6);

        token.pause();

        vm.prank(alice);
        vm.expectRevert(bytes("Pausable: paused"));
        token.transfer(bob, 1e6);

        vm.prank(bob);
        vm.expectRevert(bytes("Pausable: paused"));
        token.transferFrom(alice, bob, 10e6);

        // burn via transfer to 0, approve & release still works
        vm.prank(alice);
        token.transfer(address(tokenProxy), 1e6);

        vm.prank(alice);
        token.offchainRedeem(1e6);

        vm.prank(alice);
        token.approve(bob, 10e6);

        vm.prank(bob);
        token.transferFrom(alice, address(tokenProxy), 1e6);
    }

    // cannot double set any pause
    function testCannotDoublePause() public {
        token.accountingPause();
        vm.expectRevert(ISuperstateToken.AccountingIsPaused.selector);
        token.accountingPause();

        token.pause();
        vm.expectRevert(bytes("Pausable: paused"));
        token.pause();
    }

    function testCannotDoubleUnpause() public {
        token.accountingPause();

        token.accountingUnpause();
        vm.expectRevert(ISuperstateToken.AccountingIsNotPaused.selector);
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
        vm.stopPrank();

        token.accountingPause();

        assertEq(token.balanceOf(alice), 100e6);

        vm.expectRevert(ISuperstateToken.AccountingIsPaused.selector);
        token.mint(alice, 100e6);

        vm.expectRevert(ISuperstateToken.AccountingIsPaused.selector);
        token.adminBurn(alice, 100e6);

        vm.prank(alice);
        vm.expectRevert(ISuperstateToken.AccountingIsPaused.selector);
        token.transfer(address(tokenProxy), 50e6);

        vm.prank(alice);
        vm.expectRevert(ISuperstateToken.AccountingIsPaused.selector);
        token.transferFrom(alice, address(tokenProxy), 50e6);

        vm.prank(alice);
        vm.expectRevert(ISuperstateToken.AccountingIsPaused.selector);
        token.offchainRedeem(10e6);

        token.accountingUnpause();
        token.pause();

        vm.prank(alice);
        vm.expectRevert(bytes("Pausable: paused"));
        token.transfer(bob, 50e6);

        vm.prank(bob);
        vm.expectRevert(bytes("Pausable: paused"));
        token.transferFrom(alice, charlie, 50e6);

        assertEq(token.balanceOf(alice), 100e6);
    }

    function eveAuthorization(uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (uint8, bytes32, bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, eve, bob, value, nonce, deadline));
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
        vm.expectRevert(ISuperstateToken.BadSignatory.selector);
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
        vm.expectRevert(ISuperstateToken.BadSignatory.selector);
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
        vm.expectRevert(ISuperstateToken.BadSignatory.selector);
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
        vm.expectRevert(ISuperstateToken.BadSignatory.selector);
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
        vm.expectRevert(ISuperstateToken.BadSignatory.selector);
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
        vm.expectRevert(ISuperstateToken.BadSignatory.selector);
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
        vm.warp(expiry + 1);

        // bob calls permit with the signature after the expiry
        vm.prank(bob);
        vm.expectRevert(ISuperstateToken.SignatureExpired.selector);
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

        (uint8 v, bytes32 r,) = eveAuthorization(allowance, nonce, expiry);

        // 1 greater than the max value of s
        bytes32 invalidS = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1;

        // bob calls permit with the signature with invalid `s` value
        vm.prank(bob);
        vm.expectRevert(ISuperstateToken.InvalidSignatureS.selector);
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
        vm.expectRevert(ISuperstateToken.BadSignatory.selector);
        token.permit(eve, bob, allowance, expiry, invalidV, r, s);

        // bob's allowance from eve is unchanged
        assertEq(token.allowance(eve, bob), 0);

        // eve's nonce is not incremented
        assertEq(token.nonces(eve), nonce);
    }

    function testHasSufficientPermissions() public {
        assertTrue(token.isAllowed(bob));
    }

    /// v3 tests following

    function testUpdateOracleNotOwner() public {
        hoax(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        token.setOracle(address(1));
    }

    function testUpdateOracleSameAddress() public {
        vm.expectRevert(ISuperstateToken.BadArgs.selector);
        token.setOracle(address(oracle));
    }

    function testSetMaximumOracleDelayNotOwner() public {
        hoax(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        token.setMaximumOracleDelay(1);
    }

    function testSetMaximumOracleDelaySameDelay() public {
        vm.expectRevert(ISuperstateToken.BadArgs.selector);
        token.setMaximumOracleDelay(INITIAL_MAX_ORACLE_DELAY);
    }

    function testSetStablecoinConfigNotOwner() public {
        hoax(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        token.setStablecoinConfig(address(0), address(0), 0);
    }

    function testSetStablecoinConfigFeeTooHigh() public {
        vm.expectRevert(ISuperstateToken.FeeTooHigh.selector);
        token.setStablecoinConfig(address(0), address(0), 11);
    }

    function testSetStablecoinConfigAllArgsIdentical() public {
        vm.expectRevert(ISuperstateToken.BadArgs.selector);
        token.setStablecoinConfig(address(0), address(0), 0);
    }

    // subscribe
    function testSubscribeInAmountZero() public {
        hoax(eve);
        vm.expectRevert(ISuperstateToken.BadArgs.selector);
        token.subscribe(0, USDC);
    }

    function testSubscribeStablecoinNotSupported() public {
        hoax(eve);
        vm.expectRevert(ISuperstateToken.StablecoinNotSupported.selector);
        token.subscribe(1, USDT);
    }

    function testSubscribePaused() public {
        token.pause();

        hoax(eve);
        vm.expectRevert("Pausable: paused");
        token.subscribe(1, USDC);
    }

    function testSubscribeAccountingPaused() public {
        token.accountingPause();

        hoax(eve);
        vm.expectRevert(ISuperstateToken.AccountingIsPaused.selector);
        token.subscribe(1, USDC);
    }

    function testSubscribeZeroSuperstateTokensOut() public {
        uint256 amount = 10;
        deal(address(USDC), alice, amount);

        vm.startPrank(alice);

        IERC20(USDC).approve(address(token), amount);

        vm.expectRevert(ISuperstateToken.ZeroSuperstateTokensOut.selector);
        token.subscribe(amount, USDC);

        vm.stopPrank();
    }

    function testSubscribeNotAllowed() public {
        vm.warp(1726866001 + 1 days);

        address faker = address(123456);

        uint256 usdcAmountIn = 10_000_000; // $10
        deal(address(USDC), faker, usdcAmountIn);

        vm.startPrank(faker);

        IERC20(USDC).approve(address(token), usdcAmountIn);

        vm.expectRevert(ISuperstateToken.InsufficientPermissions.selector);
        token.subscribe(usdcAmountIn, USDC);
    }

    function testSubscribeHappyPath() public {
        vm.warp(1726866001 + 1 days);

        uint256 usdcAmountIn = 10_000_000; // $10
        uint256 ustbAmountOut = 963_040;
        deal(address(USDC), alice, usdcAmountIn);

        vm.startPrank(alice);

        IERC20(USDC).approve(address(token), usdcAmountIn);

        vm.expectEmit(true, true, true, true);
        emit ISuperstateToken.Subscribe({
            subscriber: alice,
            stablecoin: USDC,
            stablecoinInAmount: usdcAmountIn,
            stablecoinInAmountAfterFee: usdcAmountIn,
            superstateTokenOutAmount: ustbAmountOut
        });
        token.subscribe(usdcAmountIn, USDC);

        vm.stopPrank();

        assertEq(token.balanceOf(alice), ustbAmountOut);
        assertEq(IERC20(USDC).balanceOf(address(this)), usdcAmountIn);
    }

    function testSubscribeHappyPathFee() public {
        vm.warp(1726866001 + 1 days);
        token.setStablecoinConfig(USDC, address(this), 10);

        uint256 usdcAmountIn = 10_000_000; // $10
        uint256 usdcAmountFee = 10_000; // 1 cent
        uint256 ustbAmountOut = 962_077; // minus 10 bps fee on the incoming usdc
        deal(address(USDC), alice, usdcAmountIn);

        vm.startPrank(alice);

        IERC20(USDC).approve(address(token), usdcAmountIn);

        vm.expectEmit(true, true, true, true);
        emit ISuperstateToken.Subscribe({
            subscriber: alice,
            stablecoin: USDC,
            stablecoinInAmount: usdcAmountIn,
            stablecoinInAmountAfterFee: usdcAmountIn - usdcAmountFee,
            superstateTokenOutAmount: ustbAmountOut
        });
        token.subscribe(usdcAmountIn, USDC);

        vm.stopPrank();

        assertEq(token.balanceOf(alice), ustbAmountOut);
        assertEq(IERC20(USDC).balanceOf(address(this)), usdcAmountIn);
    }

    function testGetChainlinkPriceOnchainSubscriptionsDisabled() public {
        token.setOracle(address(0));

        vm.expectRevert(ISuperstateToken.OnchainSubscriptionsDisabled.selector);
        token.getChainlinkPrice();
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
    }

    function testRedemptionContract() public {
        assertEq(MAINNET_REDEMPTION_IDLE, token.redemptionContract());
    }

    //vm.expectEmit(true, true, true, true);
    //emitISuperstateToken.SetRedemptionContract(address(0), MAINNET_REDEMPTION_IDLE);
    //token.setRedemptionContract(MAINNET_REDEMPTION_IDLE);

    function testRedemptionContractNotOwnerRevert() public {
        hoax(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        token.setRedemptionContract(MAINNET_REDEMPTION_IDLE);
    }

    function testRedemptionContractAlreadySetRevert() public {
        vm.expectRevert(ISuperstateToken.BadArgs.selector);
        token.setRedemptionContract(MAINNET_REDEMPTION_IDLE);
    }

    function testRedemptionContractSuccess() public {
        vm.expectEmit(true, true, true, true);
        emit ISuperstateToken.SetRedemptionContract(MAINNET_REDEMPTION_IDLE, address(1234));
        token.setRedemptionContract(address(1234));
    }

    function testBridgeToBookEntrySuccess() public {
        token.mint(bob, 100e6);

        hoax(bob);
        vm.expectEmit(true, true, true, true);
        emit Transfer(bob, address(0), 100e6);
        emit ISuperstateToken.Bridge(bob, bob, 100e6, address(0), string(new bytes(0)), 0);
        token.bridgeToBookEntry(100e6);
    }

    function testBridgeAmountZeroRevert() public {
        token.mint(bob, 100e6);

        hoax(bob);
        vm.expectRevert(ISuperstateToken.ZeroSuperstateTokensOut.selector);
        token.bridge(0, bob, string(new bytes(0)), 9000);
    }

    function testBridgeOnchainDestinationSetForBridgeToBookEntryRevert() public {
        token.mint(bob, 100e6);

        hoax(bob);
        vm.expectRevert(ISuperstateToken.OnchainDestinationSetForBridgeToBookEntry.selector);
        token.bridge(1, bob, string(new bytes(0)), 0);

        hoax(bob);
        vm.expectRevert(ISuperstateToken.OnchainDestinationSetForBridgeToBookEntry.selector);
        token.bridge(1, address(0), "At3rMxZEKKkMeC7V52pL6WAAL9wSGpQ45usq84D3nAqv", 0);
    }

    function testBridgeTwoDestinationsRevert() public {
        token.mint(bob, 100e6);

        hoax(bob);
        vm.expectRevert(ISuperstateToken.TwoDestinationsInvalid.selector);
        token.bridge(1, bob, "At3rMxZEKKkMeC7V52pL6WAAL9wSGpQ45usq84D3nAqv", 9000);

        hoax(bob);
        vm.expectRevert(ISuperstateToken.TwoDestinationsInvalid.selector);
        token.bridge(1, bob, "At3rMxZEKKkMeC7V52pL6WAAL9wSGpQ45usq84D3nAqv", 0);
    }

    function testBridgeAccountingPausedRevert() public {
        token.mint(bob, 100e6);

        token.accountingPause();

        hoax(bob);
        vm.expectRevert(ISuperstateToken.AccountingIsPaused.selector);
        token.bridge(1, bob, "At3rMxZEKKkMeC7V52pL6WAAL9wSGpQ45usq84D3nAqv", 9000);
    }

    function testBridgeUnauthorizedRevert() public {
        token.mint(bob, 100e6);

        permsV2.setEntityAllowedForFund(IAllowListV2.EntityId.wrap(abcEntityId), "USTB", false);

        hoax(bob);
        vm.expectRevert(ISuperstateToken.InsufficientPermissions.selector);
        token.bridge(1, bob, "At3rMxZEKKkMeC7V52pL6WAAL9wSGpQ45usq84D3nAqv", 9000);
    }

    function testBridgeSuccess() public {
        token.mint(bob, 100e6);

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit Transfer(bob, address(0), 1);
        emit ISuperstateToken.Bridge({
            caller: bob,
            src: bob,
            amount: 1,
            ethDestinationAddress: address(0),
            otherDestinationAddress: "At3rMxZEKKkMeC7V52pL6WAAL9wSGpQ45usq84D3nAqv",
            chainId: 9000
        });
        token.bridge(1, address(0), "At3rMxZEKKkMeC7V52pL6WAAL9wSGpQ45usq84D3nAqv", 9000);

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit Transfer(bob, address(0), 2);
        emit ISuperstateToken.Bridge({
            caller: bob,
            src: bob,
            amount: 2,
            ethDestinationAddress: bob,
            otherDestinationAddress: string(new bytes(0)),
            chainId: 42161
        });
        token.bridge(2, bob, string(new bytes(0)), 42161);
    }
}
