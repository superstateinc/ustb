pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import "src/AllowList.sol";
import "src/USCC.sol";

contract DeployScript is Script {
    TransparentUpgradeableProxy tokenProxy;

    AllowList public permsImplementation;
    USCC public tokenImplementation;

    function run() external {
        // admin allowed to set permissions and mint / burn tokens
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address proxyAdmin = vm.envAddress("PROXY_ADMIN_ADDRESS");
        address allowlist_address = vm.envAddress("ALLOWLIST_PROXY_ADDRESS");
        AllowList wrappedPerms = AllowList(address(allowlist_address));

        vm.startBroadcast(deployer);

        tokenImplementation = new USCC(admin, wrappedPerms);
        tokenProxy = new TransparentUpgradeableProxy(address(tokenImplementation), proxyAdmin, "");

        // wrap in ABI to support easier calls
        USCC wrappedToken = USCC(address(tokenProxy));

        // initialize token contract
        wrappedToken.initialize("Superstate Crypto Carry Fund", "USCC");

        vm.stopBroadcast();
    }
}
