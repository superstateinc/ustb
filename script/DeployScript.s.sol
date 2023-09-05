pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import "src/PermissionList.sol";
import "src/SUPTB.sol";

contract DeployScript is Script {
    ProxyAdmin proxyAdmin;
    TransparentUpgradeableProxy permsProxy;
    TransparentUpgradeableProxy tokenProxy;

    PermissionList public permsImplementation;
    SUPTB public tokenImplementation;

    function run() external {
        vm.startBroadcast();

        // admin allowed to set permissions and mint / burn tokens
        // TODO: Configure before running
        address fireblocksAdmin = address(0x9825df3dc587BCc86b1365DA2E4EF07B0Cabfb9B);

        // deploy proxy admin contract
        proxyAdmin = new ProxyAdmin();

        permsImplementation = new PermissionList(fireblocksAdmin);
        permsProxy = new TransparentUpgradeableProxy(address(permsImplementation), address(proxyAdmin), "");

        // wrap in ABI to support easier calls
        PermissionList wrappedPerms = PermissionList(address(permsProxy));

        tokenImplementation = new SUPTB(fireblocksAdmin, wrappedPerms);
        tokenProxy = new TransparentUpgradeableProxy(address(tokenImplementation), address(proxyAdmin), "");

        // wrap in ABI to support easier calls
        SUPTB wrappedToken = SUPTB(address(tokenProxy));

        // initialize token contract
        wrappedToken.initialize("Superstate Short-Term Government Securities Fund", "SUPTB");

        vm.stopBroadcast();
    }
}
