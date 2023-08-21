pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/Permissionlist.sol";
import "src/SUPTB.sol";

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast();

        address admin = address(0x9825df3dc587BCc86b1365DA2E4EF07B0Cabfb9B);

        Permissionlist perms = new Permissionlist(admin);

        SUPTB token = new SUPTB(admin, perms);

        vm.stopBroadcast();
    }
}
