pragma solidity ^0.8.28;

import "test/allowlist/AllowListStorageLayoutTestBase.t.sol";
import "forge-std/StdUtils.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "test/token/TokenTestBase.t.sol";
import {AllowListV1} from "src/allowlist/v1/AllowListV1.sol";
import {AllowList} from "src/allowlist/AllowList.sol";
import {IAllowListV2} from "src/interfaces/allowlist/IAllowListV2.sol";
import {IAllowList} from "src/interfaces/allowlist/IAllowList.sol";

/**
 * AllowListV2 Token Storage Layout:
 * Slot 0: Initializable._initialized
 * Slot 1: Initializable._initializing
 * Slot 2-50: ContextUpgradeable.__gap
 * Slot 51: OwnableUpgradeable._owner
 * Slot 52-100: OwnableUpgradeable.__gap
 * Slot 101-650: AllowList.__inheritanceGap
 * Slot 651: AllowList.addressEntityIds
 * Slot 652: AllowList.fundPermissionsByEntityId
 * Slot 653: AllowList.protocolPermissionsForFunds
 * Slot 654: AllowList.protocolPermissions
 * Slot 655-755: AllowList.__additionalFieldsGap
 */
contract AllowListV2StorageLayoutTests is AllowListStorageLayoutTestBase {
    function initializeExpectedTokenVersions() public override {
        // Note: v1 is incompatible, so this test is just going to trivially "upgrade" to the same version
        oldAllowListVersion = "2";
        newAllowListVersion = "2";
    }

    function initializeOldAllowList() public override {
        AllowList allowListImplementation = new AllowList();

        allowListProxy = new TransparentUpgradeableProxy(address(allowListImplementation), address(this), "");

        allowListProxyAdmin = ProxyAdmin(getAdminAddress(address(allowListProxy)));

        oldAllowList = IAllowListV2(address(allowListProxy));

        oldAllowList.initialize();

        currentAllowList = oldAllowList;
    }

    function upgradeAndInitializeNewAllowList() public override {
        // Note: v1 is incompatible, so this test is just going to trivially "upgrade" to the same version
        AllowList newAllowListImplementation = new AllowList();

        allowListProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(allowListProxy)), address(newAllowListImplementation), ""
        );

        newAllowList = IAllowListV2(address(allowListProxy));

        currentAllowList = newAllowList;
    }
}
