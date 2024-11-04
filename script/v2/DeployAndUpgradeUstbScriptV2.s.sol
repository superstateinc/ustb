pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-contracts-v4/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts-v4/contracts/proxy/transparent/ProxyAdmin.sol";
import "src/allowlist/AllowList.sol";
import "src/v2/USTBv2.sol";

contract DeployAndUpgradeUstbScriptV2 is Script {
    /*
        Note: Using OpenZeppelin v4 for the proxy as that is what is deployed to mainnet.
        Future tokens should use the OpenZeppelin v5 version of the proxy.

        1. Deploy USTBv2
            > _deprecatedAdmin set to existing admin
        2. Call proxyAdmin.upgrade
        3. Call tokenProxy.initializeV2()
        4. Call tokenProxy.transferOwnership()
            > use generated TK key


        --
        Within backend services environment (outside of this script):
            1. Broadcast tokenProxy.acceptOwnership()
    */
    function run() external {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));
        address admin = vm.envAddress("ADMIN_ADDRESS");
        //        address newAdminAddress = vm.envAddress("NEW_ADMIN_ADDRESS");
        address allowlist_address = vm.envAddress("ALLOWLIST_PROXY_ADDRESS");
        //        address tokenProxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");
        //        address payable tokenProxyAddress = payable(vm.envAddress("PROXY_TOKEN_ADDRESS"));
        AllowList wrappedPerms = AllowList(address(allowlist_address));
        //        ProxyAdmin tokenProxyAdmin = ProxyAdmin(tokenProxyAdminAddress);
        //        TransparentUpgradeableProxy tokenProxy = TransparentUpgradeableProxy(tokenProxyAddress);

        vm.startBroadcast(deployer);

        // 1
        /*USTBv2 tokenV2Implementation = */
        new USTBv2(admin, wrappedPerms);

        // 2 - This will be called from Etherscan using our Fireblocks key and WalletConnect
        //        tokenProxyAdmin.upgrade(ITransparentUpgradeableProxy(tokenProxyAddress), address(tokenV2Implementation));

        // 3 - This will be called from Etherscan using our Fireblocks key and WalletConnect
        //        USTBv2 tokenV2 = USTBv2(address(tokenProxy));
        //        tokenV2.initializeV2();

        // 4 - This will be called from Etherscan using our Fireblocks PK and WalletConnect
        //        tokenV2.transferOwnership(newAdminAddress);

        vm.stopBroadcast();
    }
}
