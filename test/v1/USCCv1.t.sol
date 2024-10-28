pragma solidity ^0.8.28;

import "test/SuperstateTokenTestBase.t.sol";
import {USCCv1} from "src/v1/USCCv1.sol";
import {USCCV2} from "test/USCCV2.sol";
import {AllowList} from "src/AllowList.sol";
import {SuperstateTokenV1} from "src/v1/SuperstateTokenV1.sol";

contract USCCv1Test is SuperstateTokenTestBase {
    function setUp() public override {
        eve = vm.addr(evePrivateKey);

        AllowList permsImplementation = new AllowList(address(this));

        // deploy proxy contract and point it to implementation
        permsProxy = new TransparentUpgradeableProxy(address(permsImplementation), address(this), "");
        permsProxyAdmin = ProxyAdmin(getAdminAddress(address(permsProxy)));

        // wrap in ABI to support easier calls
        perms = AllowList(address(permsProxy));

        USCCv1 tokenImplementation = new USCCv1(address(this), perms);

        // repeat for the token contract
        tokenProxy = new TransparentUpgradeableProxy(address(tokenImplementation), address(this), "");
        tokenProxyAdmin = ProxyAdmin(getAdminAddress(address(tokenProxy)));

        // wrap in ABI to support easier calls
        token = USCCv1(address(tokenProxy));

        // initialize token contract
        token.initialize("Superstate Crypto Carry Fund", "USCC");

        // whitelist alice bob, and charlie (so they can tranfer to each other), but not mallory
        // Permission ordering: USTB, USCC, funds that dont yet exist ...
        AllowList.Permission memory allowPerms = AllowList.Permission(false, true, false, false, false, false);

        perms.setEntityIdForAddress(abcEntityId, alice);
        perms.setEntityIdForAddress(abcEntityId, bob);
        address[] memory addrs = new address[](1);
        addrs[0] = charlie;
        perms.setEntityPermissionAndAddresses(abcEntityId, addrs, allowPerms);
    }

    function testTokenName() public override {
        assertEq(SuperstateTokenV1(address(token)).name(), "Superstate Crypto Carry Fund");
    }

    function testTokenSymbol() public override {
        assertEq(SuperstateTokenV1(address(token)).symbol(), "USCC");
    }

    function testTransferFromWorksIfUsingEncumbranceAndSourceIsNotWhitelisted() public override {
        deal(address(token), mallory, 100e6);

        // whitelist mallory for setting encumbrances
        AllowList.Permission memory allowPerms = AllowList.Permission(false, true, false, false, false, false);
        address[] memory addrs = new address[](1);
        addrs[0] = mallory;
        perms.setEntityPermissionAndAddresses(2, addrs, allowPerms);
        vm.startPrank(mallory);
        token.encumber(bob, 20e6);
        token.approve(bob, 10e6);
        vm.stopPrank();

        // now un-whitelist mallory
        AllowList.Permission memory forbidPerms = AllowList.Permission(false, false, false, false, false, false);
        perms.setPermission(2, forbidPerms);

        // bob can transferFrom now-un-whitelisted mallory by spending her encumbrance to him, without issues
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Release(mallory, bob, 15e6);
        vm.expectEmit(true, true, true, true);
        emit Transfer(mallory, alice, 15e6);
        token.transferFrom(mallory, alice, 15e6);

        assertEq(token.balanceOf(mallory), 85e6);
        assertEq(token.balanceOf(alice), 15e6);
        assertEq(token.balanceOf(bob), 0e6);
        assertEq(token.encumbrances(mallory, bob), 5e6);
    }

    function testTransferFromRevertsIfEncumbranceLessThanAmountAndSourceNotWhitelisted() public override {
        deal(address(token), mallory, 100e6);

        // whitelist mallory for setting encumbrances
        AllowList.Permission memory allowPerms = AllowList.Permission(false, true, false, false, false, false);
        address[] memory addrs = new address[](1);
        addrs[0] = mallory;
        perms.setEntityPermissionAndAddresses(2, addrs, allowPerms);
        vm.startPrank(mallory);
        token.encumber(bob, 20e6);
        token.approve(bob, 10e6);
        vm.stopPrank();

        // now un-whitelist mallory
        AllowList.Permission memory forbidPerms = AllowList.Permission(false, false, false, false, false, false);
        perms.setPermission(2, forbidPerms);

        // reverts because encumbrances[src][bob] = 20 < amount and src (mallory) is not whitelisted
        vm.prank(bob);
        vm.expectRevert(ISuperstateTokenV1.InsufficientPermissions.selector);
        token.transferFrom(mallory, alice, 30e6);
    }

    function testUpgradingAllowListDoesNotAffectToken() public override {
        AllowListV2 permsV2Implementation = new AllowListV2(address(this));
        permsProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(permsProxy)), address(permsV2Implementation), ""
        );

        AllowListV2 permsV2 = AllowListV2(address(permsProxy));

        assertEq(address(token.allowList()), address(permsProxy));

        // check Alice, Bob, and Charlie still whitelisted
        assertEq(permsV2.getPermission(alice).state1, true);
        assertEq(permsV2.getPermission(bob).state1, true);
        assertEq(permsV2.getPermission(charlie).state1, true);

        deal(address(token), alice, 100e6);
        deal(address(token), bob, 100e6);
        // check Alice, Bob, and Charlie can still do whitelisted operations (transfer, transferFrom, encumber, encumberFrom)
        vm.prank(alice);
        token.transfer(bob, 10e6);

        assertEq(token.balanceOf(alice), 90e6);
        assertEq(token.balanceOf(bob), 110e6);

        vm.prank(bob);
        token.approve(alice, 40e6);

        vm.prank(alice);
        token.transferFrom(bob, charlie, 20e6);

        assertEq(token.balanceOf(bob), 90e6);
        assertEq(token.balanceOf(charlie), 20e6);

        vm.prank(bob);
        token.encumber(charlie, 20e6);

        vm.prank(alice);
        token.encumberFrom(bob, charlie, 10e6);

        assertEq(token.encumbrances(bob, charlie), 30e6);
    }

    function testUpgradingAllowListAndTokenWorks() public override {
        AllowListV2 permsV2Implementation = new AllowListV2(address(this));
        permsProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(permsProxy)), address(permsV2Implementation), ""
        );
        AllowListV2 permsV2 = AllowListV2(address(permsProxy));

        USCCV2 tokenV2Implementation = new USCCV2(address(this), permsV2);
        tokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenV2Implementation), ""
        );
        USCCV2 tokenV2 = USCCV2(address(tokenProxy));

        // Whitelisting criteria now requires `state7` (newly added state) be true,
        // so Alice, Bob, and Charlie no longer have sufficient permissions...
        assertEq(tokenV2.hasSufficientPermissions(alice), false);
        assertEq(tokenV2.hasSufficientPermissions(bob), false);
        assertEq(tokenV2.hasSufficientPermissions(charlie), false);

        deal(address(tokenV2), alice, 100e6);
        deal(address(tokenV2), bob, 100e6);

        // ...and cannot do regular token operations (transfer, transferFrom, encumber, encumberFrom)
        vm.prank(alice);
        vm.expectRevert(USTBV2.InsufficientPermissions.selector);
        tokenV2.transfer(bob, 10e6);

        vm.prank(charlie);
        vm.expectRevert("ERC20: insufficient allowance");
        tokenV2.transferFrom(alice, bob, 10e6);

        vm.prank(bob);
        vm.expectRevert(USTBV2.InsufficientPermissions.selector);
        tokenV2.encumber(charlie, 10e6);

        vm.prank(bob);
        tokenV2.approve(alice, 40e6);
        vm.prank(alice);
        vm.expectRevert(USTBV2.InsufficientPermissions.selector);
        tokenV2.encumberFrom(bob, charlie, 10e6);

        // But when we whitelist all three according to the new criteria...
        AllowListV2.Permission memory newPerms =
            AllowListV2.Permission(false, true, false, false, false, false, false, true);
        permsV2.setPermission(abcEntityId, newPerms);

        // ...they now have sufficient permissions
        assertEq(tokenV2.hasSufficientPermissions(alice), true);
        assertEq(tokenV2.hasSufficientPermissions(bob), true);
        assertEq(tokenV2.hasSufficientPermissions(charlie), true);

        // ...and can now do regular token operations (transfer, transferFrom, encumber, encumberFrom) without reverts
        vm.prank(alice);
        tokenV2.transfer(bob, 10e6);

        assertEq(tokenV2.balanceOf(alice), 90e6);
        assertEq(tokenV2.balanceOf(bob), 110e6);

        vm.prank(bob);
        tokenV2.approve(alice, 40e6);

        vm.prank(alice);
        tokenV2.transferFrom(bob, charlie, 20e6);

        assertEq(tokenV2.balanceOf(bob), 90e6);
        assertEq(tokenV2.balanceOf(charlie), 20e6);

        vm.prank(bob);
        tokenV2.encumber(charlie, 20e6);

        vm.prank(alice);
        tokenV2.encumberFrom(bob, charlie, 10e6);

        assertEq(tokenV2.encumbrances(bob, charlie), 30e6);
    }

    function testFuzzEncumbranceMustBeRespected(uint256 amt, address spender, address recipient, address recipient2)
        public
        override
    {
        AllowList.Permission memory allowPerms = AllowList.Permission(false, true, false, false, false, false);

        // cannot be address 0 - ERC20: transfer from the zero address
        // spender cannot be alice bob or charlie, they already have their permissions set
        vm.assume(spender != address(0) && spender != alice && spender != bob && spender != charlie);
        vm.assume(recipient != alice && recipient != bob && recipient != charlie);
        vm.assume(recipient2 != alice && recipient2 != bob && recipient2 != charlie);
        vm.assume(spender != recipient && recipient != recipient2 && spender != recipient2);
        vm.assume(recipient != address(0) && recipient2 != address(0));
        // proxy admin cant use protocol
        vm.assume(
            address(permsProxyAdmin) != spender && address(permsProxyAdmin) != recipient
                && address(permsProxyAdmin) != recipient2 && address(tokenProxyAdmin) != spender
                && address(tokenProxyAdmin) != recipient && address(tokenProxyAdmin) != recipient2
        );

        // whitelist spender and recipients
        address[] memory addrs = new address[](3);
        addrs[0] = spender;
        addrs[1] = recipient;
        addrs[2] = recipient2;

        perms.setEntityIdForMultipleAddresses(2, addrs);
        perms.setPermission(2, allowPerms);

        // limit range of amount
        uint256 amount = bound(amt, 1, type(uint128).max - 1);
        deal(address(token), spender, amount * 2);

        // encumber tokens to spender
        vm.prank(spender);
        token.encumber(recipient, amount);

        // encumber tokens to spender
        vm.prank(spender);
        token.encumber(recipient2, amount);

        // recipient calls transferFrom on spender
        vm.prank(recipient);
        token.transferFrom(spender, recipient, amount);

        // recipient calls transferFrom on spender
        vm.prank(recipient2);
        token.transferFrom(spender, recipient2, amount);
    }
}
