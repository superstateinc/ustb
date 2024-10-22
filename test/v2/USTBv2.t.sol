pragma solidity ^0.8.26;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import {SuperstateToken} from "src/SuperstateToken.sol";
import {USTBv1} from "src/v1/USTBv1.sol";
import {USTB} from "src/USTB.sol";
import {AllowList} from "src/AllowList.sol";
import "test/AllowListV2.sol";
import "test/USTBV2.sol";
import "test/SuperstateTokenTestBase.t.sol";

contract USTBv2Test is SuperstateTokenTestBase {
    SuperstateTokenV1 public tokenV1;

    function setUp() public override {
        eve = vm.addr(evePrivateKey);

        AllowList permsImplementation = new AllowList(address(this));

        // deploy proxy admin contract
        proxyAdmin = new ProxyAdmin();

        // deploy proxy contract and point it to implementation
        permsProxy = new TransparentUpgradeableProxy(address(permsImplementation), address(proxyAdmin), "");

        // wrap in ABI to support easier calls
        perms = AllowList(address(permsProxy));

        USTBv1 tokenV1Implementation = new USTBv1(address(this), perms);

        // repeat for the token contract
        tokenProxy = new TransparentUpgradeableProxy(address(tokenV1Implementation), address(proxyAdmin), "");

        // wrap in ABI to support easier calls
        tokenV1 = USTBv1(address(tokenProxy));

        // initialize token contract
        tokenV1.initialize("Superstate Short Duration US Government Securities Fund", "USTB");

        // whitelist alice bob, and charlie (so they can tranfer to each other), but not mallory
        AllowList.Permission memory allowPerms = AllowList.Permission(true, false, false, false, false, false);

        perms.setEntityIdForAddress(abcEntityId, alice);
        perms.setEntityIdForAddress(abcEntityId, bob);
        address[] memory addrs = new address[](1);
        addrs[0] = charlie;
        perms.setEntityPermissionAndAddresses(abcEntityId, addrs, allowPerms);

        // Pause accounting?

        // Now upgrade to V2
        USTB tokenImplementation = new USTB(address(this), perms);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenImplementation));

        /*
            At this point, owner() is 0x00 because the upgraded contract has not
            initialized.

            admin() is the same from the prior version of the contract
        */

        // initialize v2 of the contract, specifically the new authorization
        // mechanism via owner()
        token = USTB(address(tokenProxy));
        SuperstateToken(address(token)).initializeV2();

        /*
            At this point, owner() is the same as admin() and is the source of truth
            for authorization. admin() will no longer be used, and for future versions of the contract it need
            not even be initialized.
        */
    }
}
