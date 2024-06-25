pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import "src/AllowList.sol";
import "src/USTB.sol";

contract DeployScript is Script {
    ProxyAdmin proxyAdmin;
    TransparentUpgradeableProxy permsProxy;
    TransparentUpgradeableProxy tokenProxy;

    AllowList public permsImplementation;
    USTB public tokenImplementation;

    function run() external {
        // admin allowed to set permissions and mint / burn tokens
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));
        address admin = vm.envAddress("ADMIN_ADDRESS");

        vm.startBroadcast(deployer);

        // deploy proxy admin contract
        proxyAdmin = new ProxyAdmin();

        permsImplementation = new AllowList(admin);
        permsProxy = new TransparentUpgradeableProxy(address(permsImplementation), address(proxyAdmin), "");

        // wrap in ABI to support easier calls
        AllowList wrappedPerms = AllowList(address(permsProxy));

        tokenImplementation = new USTB(admin, wrappedPerms);
        tokenProxy = new TransparentUpgradeableProxy(address(tokenImplementation), address(proxyAdmin), "");

        // wrap in ABI to support easier calls
        USTB wrappedToken = USTB(address(tokenProxy));

        // initialize token contract
        wrappedToken.initialize("Superstate Short Duration US Government Securities Fund", "USTB");

        proxyAdmin.transferOwnership(admin);

        require(proxyAdmin.owner() == admin, "Proxy admin ownership not transferred");

        vm.stopBroadcast();
    }
}
