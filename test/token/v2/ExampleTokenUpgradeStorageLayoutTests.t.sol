pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import "test/token/TokenTestBase.t.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

/*
* This test shows that we can safely upgrade from SuperstateTokenV1 to SuperstateTokenV2
* Steps we'll need to do:
*   > Add __gap at the beginning of `SuperstateToken`
*   > Add __gap2 at the end of `SuperstateToken`
*   > Optionally remove `encumberedBalanceOf`, `encumberances` as they have not been used in v1 and thus will not have corrupt storage
*/
contract ExampleTokenUpgradeStorageLayoutTests is TokenTestBase {
    TransparentUpgradeableProxy tokenProxy;

    function setUp() public {}

    function loadSlot(uint256 slot) public view returns (bytes32) {
        return vm.load(address(tokenProxy), bytes32(slot));
    }

    function testExampleUpgradeStorageLayout() public {
        // create TokenV1 and proxies
        TokenV1 tokenV1Impl = new TokenV1();

        tokenProxy = new TransparentUpgradeableProxy(address(tokenV1Impl), address(this), "");
        ProxyAdmin proxyAdmin = ProxyAdmin(getAdminAddress(address(tokenProxy)));

        TokenV1 tokenV1 = TokenV1(address(tokenProxy));

        // init TokenV1
        tokenV1.init();

        // assert storage
        uint256 expectedA = 1;
        assertEq(expectedA, uint256(loadSlot(0))); // a
        assertEq(expectedA, tokenV1.a());

        uint256 expectedTV1Unused = 0;
        assertEq(expectedTV1Unused, uint256(loadSlot(1))); // tV1_unused
        assertEq(expectedTV1Unused, tokenV1.tV1_unused());

        // create TokenV2 and update proxy
        TokenV2 tokenV2Impl = new TokenV2();
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenV2Impl), "");
        TokenV2 tokenV2 = TokenV2(address(tokenProxy));

        // init TokenV2
        tokenV2.initV2(); // overwrites tV1_unused w/ b

        // assert storage
        assertEq(expectedA, uint256(loadSlot(0))); // a, storage preserved

        uint256 expectedB = 2;
        assertEq(expectedB, uint256(loadSlot(1))); // b, overwrote tV1_unused
        assertEq(expectedB, tokenV2.b());

        for (uint256 i = 2; i < 50; i++) {
            assertEq(0, uint256(loadSlot(i))); // empty gap
        }

        uint256 expectedTV2 = 3;
        assertEq(expectedTV2, uint256(loadSlot(51))); // tV2, past the __gap
        assertEq(expectedTV2, tokenV2.tV2());

        // create TokenV3 and update proxy
        TokenV3 tokenV3Impl = new TokenV3();
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(tokenProxy)), address(tokenV3Impl), "");
        TokenV3 tokenV3 = TokenV3(address(tokenProxy));

        // init TokenV3
        tokenV3.initV3();

        // assert storage
        assertEq(expectedA, uint256(loadSlot(0))); // a, storage preserved
        assertEq(expectedB, uint256(loadSlot(1))); // b, storage preserved from V2

        uint256 expectedC = 4;
        assertEq(expectedC, uint256(loadSlot(2)));
        assertEq(expectedC, tokenV3.c());

        for (uint256 i = 3; i < 50; i++) {
            // note: gap has one less slot due to `C.c`
            assertEq(0, uint256(loadSlot(i))); // empty gap
        }

        assertEq(expectedTV2, uint256(loadSlot(51))); // tV2, past the __gap
        assertEq(expectedTV2, tokenV3.tV2());

        uint256 expectedTV3 = 5;
        assertEq(expectedTV3, uint256(loadSlot(52))); // tV3
        assertEq(expectedTV3, tokenV3.tV3());
    }
}

contract A {
    uint256 public a;
}

contract B {
    uint256 public b;
}

contract C {
    uint256 public c;
}

/*
* Storage:
* Slot 0: A.a
* Slot 1: TokenV1.tV1_unused
*/
contract TokenV1 is A {
    uint256 public tV1_unused; // mimics encumberances, which has currently never been used

    function init() public {
        a = 1;
    }
}

/*
* Storage:
* Slot 0: A.a
* Slot 1: B.b
* Slot 2-50: TokenV2.__gap
* Slot 51: tV2;
*/
contract TokenV2 is A, B {
    // removed tV1_unused
    uint256[49] private __gap;
    uint256 public tV2;

    function init() public {
        a = 1;
    }

    function initV2() public {
        b = 2;
        tV2 = 3;
    }
}

/*
* Storage:
* Slot 0: A.a
* Slot 1: B.b
* Slot 2: C.c
* Slot 3-50: TokenV2.__gap
* Slot 51: tV2;
* Slot 52: tV3;
*/
contract TokenV3 is A, B, C {
    uint256[48] private __gap; // element removed from gap to account for new var `C.c`
    uint256 public tV2;
    uint256 public tV3;

    function init() public {
        a = 1;
    }

    function initV2() public {
        b = 2;
        tV2 = 3;
    }

    function initV3() public {
        c = 4;
        tV3 = 5;
    }
}
