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
import {USTB} from "src/USTB.sol";
import {AllowList} from "src/allowlist/AllowList.sol";
import {AllowListV1} from "src/allowlist/v1/AllowListV1.sol";
import {IAllowList} from "src/interfaces/allowlist/IAllowList.sol";
import "test/token/SuperstateTokenTestBase.t.sol";
import {ISuperstateToken} from "src/interfaces/ISuperstateToken.sol";
import {SuperstateOracle} from "../../../lib/onchain-redemptions/src/oracle/SuperstateOracle.sol";

contract USTBv3Test is SuperstateTokenTestBase {
    SuperstateTokenV1 public tokenV1;
    SuperstateTokenV2 public tokenV2;
    USTB public tokenV3;
    SuperstateOracle public oracle;

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint256 public constant INITIAL_MAX_ORACLE_DELAY = 1 hours;

    function setUp() public override {
        string memory rpcUrl = vm.envString("RPC_URL");

        uint256 mainnetFork = vm.createFork(rpcUrl, 20_993_400);
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

        vm.warp(1_726_779_601);

        eve = vm.addr(evePrivateKey);

        // TODO - change this to `AllowList` once that is fully baked
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

        // Now upgrade to V3
        USTB tokenImplementation = new USTB(AllowList(address(perms))); // TODO - this will need to be allowListV2
        tokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenImplementation), ""
        );

        // No initialization needed for V3
        token = USTB(address(tokenProxy));
        tokenV3 = USTB(address(token));

        // Set up oracle
        oracle = new SuperstateOracle(address(this), address(tokenV3));
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
}
