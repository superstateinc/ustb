pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import "src/Permissionlist.sol";
import "src/SUPTB.sol";

contract DeployScript is Script {
    Permissionlist perms;
    TransparentUpgradeableProxy proxy;
    Permissionlist wrappedPerms;
    ProxyAdmin proxyAdmin;

    function run() external {
        vm.startBroadcast();

        // deployer contract set as initial owner who can perform upgrades
        proxyAdmin = new ProxyAdmin(address(this));

        perms = new Permissionlist();

        proxy = new TransparentUpgradeableProxy(address(perms), address(proxyAdmin), "");

        // admin allowed to set permissions and mint / burn tokens
        address admin = address(0x9825df3dc587BCc86b1365DA2E4EF07B0Cabfb9B);

        // wrap in ABI to support easier calls
        wrappedPerms = Permissionlist(address(proxy));
        wrappedPerms.initialize(admin);

        SUPTB token = new SUPTB(admin, perms);

        vm.stopBroadcast();
    }
}
