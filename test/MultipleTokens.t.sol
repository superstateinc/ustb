pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {USTBv2} from "src/v2/USTBv2.sol";
import {USCCv2} from "src/v2/USCCv2.sol";
import {AllowList} from "src/allowlist/AllowList.sol";

contract MultiTokenTest is Test {
    event Encumber(address indexed owner, address indexed taker, uint256 amount);
    event Release(address indexed owner, address indexed taker, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed minter, address indexed to, uint256 amount);
    event Burn(address indexed burner, address indexed from, uint256 amount);
    event AccountingPaused(address admin);
    event AccountingUnpaused(address admin);

    ProxyAdmin proxyAdmin;
    TransparentUpgradeableProxy permsProxy;
    AllowList public perms;
    TransparentUpgradeableProxy tokenProxyUstb;
    TransparentUpgradeableProxy tokenProxyUscc;
    USTBv2 public ustb;
    USCCv2 public uscc;

    address alice = address(10);
    address bob = address(11);
    address charlie = address(12);
    address mallory = address(13);
    uint256 evePrivateKey = 0x353;
    address eve; // see setup()

    uint256 abcEntityId = 1;

    bytes32 internal constant AUTHORIZATION_TYPEHASH =
        keccak256("Authorization(address owner,address spender,uint256 amount,uint256 nonce,uint256 expiry)");

    function setUp() public {
        eve = vm.addr(evePrivateKey);

        AllowList permsImplementation = new AllowList(address(this));

        // deploy proxy admin contract
        proxyAdmin = new ProxyAdmin(address(this));

        // deploy proxy contract and point it to implementation
        permsProxy = new TransparentUpgradeableProxy(address(permsImplementation), address(proxyAdmin), "");

        // wrap in ABI to support easier calls
        perms = AllowList(address(permsProxy));

        USTBv2 ustbImplementation = new USTBv2(address(this), perms);
        USCCv2 usccImplementation = new USCCv2(address(this), perms);

        // repeat for the token contract
        tokenProxyUstb = new TransparentUpgradeableProxy(address(ustbImplementation), address(proxyAdmin), "");
        tokenProxyUscc = new TransparentUpgradeableProxy(address(usccImplementation), address(proxyAdmin), "");

        // wrap in ABI to support easier calls
        ustb = USTBv2(address(tokenProxyUstb));
        uscc = USCCv2(address(tokenProxyUscc));

        // initialize token contract
        ustb.initialize("Superstate Short Duration US Government Securities Fund", "USTB");
        uscc.initialize("Superstate Crypto Carry Fund", "USCC");

        // whitelist alice bob, and charlie for both funds (so they can transfer to each other), but not mallory
        AllowList.Permission memory allowPerms = AllowList.Permission(true, true, false, false, false, false);

        perms.setEntityIdForAddress(abcEntityId, alice);
        perms.setEntityIdForAddress(abcEntityId, bob);
        address[] memory addrs = new address[](1);
        addrs[0] = charlie;
        perms.setEntityPermissionAndAddresses(abcEntityId, addrs, allowPerms);
    }

    function testCanUseBothTokens() public {
        deal(address(ustb), alice, 100e6);
        deal(address(ustb), bob, 100e6);

        deal(address(uscc), alice, 100e6);
        deal(address(uscc), bob, 100e6);

        vm.startPrank(bob);
        ustb.transfer(alice, 100e6);
        uscc.transfer(alice, 100e6);
        vm.stopPrank();

        assertEq(ustb.balanceOf(alice), 200e6);
        assertEq(uscc.balanceOf(alice), 200e6);

        assertEq(ustb.balanceOf(bob), 0);
        assertEq(uscc.balanceOf(bob), 0);
    }
}
