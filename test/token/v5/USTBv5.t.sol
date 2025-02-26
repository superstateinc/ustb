pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
//import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {USTBv4} from "test/token/v4/USTBv4.t.sol";
import {IAllowListV2} from "src/interfaces/allowlist/IAllowListV2.sol";
import {ISuperstateToken} from "src/interfaces/ISuperstateToken.sol";
import {SuperstateToken} from "src/SuperstateToken.sol";
import {SuperstateOracle} from "../../../lib/onchain-redemptions/src/oracle/SuperstateOracle.sol";

contract USTBv5 is USTBv4 {
    SuperstateToken public token;
    address public constant USTB_RECEIVER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public override  {
        super.setUp();

        // update AllowList associate USTB_RECEIVER with abcEntityId
        permsV2.setEntityIdForAddress(IAllowListV2.EntityId.wrap(abcEntityId), USTB_RECEIVER);

        // Upgrade to v5
        SuperstateToken tokenImplementationV5 = new SuperstateToken();

        tokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenImplementationV5), ""
        );

        token = SuperstateToken(address(tokenProxy));
    }

    // subscribe
    function testSubscribeInAmountZero() public override {
        hoax(eve);
        vm.expectRevert(ISuperstateToken.BadArgs.selector);
        token.subscribe(USTB_RECEIVER, 0, USDC);
    }

    function testSubscribeStablecoinNotSupported() public override {
        hoax(eve);
        vm.expectRevert(ISuperstateToken.StablecoinNotSupported.selector);
        token.subscribe(USTB_RECEIVER, 1, USDT);
    }

    function testSubscribePaused() public override {
        token.pause();

        hoax(eve);
        vm.expectRevert("Pausable: paused");
        token.subscribe(USTB_RECEIVER, 1, USDC);
    }

    function testSubscribeAccountingPaused() public override {
        token.accountingPause();

        hoax(eve);
        vm.expectRevert(ISuperstateToken.AccountingIsPaused.selector);
        token.subscribe(USTB_RECEIVER, 1, USDC);
    }

    function testSubscribeZeroSuperstateTokensOut() public override {
        uint256 amount = 10;
        deal(address(USDC), alice, amount);

        vm.startPrank(alice);

        IERC20(USDC).approve(address(token), amount);

        vm.expectRevert(ISuperstateToken.ZeroSuperstateTokensOut.selector);
        token.subscribe(USTB_RECEIVER, amount, USDC);

        vm.stopPrank();
    }

    function testSubscribeNotAllowed() public override {
        vm.warp(1726866001 + 1 days);

        address faker = address(123456);

        uint256 usdcAmountIn = 10_000_000; // $10
        deal(address(USDC), faker, usdcAmountIn);

        vm.startPrank(faker);

        IERC20(USDC).approve(address(token), usdcAmountIn);

        vm.expectRevert(ISuperstateToken.InsufficientPermissions.selector);
        token.subscribe(faker, usdcAmountIn, USDC);
    }

    function testSubscribeHappyPath() public override {
        vm.warp(1726866001 + 1 days);

        uint256 usdcAmountIn = 10_000_000; // $10
        uint256 ustbAmountOut = 963_040;
        deal(address(USDC), alice, usdcAmountIn);

        vm.startPrank(alice);

        IERC20(USDC).approve(address(token), usdcAmountIn);

        vm.expectEmit(true, true, true, true);
        emit ISuperstateToken.SubscribeV2({
            subscriber: alice,
            to: USTB_RECEIVER,
            stablecoin: USDC,
            stablecoinInAmount: usdcAmountIn,
            stablecoinInAmountAfterFee: usdcAmountIn,
            superstateTokenOutAmount: ustbAmountOut
        });
        token.subscribe(USTB_RECEIVER, usdcAmountIn, USDC);

        vm.stopPrank();

        assertEq(token.balanceOf(USTB_RECEIVER), ustbAmountOut);
        assertEq(IERC20(USDC).balanceOf(address(this)), usdcAmountIn);
    }

    function testSubscribeHappyPathFee() public override {
        vm.warp(1726866001 + 1 days);
        token.setStablecoinConfig(USDC, address(this), 10);

        uint256 usdcAmountIn = 10_000_000; // $10
        uint256 usdcAmountFee = 10_000; // 1 cent
        uint256 ustbAmountOut = 962_077; // minus 10 bps fee on the incoming usdc
        deal(address(USDC), alice, usdcAmountIn);

        vm.startPrank(alice);

        IERC20(USDC).approve(address(token), usdcAmountIn);

        vm.expectEmit(true, true, true, true);
        emit ISuperstateToken.SubscribeV2({
            subscriber: alice,
            to: USTB_RECEIVER,
            stablecoin: USDC,
            stablecoinInAmount: usdcAmountIn,
            stablecoinInAmountAfterFee: usdcAmountIn - usdcAmountFee,
            superstateTokenOutAmount: ustbAmountOut
        });
        token.subscribe(USTB_RECEIVER, usdcAmountIn, USDC);

        vm.stopPrank();

        assertEq(token.balanceOf(USTB_RECEIVER), ustbAmountOut);
        assertEq(IERC20(USDC).balanceOf(address(this)), usdcAmountIn);
    }
}