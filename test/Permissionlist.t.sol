pragma solidity ^0.8.20;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

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

    address alice = address(10);
    address bob = address(11);

    function setUp() public {
        admin = new ProxyAdmin(address(this));

        implementation = new Permissionlist();
        // deploy proxy contract and point it to implementation
        proxy = new TransparentUpgradeableProxy(address(implementation), address(admin), "");

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
        wrappedProxyV2 = PermissionlistV2(address(implementationV2));

        // check permission admin hasn't changed
        assertEq(wrappedProxyV2.permissionAdmin(), address(this));

        // TODO: check bob's whitelisting hasn't changed
        // assertEq(wrappedProxyV2.getPermission(bob).allowed, true);

        // and test setting new Permission struct...
    }
}
