pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "openzeppelin-contracts-v4/contracts/proxy/transparent/ProxyAdmin.sol";
import "src/v1/USTBv1.sol";
import "src/allowlist/v1/AllowListV1.sol";

contract DeployUstbUpgradeV1 is Script {
    USTBv1 public tokenImplementation;
    AllowListV1 public permsImplementation;

    function run() external {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address allowlist_address = vm.envAddress("ALLOWLIST_PROXY_ADDRESS");
        AllowListV1 wrappedPerms = AllowListV1(address(allowlist_address));

        vm.startBroadcast(deployer);

        tokenImplementation = new USTBv1(admin, wrappedPerms);

        vm.stopBroadcast();
    }
}
