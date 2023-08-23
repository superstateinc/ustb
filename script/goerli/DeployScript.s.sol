pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import "src/Permissionlist.sol";
import "src/SUPTB.sol";

contract DeployScript is Script {
    TransparentUpgradeableProxy permsProxy;
    ProxyAdmin permsAdmin;

    Permissionlist public permsImplementation;
    Permissionlist public perms;

    TransparentUpgradeableProxy tokenProxy;
    ProxyAdmin tokenAdmin;

    SUPTB public tokenImplementation;
    SUPTB public token;

    // Storage slot with the admin of the contract.
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function run() external {
        vm.startBroadcast();

        permsImplementation = new Permissionlist();
        permsProxy = new TransparentUpgradeableProxy(address(permsImplementation), address(this), "");

        bytes32 permsAdminAddress = vm.load(address(permsProxy), ADMIN_SLOT);
        permsAdmin = ProxyAdmin(address(uint160(uint256(permsAdminAddress))));

        tokenImplementation = new SUPTB();
        tokenProxy = new TransparentUpgradeableProxy(address(tokenImplementation), address(this), "");

        bytes32 tokenAdminAddress = vm.load(address(tokenProxy), ADMIN_SLOT);
        tokenAdmin = ProxyAdmin(address(uint160(uint256(tokenAdminAddress))));

        // admin allowed to set permissions and mint / burn tokens
        address fireblocksAdmin = address(0x9825df3dc587BCc86b1365DA2E4EF07B0Cabfb9B);

        perms = Permissionlist(address(permsProxy));
        perms.initialize(fireblocksAdmin);

        token = SUPTB(address(tokenProxy));
        token.initialize(fireblocksAdmin, perms);

        vm.stopBroadcast();
    }
}
