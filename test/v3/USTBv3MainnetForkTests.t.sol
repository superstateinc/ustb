//pragma solidity ^0.8.28;
//
//import "forge-std/StdUtils.sol";
//import {Test} from "forge-std/Test.sol";
//import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
//
//import "openzeppelin-contracts-v4/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
//import "openzeppelin-contracts-v4/contracts/proxy/transparent/ProxyAdmin.sol";
//import {console} from "forge-std/console.sol";
//import {SuperstateToken} from "src/SuperstateToken.sol";
//import {SuperstateTokenV2} from "src/v2/SuperstateTokenV2.sol";
//import {USTBv2} from "src/v2/USTBv2.sol";
//import {USTB} from "src/USTB.sol";
//import {AllowList} from "src/AllowList.sol";
//
//contract USTBv3MainnetForkTest is Test {
//    ProxyAdmin proxyAdmin;
//    TransparentUpgradeableProxy permsProxy;
//    AllowList public perms;
//    TransparentUpgradeableProxy tokenProxy;
//    SuperstateToken public token;
//    SuperstateTokenV2 public tokenV2;
//    address adminAddress;
//    address capturedMainnetAddress = address(0x008B3EeEE3AaAA5AD8F92De038729FC4fe899f75);
//    USTB tokenImplementation;
//
//    address alice = address(10);
//    address bob = address(11);
//
//    function setUp() public virtual {
//        string memory rpcUrl = vm.envString("RPC_URL");
//
//        uint256 mainnetFork = vm.createFork(rpcUrl);
//        vm.selectFork(mainnetFork);
//        assertEq(vm.activeFork(), mainnetFork);
//
//        adminAddress = address(0xad309BB6f13074128b4F23EF9EA2fe8552AfCA83);
//
//        proxyAdmin = ProxyAdmin(address(0xCb8d325C0Af19697B8454481602097f93aa9040F));
//        perms = AllowList(address(0x42d75C8FdBBF046DF0Fe1Ff388DA16fF99dE8149)); // This points to the AllowList proxy
//        tokenProxy = TransparentUpgradeableProxy(payable(0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e));
//        tokenV2 = USTBv2(address(tokenProxy));
//    }
//
//    function doTokenUpgradeFromV2toV3() public {
//        // assert logic contract is v2
//        assertEq("2", tokenV2.VERSION());
//
//        // Upgrade to v3 contract
//        tokenImplementation = new USTB(perms);
//        vm.prank(adminAddress);
//        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenImplementation));
//
//        // initialize v3 contract
//        token = USTB(address(tokenProxy));
//        vm.prank(adminAddress);
//        token.initializeV2();
//
//        // assert logic contract is now v3
//        assertEq("3", token.VERSION());
//
//        // assert owner is the new admin
//        assertEq(adminAddress, token.owner());
//    }
//
//    // TODO: [FAIL: revert: Ownable: caller is not the owner] testUpgradeWithMainnetFork() (gas: 2666431)
//    function testUpgradeWithMainnetFork() public {
//        assertEq(vm.activeFork(), 0);
//
//        // check balance on an address in v2
//        assertEq(404619420184, tokenV2.balanceOf(capturedMainnetAddress));
//
//        // upgrade to v3
//        doTokenUpgradeFromV2toV3();
//
//        // ensure balance state is the same
//        assertEq(404619420184, token.balanceOf(capturedMainnetAddress));
//    }
//}
