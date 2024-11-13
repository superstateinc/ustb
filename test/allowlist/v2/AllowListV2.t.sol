pragma solidity ^0.8.28;

import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {SuperstateTokenV1} from "src/v1/SuperstateTokenV1.sol";
import {ISuperstateTokenV1} from "src/interfaces/ISuperstateTokenV1.sol";
import {USTBv1} from "src/v1/USTBv1.sol";
import {AllowListV1} from "src/allowlist/v1/AllowListV1.sol";
import {IAllowList} from "src/interfaces/allowlist/IAllowList.sol";
import {IAllowListV2} from "src/interfaces/allowlist/IAllowListV2.sol";
import "test/allowlist/mocks/MockAllowList.sol";
import "test/token/mocks/MockUSTBv1.sol";
import "test/token/TokenTestBase.t.sol";
import {AllowList} from "src/allowlist/AllowList.sol";
import {AllowListTestBase} from "../AllowListTestBase.t.sol";

contract AllowListV2Test is AllowListTestBase {}
