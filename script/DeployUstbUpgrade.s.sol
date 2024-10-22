pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "src/USTB.sol";
import "src/AllowList.sol";

contract DeployUstbUpgrade is Script {
    USTB public tokenImplementation;
    AllowList public permsImplementation;

    function run() external {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address allowlist_address = vm.envAddress("ALLOWLIST_PROXY_ADDRESS");
        AllowList wrappedPerms = AllowList(address(allowlist_address));

        vm.startBroadcast(deployer);

        tokenImplementation = new USTB(admin, wrappedPerms);

        vm.stopBroadcast();
    }
}
