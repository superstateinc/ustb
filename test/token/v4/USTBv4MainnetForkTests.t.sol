pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "openzeppelin-contracts-v4/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts-v4/contracts/proxy/transparent/ProxyAdmin.sol";
import {console} from "forge-std/console.sol";
import {SuperstateTokenV3} from "src/v3/SuperstateTokenV3.sol";
import {SuperstateToken} from "src/SuperstateToken.sol";
import {AllowList} from "src/allowlist/AllowList.sol";

contract USTBv4MainnetForkTest is Test {
    ProxyAdmin proxyAdmin;
    TransparentUpgradeableProxy permsProxy;
    AllowList public allowlistProxy;
    TransparentUpgradeableProxy tokenProxy;
    SuperstateToken public token;
    SuperstateTokenV3 public tokenV3;
    address turnkeyUstbAdminAddress;
    address capturedMainnetAddress = address(0x5138D77d51dC57983e5A653CeA6e1C1aa9750A39);
    SuperstateToken tokenImplementation;

    address alice = address(10);
    address bob = address(11);

    function setUp() public virtual {
        string memory rpcUrl = vm.envString("RPC_URL");

        uint256 mainnetFork = vm.createFork(rpcUrl, 21666519);
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

        turnkeyUstbAdminAddress = 0xad309BB6f13074128b4F23EF9EA2fe8552AfCA83;

        proxyAdmin = ProxyAdmin(address(0xb9d285DCaD879513DC9c1A3b2e0CCcB21c3c2146));
        allowlistProxy = AllowList(address(0x02f1fA8B196d21c7b733EB2700B825611d8A38E5));
        tokenProxy = TransparentUpgradeableProxy(payable(0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e));
        tokenV3 = SuperstateTokenV3(address(tokenProxy));
    }

    function doTokenUpgradeFromV3toV4() public {
        // assert logic contract is v3
        assertEq("3", tokenV3.VERSION());

        // Upgrade to v4 contract
        tokenImplementation = new SuperstateToken();

        vm.prank(turnkeyUstbAdminAddress);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenImplementation));

        // initialize v4 contract
        token = SuperstateToken(address(tokenProxy));

        // assert logic contract is now v3
        assertEq("4", token.VERSION());

        // assert owner is the new admin
        assertEq(turnkeyUstbAdminAddress, token.owner());
    }

    function testUpgradeWithMainnetFork() public {
        assertEq(vm.activeFork(), 0);

        // check balance on an address in v3
        assertEq(1399710234231, tokenV3.balanceOf(capturedMainnetAddress));

        // upgrade to v4
        doTokenUpgradeFromV3toV4();

        // ensure balance state is the same
        assertEq(1399710234231, token.balanceOf(capturedMainnetAddress));
    }
}
