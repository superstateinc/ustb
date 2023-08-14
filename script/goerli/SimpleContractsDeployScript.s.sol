pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/SimplePermissionlist.sol";
import "src/SimpleERC20.sol";

contract SimpleContractsDeployScript is Script {
    function run() external {
        vm.startBroadcast();

        SimplePermissionlist perms = new SimplePermissionlist();
        uint256 initialSupply = 1000000000 * (10 ** 18);
        SimpleERC20 _token = new SimpleERC20(initialSupply, perms);

        vm.stopBroadcast();
    }
}
