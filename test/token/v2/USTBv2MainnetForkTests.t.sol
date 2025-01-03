pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "openzeppelin-contracts-v4/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts-v4/contracts/proxy/transparent/ProxyAdmin.sol";
import {console} from "forge-std/console.sol";
import {SuperstateTokenV2} from "src/v2/SuperstateTokenV2.sol";
import {SuperstateTokenV1} from "src/v1/SuperstateTokenV1.sol";
import {USTBv2} from "src/v2/USTBv2.sol";
import {USTBv1} from "src/v1/USTBv1.sol";
import {AllowListV1} from "src/allowlist/v1/AllowListV1.sol";
import "test/allowlist/mocks/MockAllowList.sol";
import "test/token/mocks/MockUSTBv1.sol";

contract USTBv2MainnetForkTest is Test {
    ProxyAdmin proxyAdmin;
    TransparentUpgradeableProxy permsProxy;
    AllowListV1 public perms;
    TransparentUpgradeableProxy tokenProxy;
    SuperstateTokenV2 public token;
    SuperstateTokenV1 public tokenV1;
    address adminAddress;
    address capturedMainnetAddress = address(0x5138D77d51dC57983e5A653CeA6e1C1aa9750A39);
    USTBv2 tokenImplementation;

    address alice = address(10);
    address bob = address(11);

    function setUp() public virtual {
        string memory rpcUrl = vm.envString("RPC_URL");

        uint256 mainnetFork = vm.createFork(rpcUrl, 21023910);
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

        adminAddress = address(0x8C7Db8A96d39F76D9f456db23d591C2FDd0e2F8a);

        proxyAdmin = ProxyAdmin(address(0xCb8d325C0Af19697B8454481602097f93aa9040F));
        perms = AllowListV1(address(0x42d75C8FdBBF046DF0Fe1Ff388DA16fF99dE8149)); // This points to the AllowList proxy
        tokenProxy = TransparentUpgradeableProxy(payable(0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e));
        tokenV1 = USTBv1(address(tokenProxy));
    }

    function doTokenUpgradeFromV1toV2() public {
        // assert logic contract is v1
        assertEq("1", tokenV1.VERSION());

        // Upgrade to v2 contract
        tokenImplementation = new USTBv2(adminAddress, perms);
        vm.prank(adminAddress);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenImplementation));

        // initialize v2 contract
        token = USTBv2(address(tokenProxy));
        vm.prank(adminAddress);
        token.initializeV2();

        // assert logic contract is now v2
        assertEq("2", token.VERSION());

        // assert owner is the new admin
        assertEq(adminAddress, token.owner());
    }

    function testUpgradeWithMainnetFork() public {
        assertEq(vm.activeFork(), 0);

        // check balance on an address in v1
        assertEq(2401109347870, tokenV1.balanceOf(capturedMainnetAddress));

        // upgrade to v2
        doTokenUpgradeFromV1toV2();

        // ensure balance state is the same
        assertEq(2401109347870, token.balanceOf(capturedMainnetAddress));
    }

    function testUpgradeAndChangeOwner() public {
        assertEq(vm.activeFork(), 0);

        // upgrade to v2
        doTokenUpgradeFromV1toV2();

        // change owner to a new admin
        address newAdmin = alice;

        vm.prank(adminAddress);
        token.transferOwnership(newAdmin);

        vm.prank(alice);
        token.acceptOwnership();

        assertEq(alice, token.owner());

        uint256 capturedBalance = token.balanceOf(capturedMainnetAddress);

        // ensure alice can perform admin functions
        uint256 mintAmount = 100;
        vm.prank(newAdmin);
        token.mint(capturedMainnetAddress, mintAmount);
        assertEq(capturedBalance + mintAmount, token.balanceOf(capturedMainnetAddress));

        // ensure the prior admin can no longer perform admin functions
        vm.prank(adminAddress);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        token.mint(capturedMainnetAddress, mintAmount);
    }
}
