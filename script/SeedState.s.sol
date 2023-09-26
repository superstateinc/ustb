// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import { SUPTB } from "../src/SUPTB.sol";
import { PermissionList } from "../src/PermissionList.sol";

// Just add some example state for testing
contract SeedStateScript is Script {
    function setUp() public {}

    function run() public {
        address admin = vm.rememberKey(vm.envUint("ADMIN_PRIVATE_KEY"));
        address alice = vm.rememberKey(vm.envUint("ALICE_PRIVATE_KEY"));

        address permissionList = vm.envAddress("PERMISSION_LIST_ADDRESS");
        address supTB = vm.envAddress("SUPTB_ADDRESS");
        
        PermissionList perms = PermissionList(permissionList);
        SUPTB token = SUPTB(supTB);
        
        require(perms.permissionAdmin() == admin, "Wrong admin address");

        vm.startBroadcast(admin);

        PermissionList.Permission memory allowPerms = PermissionList.Permission(true, false, false, false, false, false);
        perms.setPermission(alice, allowPerms);

        token.mint(alice, 100e6);

        vm.stopBroadcast();

        vm.startBroadcast(alice);

        token.transfer(address(0), 20e6);

        vm.stopBroadcast();
    }
}