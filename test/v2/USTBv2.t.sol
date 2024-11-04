pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {SuperstateTokenV2} from "src/v2/SuperstateTokenV2.sol";
import {USTBv1} from "src/v1/USTBv1.sol";
import {USTBv2} from "src/v2/USTBv2.sol";
import {AllowListV1} from "src/allowlist/v1/AllowListV1.sol";
import "test/TestAllowList.sol";
import "test/USTBV2.sol";
import "test/SuperstateTokenTestBase.t.sol";
import {ISuperstateTokenV2} from "src/interfaces/ISuperstateTokenV2.sol";

contract USTBv2Test is SuperstateTokenTestBase {
    SuperstateTokenV1 public tokenV1;

    function setUp() public override {
        eve = vm.addr(evePrivateKey);

        AllowListV1 permsImplementation = new AllowListV1(address(this));

        // deploy proxy contract and point it to implementation
        permsProxy = new TransparentUpgradeableProxy(address(permsImplementation), address(this), "");
        permsProxyAdmin = ProxyAdmin(getAdminAddress(address(permsProxy)));

        // wrap in ABI to support easier calls
        perms = AllowListV1(address(permsProxy));

        USTBv1 tokenV1Implementation = new USTBv1(address(this), AllowListV1(address(perms)));

        // repeat for the token contract
        tokenProxy = new TransparentUpgradeableProxy(address(tokenV1Implementation), address(this), "");
        tokenProxyAdmin = ProxyAdmin(getAdminAddress(address(tokenProxy)));

        // wrap in ABI to support easier calls
        tokenV1 = USTBv1(address(tokenProxy));

        // initialize token contract
        tokenV1.initialize("Superstate Short Duration US Government Securities Fund", "USTB");

        // whitelist alice bob, and charlie (so they can tranfer to each other), but not mallory
        IAllowList.Permission memory allowPerms = IAllowList.Permission(true, false, false, false, false, false);

        perms.setEntityIdForAddress(abcEntityId, alice);
        perms.setEntityIdForAddress(abcEntityId, bob);
        address[] memory addrs = new address[](1);
        addrs[0] = charlie;
        perms.setEntityPermissionAndAddresses(abcEntityId, addrs, allowPerms);

        // Pause accounting?

        // Now upgrade to V2
        USTBv2 tokenImplementation = new USTBv2(address(this), AllowListV1(address(perms)));
        tokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenImplementation), ""
        );

        /*
            At this point, owner() is 0x00 because the upgraded contract has not
            initialized.

            admin() is the same from the prior version of the contract
        */

        // initialize v2 of the contract, specifically the new authorization
        // mechanism via owner()
        token = USTBv2(address(tokenProxy));
        SuperstateTokenV2(address(token)).initializeV2();

        /*
            At this point, owner() is the same as admin() and is the source of truth
            for authorization. admin() will no longer be used, and for future versions of the contract it need
            not even be initialized.
        */
    }

    function testRenounceOwnershipBlocked() public {
        vm.expectRevert(ISuperstateTokenV2.RenounceOwnershipDisabled.selector);
        SuperstateTokenV2(address(token)).renounceOwnership();
    }
}
