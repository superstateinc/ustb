// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

contract MockContract {
    // Empty contract to test protocol permissions
    // Just needs to have code size > 0
    function dummy() public pure returns (bool) {
        return true;
    }
}