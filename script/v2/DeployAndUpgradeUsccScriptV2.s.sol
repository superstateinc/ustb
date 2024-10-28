pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "openzeppelin-contracts-v4/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts-v4/contracts/proxy/transparent/ProxyAdmin.sol";
import "src/AllowList.sol";
import "src/USCC.sol";

contract DeployAndUpgradeUsccScriptV2 is Script {
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
        address newAdminAddress = vm.envAddress("NEW_ADMIN_ADDRESS");
        address allowlist_address = vm.envAddress("ALLOWLIST_PROXY_ADDRESS");
        address tokenProxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");
        address payable tokenProxyAddress = payable(vm.envAddress("PROXY_TOKEN_ADDRESS"));
        AllowList wrappedPerms = AllowList(address(allowlist_address));
        ProxyAdmin tokenProxyAdmin = ProxyAdmin(tokenProxyAdminAddress);
        TransparentUpgradeableProxy tokenProxy = TransparentUpgradeableProxy(tokenProxyAddress);

        vm.startBroadcast(deployer);

        // 1
        USCC tokenV2Implementation = new USCC(admin, wrappedPerms);

        // 2
        tokenProxyAdmin.upgrade(ITransparentUpgradeableProxy(tokenProxyAddress), address(tokenV2Implementation));

        // 3
        USCC tokenV2 = USCC(tokenProxyAddress);
        tokenV2.initializeV2();

        // 4
        tokenV2.transferOwnership(newAdminAddress);

        vm.stopBroadcast();
    }
}
