// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {IERC7246} from "src/interfaces/IERC7246.sol";
import {AllowList} from "src/allowlist/AllowList.sol";
import {ISuperstateTokenV2} from "./ISuperstateTokenV2.sol";

interface ISuperstateToken is ISuperstateTokenV2 {
    /// @dev Struct for storing supported stablecoin configuration
    struct StablecoinConfig {
        address sweepDestination;
        uint96 fee;
    }

    /// @dev Emitted when the max oracle delay is set
    event SetMaximumOracleDelay(uint256 oldMaxOracleDelay, uint256 newMaxOracleDelay);

    /// @dev Event emitted when the address for the pricing oracle changes
    event SetOracle(address oldOracle, address newOracle);

    /// @dev Event emitted when the configuration for a supported stablecoin changes
    event SetStablecoinConfig(
        address indexed stablecoin,
        address oldSweepDestination,
        address newSweepDestination,
        uint96 oldFee,
        uint96 newFee
    );

    /// @dev Event emitted when stablecoins are used to Subscribe to a Superstate fund
    event Subscribe(
        address indexed subscriber,
        address stablecoin,
        uint256 stablecoinInAmount,
        uint256 stablecoinInAmountAfterFee,
        uint256 superstateTokenOutAmount
    );

    /// @dev Thrown when an argument is invalid
    error BadArgs();

    /// @dev Thrown when Chainlink Oracle data is bad
    error BadChainlinkData();

    /// @dev Thrown when owner tries to set the fee for a stablecoin too high
    error FeeTooHigh();

    /// @dev Thrown when the superstateUstbOracle is the 0 address
    error OnchainSubscriptionsDisabled();

    /// @dev Thrown when trying to calculate amount of Superstate Tokens you'd get for an unsupported stablecoin
    error StablecoinNotSupported();

    /// @dev Thrown when the msg.sender would receive 0 Superstate tokens out for their call to subscribe
    error ZeroSuperstateTokensOut();
}
