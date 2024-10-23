pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import {SuperstateTokenV1} from "src/v1/SuperstateTokenV1.sol";
import {ISuperstateToken} from "src/interfaces/ISuperstateToken.sol";
import {SuperstateToken} from "src/SuperstateToken.sol";
import {USTBv1} from "src/v1/USTBv1.sol";
import {USTB} from "src/USTB.sol";
import {AllowList} from "src/AllowList.sol";
import "test/AllowListV2.sol";
import "test/USTBV2.sol";
import "test/SuperstateTokenStorageLayoutTestBase.t.sol";

contract USTBv2TokenStorageLayoutTests is SuperstateTokenStorageLayoutTestBase {
    function initializeExpectedTokenVersions() public override {
        oldTokenVersion = "1";
        newTokenVersion = "2";
    }

    function initializeOldToken() public override {
        USTBv1 oldTokenImplementation = new USTBv1(address(this), perms);
        tokenProxy = new TransparentUpgradeableProxy(address(oldTokenImplementation), address(proxyAdmin), "");

        // wrap in ABI to support easier calls
        oldToken = USTBv1(address(tokenProxy));

        oldToken.initialize("Superstate Short Duration US Government Securities Fund", "USTB");

        currentToken = USTBv1(address(tokenProxy));
    }

    function upgradeAndInitializeNewToken() public override {
        // Now upgrade to V2
        USTB newTokenImplementation = new USTB(address(this), perms);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(tokenProxy)), address(newTokenImplementation));

        /*
            At this point, owner() is 0x00 because the upgraded contract has not
            initialized.

            admin() is the same from the prior version of the contract
        */

        // initialize v2 of the contract, specifically the new authorization
        // mechanism via owner()
        newToken = USTB(address(tokenProxy));
        SuperstateToken(address(newToken)).initializeV2();

        currentToken = newToken;
    }
}
