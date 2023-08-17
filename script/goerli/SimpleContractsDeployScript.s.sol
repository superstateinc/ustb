pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/SimplePermissionlist.sol";
import "src/ComplexERC20.sol";

contract SimpleContractsDeployScript is Script {
    function run() external {
        vm.startBroadcast();

        address admin = address(0x9825df3dc587BCc86b1365DA2E4EF07B0Cabfb9B);

        SimplePermissionlist perms = new SimplePermissionlist(admin);

        ComplexERC20 token = new ComplexERC20(admin, perms);

        vm.stopBroadcast();
    }
}
