pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
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
import {SuperstateToken} from "src/SuperstateToken.sol";
import {SuperstateOracle} from "../../../lib/onchain-redemptions/src/oracle/SuperstateOracle.sol";

contract USTBv3Test is SuperstateTokenTestBase {
    SuperstateTokenV1 public tokenV1;
    SuperstateTokenV2 public tokenV2;
    SuperstateToken public tokenV3;
    SuperstateOracle public oracle;

    AllowList permsV2;
    ProxyAdmin permsProxyAdminV2;
    TransparentUpgradeableProxy permsProxyV2;

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint256 public constant INITIAL_MAX_ORACLE_DELAY = 1 hours;
    uint256 public constant MAXIMUM_ACCEPTABLE_PRICE_DELTA = 1_000_000;

    function setUp() public override {
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
        SuperstateToken tokenImplementation = new SuperstateToken();
        tokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenImplementation), ""
        );

        token = SuperstateToken(address(tokenProxy));
        tokenV3 = SuperstateToken(address(token));

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
    }

    function testUpdateOracleNotOwner() public {
        hoax(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenV3.setOracle(address(1));
    }

    function testUpdateOracleSameAddress() public {
        vm.expectRevert(ISuperstateToken.BadArgs.selector);
        tokenV3.setOracle(address(oracle));
    }

    function testSetMaximumOracleDelayNotOwner() public {
        hoax(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenV3.setMaximumOracleDelay(1);
    }

    function testSetMaximumOracleDelaySameDelay() public {
        vm.expectRevert(ISuperstateToken.BadArgs.selector);
        tokenV3.setMaximumOracleDelay(INITIAL_MAX_ORACLE_DELAY);
    }

    function testSetStablecoinConfigNotOwner() public {
        hoax(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenV3.setStablecoinConfig(address(0), address(0), 0);
    }

    function testSetStablecoinConfigFeeTooHigh() public {
        vm.expectRevert(ISuperstateToken.FeeTooHigh.selector);
        tokenV3.setStablecoinConfig(address(0), address(0), 11);
    }

    function testSetStablecoinConfigAllArgsIdentical() public {
        vm.expectRevert(ISuperstateToken.BadArgs.selector);
        tokenV3.setStablecoinConfig(address(0), address(0), 0);
    }

    // subscribe
    function testSubscribeInAmountZero() public {
        hoax(eve);
        vm.expectRevert(ISuperstateToken.BadArgs.selector);
        tokenV3.subscribe(0, USDC);
    }


    function testSubscribeStablecoinNotSupported() public {
        hoax(eve);
        vm.expectRevert(ISuperstateToken.StablecoinNotSupported.selector);
        tokenV3.subscribe(1, USDT);
    }

    function testSubscribePaused() public {
        tokenV3.pause();

        hoax(eve);
        vm.expectRevert("Pausable: paused");
        tokenV3.subscribe(1, USDC);
    }

    function testSubscribeAccountingPaused() public {
        tokenV3.accountingPause();

        hoax(eve);
        vm.expectRevert(ISuperstateTokenV1.AccountingIsPaused.selector);
        tokenV3.subscribe(1, USDC);
    }

    function testSubscribeZeroSuperstateTokensOut() public {
        uint256 amount = 10;
        deal(address(USDC), alice, amount);

        vm.startPrank(alice);

        IERC20(USDC).approve(address(tokenV3), amount);

        vm.expectRevert(ISuperstateToken.ZeroSuperstateTokensOut.selector);
        tokenV3.subscribe(amount, USDC);

        vm.stopPrank();
    }

    function testSubscribeNotAllowed() public {
        vm.warp(1726866001 + 1 days);

        address faker = address(123456);

        uint256 usdcAmountIn = 10_000_000; // $10
        deal(address(USDC), faker, usdcAmountIn);

        vm.startPrank(faker);

        IERC20(USDC).approve(address(tokenV3), usdcAmountIn);

        vm.expectRevert(ISuperstateTokenV1.InsufficientPermissions.selector);
        tokenV3.subscribe(usdcAmountIn, USDC);
    }

    function testSubscribeHappyPath() public {
        vm.warp(1726866001 + 1 days);

        uint256 usdcAmountIn = 10_000_000; // $10
        uint256 ustbAmountOut = 963_040;
        deal(address(USDC), alice, usdcAmountIn);

        vm.startPrank(alice);

        IERC20(USDC).approve(address(tokenV3), usdcAmountIn);

        vm.expectEmit(true, true, true, true);
        emit ISuperstateToken.Subscribe({
            subscriber: alice,
            stablecoin: USDC,
            stablecoinInAmount: usdcAmountIn,
            stablecoinInAmountAfterFee: usdcAmountIn,
            superstateTokenOutAmount: ustbAmountOut
        });
        tokenV3.subscribe(usdcAmountIn, USDC);

        vm.stopPrank();

        assertEq(tokenV3.balanceOf(alice), ustbAmountOut);
        assertEq(IERC20(USDC).balanceOf(address(this)), usdcAmountIn);
    }

    function testSubscribeHappyPathFee() public {
        vm.warp(1726866001 + 1 days);
        tokenV3.setStablecoinConfig(USDC, address(this), 10);

        uint256 usdcAmountIn = 10_000_000; // $10
        uint256 usdcAmountFee = 10_000; // 1 cent
        uint256 ustbAmountOut = 962_077; // minus 10 bps fee on the incoming usdc
        deal(address(USDC), alice, usdcAmountIn);

        vm.startPrank(alice);

        IERC20(USDC).approve(address(tokenV3), usdcAmountIn);

        vm.expectEmit(true, true, true, true);
        emit ISuperstateToken.Subscribe({
            subscriber: alice,
            stablecoin: USDC,
            stablecoinInAmount: usdcAmountIn,
            stablecoinInAmountAfterFee: usdcAmountIn - usdcAmountFee,
            superstateTokenOutAmount: ustbAmountOut
        });
        tokenV3.subscribe(usdcAmountIn, USDC);

        vm.stopPrank();

        assertEq(tokenV3.balanceOf(alice), ustbAmountOut);
        assertEq(IERC20(USDC).balanceOf(address(this)), usdcAmountIn);
    }

    function testGetChainlinkPriceOnchainSubscriptionsDisabled() public {
        tokenV3.setOracle(address(0));

        vm.expectRevert(ISuperstateToken.OnchainSubscriptionsDisabled.selector);
        tokenV3.getChainlinkPrice();
    }

    function testUpgradingAllowListDoesNotAffectToken() public override {
        AllowList permsV2Implementation = new AllowList();
        permsProxyAdminV2.upgradeAndCall(
            ITransparentUpgradeableProxy(address(permsProxyV2)), address(permsV2Implementation), ""
        );

        AllowList permsV3 = AllowList(address(permsProxyV2));

        assertEq(address(token.allowList()), address(permsProxyV2));

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

        vm.prank(bob);
        token.encumber(charlie, 20e6);

        vm.prank(alice);
        token.encumberFrom(bob, charlie, 10e6);

        assertEq(token.encumbrances(bob, charlie), 30e6);
    }

    function testTransferFromWorksIfUsingEncumbranceAndSourceIsNotWhitelisted() public override {
        deal(address(token), mallory, 100e6);

        // whitelist mallory for setting encumbrances
        address[] memory addrsToSet = new address[](1);
        addrsToSet[0] = mallory;
        string[] memory fundsToSet = new string[](1);
        fundsToSet[0] = "USTB";
        bool[] memory fundPermissionsToSet = new bool[](1);
        fundPermissionsToSet[0] = true;
        permsV2.setEntityPermissionsAndAddresses(
            IAllowListV2.EntityId.wrap(2), addrsToSet, fundsToSet, fundPermissionsToSet
        );
        vm.startPrank(mallory);
        token.encumber(bob, 20e6);
        token.approve(bob, 10e6);
        vm.stopPrank();

        // now un-whitelist mallory
        permsV2.setEntityAllowedForFund(IAllowListV2.EntityId.wrap(2), "USTB", false);

        // bob can transferFrom now-un-whitelisted mallory by spending her encumbrance to him, without issues
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Release(mallory, bob, 15e6);
        vm.expectEmit(true, true, true, true);
        emit Transfer(mallory, alice, 15e6);
        token.transferFrom(mallory, alice, 15e6);

        assertEq(token.balanceOf(mallory), 85e6);
        assertEq(token.balanceOf(alice), 15e6);
        assertEq(token.balanceOf(bob), 0e6);
        assertEq(token.encumbrances(mallory, bob), 5e6);
    }

    function testTransferFromRevertsIfEncumbranceLessThanAmountAndSourceNotWhitelisted() public override {
        deal(address(token), mallory, 100e6);

        // Re-populate AllowList state
        address[] memory addrsToSet = new address[](1);
        addrsToSet[0] = mallory;
        string[] memory fundsToSet = new string[](1);
        fundsToSet[0] = "USTB";
        bool[] memory fundPermissionsToSet = new bool[](1);
        fundPermissionsToSet[0] = true;
        permsV2.setEntityPermissionsAndAddresses(
            IAllowListV2.EntityId.wrap(2), addrsToSet, fundsToSet, fundPermissionsToSet
        );
        // whitelist mallory for setting encumbrances
        vm.startPrank(mallory);
        token.encumber(bob, 20e6);
        token.approve(bob, 10e6);
        vm.stopPrank();

        // now un-whitelist mallory
        permsV2.setEntityAllowedForFund(IAllowListV2.EntityId.wrap(2), "USTB", false);

        assertFalse(permsV2.isAddressAllowedForFund(mallory, "USTB"));

        // reverts because encumbrances[src][bob] = 20 < amount and src (mallory) is not whitelisted
        vm.prank(bob);
        vm.expectRevert(ISuperstateTokenV1.InsufficientPermissions.selector);
        token.transferFrom(mallory, alice, 30e6);
    }

    function testFuzzEncumbranceMustBeRespected(uint256 amt, address spender, address recipient, address recipient2)
        public
        override
    {
        // cannot be address 0 - ERC20: transfer from the zero address
        // spender cannot be alice bob or charlie, they already have their permissions set
        vm.assume(spender != address(0) && spender != alice && spender != bob && spender != charlie);
        vm.assume(recipient != alice && recipient != bob && recipient != charlie);
        vm.assume(recipient2 != alice && recipient2 != bob && recipient2 != charlie);
        vm.assume(spender != recipient && recipient != recipient2 && spender != recipient2);
        vm.assume(recipient != address(0) && recipient2 != address(0));
        // proxy admin cant use protocol
        vm.assume(
            address(permsProxyAdmin) != spender && address(permsProxyAdmin) != recipient
                && address(permsProxyAdmin) != recipient2 && address(tokenProxyAdmin) != spender
                && address(tokenProxyAdmin) != recipient && address(tokenProxyAdmin) != recipient2
        );

        // whitelist spender and recipients
        address[] memory addrsToSet = new address[](3);
        addrsToSet[0] = spender;
        addrsToSet[1] = recipient;
        addrsToSet[2] = recipient2;
        string[] memory fundsToSet = new string[](1);
        fundsToSet[0] = "USTB";
        bool[] memory fundPermissionsToSet = new bool[](1);
        fundPermissionsToSet[0] = true;

        permsV2.setEntityPermissionsAndAddresses(
            IAllowListV2.EntityId.wrap(2), addrsToSet, fundsToSet, fundPermissionsToSet
        );

        // limit range of amount
        uint256 amount = bound(amt, 1, type(uint128).max - 1);
        deal(address(token), spender, amount * 2);

        // encumber tokens to spender
        vm.prank(spender);
        token.encumber(recipient, amount);

        // encumber tokens to spender
        vm.prank(spender);
        token.encumber(recipient2, amount);

        // recipient calls transferFrom on spender
        vm.prank(recipient);
        token.transferFrom(spender, recipient, amount);

        // recipient calls transferFrom on spender
        vm.prank(recipient2);
        token.transferFrom(spender, recipient2, amount);
    }
}
