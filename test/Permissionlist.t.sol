pragma solidity ^0.8.20;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import "src/Permissionlist.sol";
import "src/PermissionlistV2.sol";

contract PermissionlistTest is Test {
    TransparentUpgradeableProxy proxy;
    ProxyAdmin admin;

    Permissionlist public implementation;
    Permissionlist public wrappedProxy;
    PermissionlistV2 public wrappedProxyV2;

    // Storage slot with the admin of the contract.
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address alice = address(10);
    address bob = address(11);

    function setUp() public {
        implementation = new Permissionlist();
        // deploy proxy contract and point it to implementation
        proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");

        bytes32 proxyAdminAddress = vm.load(address(proxy), ADMIN_SLOT);
        admin = ProxyAdmin(address(uint160(uint256(proxyAdminAddress))));

        // wrap in ABI to support easier calls
        wrappedProxy = Permissionlist(address(proxy));
        wrappedProxy.initialize(address(this));

        // whitelist bob
        Permissionlist.Permission memory allowPerms = Permissionlist.Permission(true);
        wrappedProxy.setPermission(bob, allowPerms);
    }

    function testInitialize() public {
        assertEq(wrappedProxy.permissionAdmin(), address(this));
    }

    function testSetAllowPerms() public {
        assertEq(wrappedProxy.getPermission(alice).allowed, false);

        // allow alice
        Permissionlist.Permission memory newPerms = Permissionlist.Permission(true);
        wrappedProxy.setPermission(alice, newPerms);

        assertEq(wrappedProxy.getPermission(alice).allowed, true);
    }

    function testSetDisallowPerms() public {
        assertEq(wrappedProxy.getPermission(bob).allowed, true);

        // disallow bob
        Permissionlist.Permission memory disallowPerms = Permissionlist.Permission(false);
        wrappedProxy.setPermission(bob, disallowPerms);

        assertEq(wrappedProxy.getPermission(bob).allowed, false);
    }

    function testUndoAllowPerms() public {
        assertEq(wrappedProxy.getPermission(alice).allowed, false);

        // allow alice
        Permissionlist.Permission memory allowPerms = Permissionlist.Permission(true);
        wrappedProxy.setPermission(alice, allowPerms);
        assertEq(wrappedProxy.getPermission(alice).allowed, true);

        // now disallow alice
        Permissionlist.Permission memory disallowPerms = Permissionlist.Permission(false);
        wrappedProxy.setPermission(alice, disallowPerms);
        assertEq(wrappedProxy.getPermission(alice).allowed, false);
    }

    function testUpgradePermissions() public {
        PermissionlistV2 implementationV2 = new PermissionlistV2();

        admin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(implementationV2), "");

        // re-wrap proxy
        wrappedProxyV2 = PermissionlistV2(address(proxy));

        // check permission admin didn't change
        assertEq(wrappedProxyV2.permissionAdmin(), address(this));

        // check bob's whitelisting hasn't changed
        assertEq(wrappedProxyV2.getPermission(bob).allowed, true);

        // check bob's new statuses are at default false values
        assertEq(wrappedProxyV2.getPermission(bob).isKyc, false);
        assertEq(wrappedProxyV2.getPermission(bob).isAccredited, false);

        // set new multi-permission values for bob
        PermissionlistV2.Permission memory multiPerms = PermissionlistV2.Permission(true, true, false);
        wrappedProxyV2.setPermission(bob, multiPerms);

        assertEq(wrappedProxyV2.getPermission(bob).allowed, true);
        assertEq(wrappedProxyV2.getPermission(bob).isKyc, true);
        assertEq(wrappedProxyV2.getPermission(bob).isAccredited, false);

        // set new perms admin
        wrappedProxyV2.setAdmin(alice);
        assertEq(wrappedProxyV2.permissionAdmin(), alice);
    }
}
