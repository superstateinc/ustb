pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {SuperstateTokenV2} from "src/v2/SuperstateTokenV2.sol";
import {USTBv2} from "src/v2/USTBv2.sol";
import {USTB} from "src/USTB.sol";
import {AllowList} from "src/allowlist/AllowList.sol";
import {AllowListV1} from "src/allowlist/v1/AllowListV1.sol";
import {IAllowList} from "src/interfaces/allowlist/IAllowList.sol";
import "test/SuperstateTokenTestBase.t.sol";

contract USTBv3Test is SuperstateTokenTestBase {
    SuperstateTokenV1 public tokenV1;
    SuperstateTokenV2 public tokenV2;

    function setUp() public override {
        eve = vm.addr(evePrivateKey);

        AllowList permsImplementation = new AllowList(address(this));

        // deploy proxy contract and point it to implementation
        permsProxy = new TransparentUpgradeableProxy(address(permsImplementation), address(this), "");
        permsProxyAdmin = ProxyAdmin(getAdminAddress(address(permsProxy)));

        // wrap in ABI to support easier calls
        perms = AllowList(address(permsProxy));

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

        // Now upgrade to V2
        tokenV2 = new USTBv2(address(this), AllowListV1(address(perms)));
        tokenProxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenV2), "");

        /*
            At this point, owner() is 0x00 because the upgraded contract has not
            initialized.

            admin() is the same from the prior version of the contract
        */

        // initialize v2 of the contract, specifically the new authorization
        // mechanism via owner()
        tokenV2 = USTBv2(address(tokenProxy));
        SuperstateTokenV2(address(tokenV2)).initializeV2();

        /*
            At this point, owner() is the same as admin() and is the source of truth
            for authorization. admin() will no longer be used, and for future versions of the contract it need
            not even be initialized.
        */

        // Now upgrade to V3
        USTB tokenImplementation = new USTB(AllowList(address(perms))); // TODO - this will need to be allowListV2
        tokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenImplementation), ""
        );

        token = USTB(address(tokenProxy));
        // No initialization needed for V3
    }

    function testFoobar() public {}

    // TODO: add all tests for new functionality
}
