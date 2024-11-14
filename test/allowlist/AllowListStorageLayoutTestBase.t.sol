pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import "forge-std/console.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {AllowListV1} from "src/allowlist/v1/AllowListV1.sol";
import {IAllowList} from "src/interfaces/allowlist/IAllowList.sol";
import {IAllowListV2} from "src/interfaces/allowlist/IAllowListV2.sol";
import "test/token/TokenTestBase.t.sol";
import {AllowList} from "src/allowlist/AllowList.sol";
import {MockContract} from "test/allowlist/mocks/MockContract.sol";

/*
* Note: This is used for v2 and beyond, as v1 is incompatible and this is known/accepted.
*/
abstract contract AllowListStorageLayoutTestBase is TokenTestBase {
    ProxyAdmin allowListProxyAdmin;
    TransparentUpgradeableProxy allowListProxy;

    IAllowListV2 oldAllowList;
    IAllowListV2 newAllowList;
    IAllowListV2 currentAllowList;

    string public oldAllowListVersion;
    string public newAllowListVersion;

    address alice = address(10);
    address bob = address(11);
    address charlie = address(12);

    IAllowListV2.EntityId aliceEntityId = IAllowListV2.EntityId.wrap(10);
    IAllowListV2.EntityId bobEntityId = IAllowListV2.EntityId.wrap(11);

    MockContract public mockProtocol;
    MockContract public mockProtocol2;

    function setUp() public virtual {
        mockProtocol = new MockContract();
        mockProtocol2 = new MockContract();

        initializeExpectedTokenVersions();
        initializeOldAllowList();
    }

    function initializeExpectedTokenVersions() public virtual;

    function initializeOldAllowList() public virtual;

    function upgradeAndInitializeNewAllowList() public virtual;

    function manipulateStateOldAllowList() public {
        // allowlist bob and charlie to the same entity
        address[] memory addrsToSet = new address[](2);
        addrsToSet[0] = bob;
        addrsToSet[1] = charlie;
        string[] memory fundsToSet = new string[](2);
        fundsToSet[0] = "USTB";
        fundsToSet[1] = "USCC";
        bool[] memory fundPermissionsToSet = new bool[](2);
        fundPermissionsToSet[0] = true;
        fundPermissionsToSet[1] = false;
        oldAllowList.setEntityPermissionsAndAddresses(bobEntityId, addrsToSet, fundsToSet, fundPermissionsToSet);

        oldAllowList.setProtocolAddressPermission(address(mockProtocol), "USTB", true);
        //oldAllowList.setProtocolAddressPermission(address(mockProtocol), "USCC", false); // AlreadySet()
    }

    function loadSlot(uint256 slot) public view returns (bytes32) {
        return vm.load(address(allowListProxy), bytes32(slot));
    }

    function assertStorageLayout() public {
        assertOwnable2StepUpgradeableStorageLayout();
        assertAllowListStorageLayout();
    }

    function assertOwnable2StepUpgradeableStorageLayout() public {
        //
        // assert Initializable
        //

        // assert _initialized (storage slot 0)
        uint256 initializedSlotValue = uint256(loadSlot(0));
        uint256 expectedInitialized = 1;
        assertEq(initializedSlotValue, expectedInitialized);

        // assert _initializing (storage slot 1)
        uint256 initializingSlotValue = uint256(loadSlot(1));
        uint256 expectedInitializing = 0;
        assertEq(initializingSlotValue, expectedInitializing);

        //
        // assert ContextUpgradeable
        //

        // assert __gap (storage slots 2-50)
        for (uint256 i = 1; i <= 50; ++i) {
            assertEq(uint256(loadSlot(i)), 0);
        }

        //
        // assert OwnableUpgradeable
        //

        // assert _owner (storage slot 51)
        address ownerSlotValue = address(uint160(uint256(loadSlot(51))));
        address expectedOwner = address(this);
        assertEq(ownerSlotValue, expectedOwner);

        // assert _owner from contract method
        assertEq(AllowList(address(currentAllowList)).owner(), expectedOwner);

        // assert __gap (storage slots 52-100)
        for (uint256 i = 52; i <= 100; ++i) {
            assertEq(uint256(loadSlot(i)), 0);
        }
    }

    function assertAllowListStorageLayout() public {
        // assert __inheritanceGap (storage slots 101-650)
        for (uint256 i = 101; i <= 650; ++i) {
            assertEq(uint256(loadSlot(i)), 0);
        }

        // assert addressEntityIds (storage slot 651)
        bytes32 addressEntityIdsBobSlot = keccak256(abi.encode(bob, uint256(651)));
        uint256 addressEntityIdsBobSlotValue = uint256(vm.load(address(allowListProxy), addressEntityIdsBobSlot));
        IAllowListV2.EntityId expectedBobEntityId = bobEntityId;
        assertEq(addressEntityIdsBobSlotValue, IAllowListV2.EntityId.unwrap(bobEntityId));

        // assert addressEntityIds from contract method
        assertEq(
            IAllowListV2.EntityId.unwrap(AllowList(address(allowListProxy)).addressEntityIds(bob)),
            IAllowListV2.EntityId.unwrap(expectedBobEntityId)
        );

        // assert fundPermissionsByEntityId (storage slot 652)
        bytes32 fundPermissionsByEntityIdBobSlot =
            keccak256(abi.encodePacked(IAllowListV2.EntityId.unwrap(bobEntityId), uint256(652)));
        bytes32 fundPermissionBobSlot = keccak256(abi.encodePacked("USTB", uint256(fundPermissionsByEntityIdBobSlot)));
        uint256 fundPermissionBobSlotValue = uint256(vm.load(address(allowListProxy), fundPermissionBobSlot));
        uint256 expectedFundPermissionBobSlot = 1; // 1 == true
        assertEq(fundPermissionBobSlotValue, expectedFundPermissionBobSlot);

        // assert fundPermissionsByEntityId from contract method
        assertTrue(currentAllowList.isEntityAllowedForFund(bobEntityId, "USTB"));

        // assert protocolPermissionsForFunds (storage slot 653)
        bytes32 protocolPermissionsForFundsProtocol = keccak256(abi.encode(address(mockProtocol), uint256(653)));
        uint256 protocolPermissionsForFundsSlotValue =
            uint256(vm.load(address(allowListProxy), protocolPermissionsForFundsProtocol));
        uint256 expectedCount = 1;
        assertEq(protocolPermissionsForFundsSlotValue, expectedCount, "butt");

        // assert protocolPermissionsForFunds from contract method
        assertEq(AllowList(address(allowListProxy)).protocolPermissionsForFunds(address(mockProtocol)), expectedCount);

        // assert protocolPermissions (storage slot 654)
        bytes32 protocolPermissionsProtocolSlot = keccak256(abi.encodePacked(address(mockProtocol), uint256(654)));
        bytes32 protocolPermissionsSlot = keccak256(abi.encodePacked("USTB", uint256(protocolPermissionsProtocolSlot)));
        uint256 protocolPermissionsSlotValue = uint256(vm.load(address(allowListProxy), protocolPermissionsSlot));
        uint256 expectedValue = 1; // 1 == true
        assertEq(protocolPermissionsSlotValue, expectedValue); // This fails

        // assert protocolPermissions from contract method
        assertTrue(currentAllowList.protocolPermissions(address(mockProtocol), "USTB"));

        // assert __additionalFieldsGap (storage slots 655-755)
        for (uint256 i = 655; i <= 755; ++i) {
            assertEq(uint256(loadSlot(i)), 0);
        }
    }

    function testUpgradeStorageLayout() public {
        // do some state manipulation
        manipulateStateOldAllowList();

        // assert storage layout
        assertStorageLayout();

        // upgrade to newToken
        upgradeAndInitializeNewAllowList();

        // assert storage layout
        assertStorageLayout();
    }
}
