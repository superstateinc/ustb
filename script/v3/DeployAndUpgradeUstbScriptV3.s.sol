pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-contracts-v4/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts-v4/contracts/proxy/transparent/ProxyAdmin.sol";
import "src/AllowList.sol";
import "src/USTB.sol";

contract DeployAndUpgradeUstbScriptV3 is Script {
    /*
        Note: Using OpenZeppelin v4 for the proxy as that is what is deployed to mainnet.
        Future tokens should use the OpenZeppelin v5 version of the proxy.

        1. Deploy USTBv3
            > _deprecatedAdmin set to existing admin
        2. Call proxyAdmin.upgrade
        3. Call tokenProxy.initializeV2()
        4. Call tokenProxy.transferOwnership()
            > use generated TK key


        --
        Within backend services environment (outside of this script):
            1. Broadcast tokenProxy.acceptOwnership()
    */

    uint256 public constant MAXIMUM_ORACLE_DELAY = 120;

    function run() external {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));
        address admin = vm.envAddress("ADMIN_ADDRESS");
        //        address newAdminAddress = vm.envAddress("NEW_ADMIN_ADDRESS");
        address allowlist_address = vm.envAddress("ALLOWLIST_PROXY_ADDRESS");
        address tokenProxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");
        address payable tokenProxyAddress = payable(vm.envAddress("PROXY_TOKEN_ADDRESS"));
        AllowList wrappedPerms = AllowList(address(allowlist_address));
        ProxyAdmin tokenProxyAdmin = ProxyAdmin(tokenProxyAdminAddress);
        //        TransparentUpgradeableProxy tokenProxy = TransparentUpgradeableProxy(tokenProxyAddress);

        vm.startBroadcast(deployer);

        // 1
        USTB tokenV3Implementation = new USTB(admin, wrappedPerms, MAXIMUM_ORACLE_DELAY);

        // 2
        tokenProxyAdmin.upgrade(ITransparentUpgradeableProxy(tokenProxyAddress), address(tokenV3Implementation));

        // TODO the rest
        //        // 3
        //        USTB tokenV3 = USTB(address(tokenProxy));
        //        tokenV3.initializeV2();
        //
        //        // 4
        //        tokenV3.transferOwnership(newAdminAddress);

        vm.stopBroadcast();
    }
}
