// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/SimpleERC20.sol";
import "src/SimplePermissionlist.sol";

contract SimpleERC20Test is Test {
    SimpleERC20 simpleToken;
    SimplePermissionlist perms;

    uint256 initialSupply;

    function setUp() public {
        perms = new SimplePermissionlist(address(this));

        initialSupply = 1000000000;
        vm.prank(address(1));
        simpleToken = new SimpleERC20(initialSupply, perms);
    }

    function testName() public {
        assertEq(simpleToken.name(), "SimpleERC20");
    }

    function testInitialSupply() public {
        assertEq(simpleToken.balanceOf(address(1)), initialSupply);
    }

    function testCannotTransferTokensUnlessWhitelisted() public {
        // Cannot transfer to address(2)...
        vm.prank(address(1));
        vm.expectRevert(SimpleERC20.TransferNotAllowed.selector);
        simpleToken.transfer(address(2), 100000);

        // ... until we whitelist them
        assertEq(simpleToken.balanceOf(address(2)), 0);

        SimplePermissionlist.Permission memory newPerms = SimplePermissionlist.Permission(true);
        perms.setPermission(address(2), newPerms);

        vm.prank(address(1));
        simpleToken.transfer(address(2), 100000);
        assertEq(simpleToken.balanceOf(address(2)), 100000);
    }
}
