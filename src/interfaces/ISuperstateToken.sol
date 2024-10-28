// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {IERC7246} from "src/interfaces/IERC7246.sol";
import {AllowList} from "src/AllowList.sol";

interface ISuperstateToken is IERC20Upgradeable, IERC7246 {
    /// @dev Struct for storing supported stablecoin configuration
    struct StablecoinConfig {
        address sweepDestination;
        uint96 fee;
    }

    /// @dev Event emitted when tokens are minted
    event Mint(address indexed minter, address indexed to, uint256 amount);

    /// @dev Event emitted when tokens are burned
    event Burn(address indexed burner, address indexed from, uint256 amount);

    /// @dev Emitted when the accounting pause is triggered by `admin`.
    event AccountingPaused(address admin);

    /// @dev Emitted when the accounting pause is lifted by `admin`.
    event AccountingUnpaused(address admin);

    /// @dev Emitted when the max oracle delay is set
    event SetMaximumOracleDelay(uint256 oldMaxOracleDelay, uint256 newMaxOracleDelay);

    /// @dev Event emitted when stablecoins are used to Subscribe to a Superstate fund
    event Subscribe(
        address indexed subscriber, address stablecoin, uint256 stablecoinInAmount, uint256 stablecoinInAmountAfterFee, uint256 superstateTokenOutAmount
    );

    /// @dev Event emitted when the configuration for a supported stablecoin changes
    event StablecoinConfigUpdated(
        address indexed stablecoin, address oldSweepDestination, address newSweepDestination, uint96 oldFee, uint96 newFee
    );

    /// @dev Event emitted when the address for the pricing oracle changes
    event OracleUpdated(address oldOracle, address newOracle);

    /// @dev Thrown when a request is not sent by the authorized admin
    error Unauthorized();

    /// @dev Thrown when an address does not have sufficient permissions, as dictated by the AllowList
    error InsufficientPermissions();

    /// @dev Thrown when an address does not have a sufficient balance of unencumbered tokens
    error InsufficientAvailableBalance();

    /// @dev Thrown when the amount of tokens to spend or release exceeds the amount encumbered to the taker
    error InsufficientEncumbrance();

    /// @dev Thrown when the current timestamp has surpassed the expiration time for a signature
    error SignatureExpired();

    /// @dev Thrown if the signature has an S value that is in the upper half order.
    error InvalidSignatureS();

    /// @dev Thrown if the signature is invalid or its signer does not match the expected singer
    error BadSignatory();

    /// @dev Thrown if accounting pause is already on
    error AccountingIsPaused();

    /// @dev Thrown if accounting pause is already off
    error AccountingIsNotPaused();

    /// @dev Thrown if an address tries to encumber tokens to itself
    error SelfEncumberNotAllowed();

    /// @dev Thrown if array length arguments aren't equal
    error InvalidArgumentLengths();

    /// @dev Thrown when an argument is invalid
    error BadArgs();

    /// @dev Thrown when Chainlink Oracle data is bad
    error BadChainlinkData();

    /// @dev Thrown when the superstateUstbOracle is the 0 address
    error OnchainSubscriptionsDisabled();

    /// @dev Thrown when trying to calculate amount of Superstate Tokens you'd get for an unsupported stablecoin
    error StablecoinNotSupported();

    /// @dev Thrown when owner tries to set the fee for a stablecoin too high
    error FeeTooHigh();

    /// @dev Thrown when the msg.sender would receive 0 Superstate tokens out for their call to subscribe
    error ZeroSuperstateTokensOut();

    function allowList() external view returns (AllowList);

    /**
     * @notice Returns the domain separator used in the encoding of the
     * signature for permit
     * @return bytes32 The domain separator
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice The next expected nonce for an address, for validating authorizations via signature
    function nonces(address toFind) external view returns (uint256);

    /**
     * @notice Check permissions of an address for transferring / encumbering
     * @param addr Address to check permissions for
     * @return bool True if the address has sufficient permission, false otherwise
     */
    function hasSufficientPermissions(address addr) external view returns (bool);

    /**
     * @notice Invokes the {Pausable-_pause} internal function
     * @dev Can only be called by the admin
     */
    function pause() external;

    /**
     * @notice Invokes the {Pausable-_unpause} internal function
     * @dev Can only be called by the admin
     */
    function unpause() external;

    /**
     * @return bool True if the accounting is currently paused, false otherwise
     */
    function accountingPaused() external view returns (bool);

    /**
     * @notice Pauses mint and burn
     * @dev Can only be called by the admin
     */
    function accountingPause() external;

    /**
     * @notice Unpauses mint and burn
     * @dev Can only be called by the admin
     */
    function accountingUnpause() external;

    /**
     * @notice Increases the amount of tokens that the caller has encumbered to
     * `taker` by `amount`
     * @param taker Address to increase encumbrance to
     * @param amount Amount of tokens to increase the encumbrance by
     */
    function encumber(address taker, uint256 amount) external;

    /**
     * @notice Increases the amount of tokens that `owner` has encumbered to
     * `taker` by `amount`.
     * @dev Spends the caller's `allowance`
     * @param owner Address to increase encumbrance from
     * @param taker Address to increase encumbrance to
     * @param amount Amount of tokens to increase the encumbrance to `taker` by
     */
    function encumberFrom(address owner, address taker, uint256 amount) external;

    /**
     * @notice Reduces amount of tokens encumbered from `owner` to caller by
     * `amount`
     * @dev Reverts if `amount` is greater than `owner`'s current encumbrance to caller
     * @param owner Address to decrease encumbrance from
     * @param amount Amount of tokens to decrease the encumbrance by
     */
    function release(address owner, uint256 amount) external;

    /**
     * @notice Sets approval amount for a spender via signature from signatory
     * @param owner The address that signed the signature
     * @param spender The address to authorize (or rescind authorization from)
     * @param value Amount that `owner` is approving for `spender`
     * @param deadline Expiration time for the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    /**
     * @notice Mint new tokens to a recipient
     * @dev Only callable by the admin
     * @param dst Recipient of the minted tokens
     * @param amount Amount of tokens to mint
     */
    function mint(address dst, uint256 amount) external;

    /**
     * @notice Mint new tokens to many recipients
     * @dev Only callable by the admin
     * @param dsts Recipients of the minted tokens
     * @param amounts Amounts of tokens to mint
     */
    function bulkMint(address[] calldata dsts, uint256[] calldata amounts) external;

    /**
     * @notice Burn tokens from a given source address
     * @dev Only callable by the admin
     * @param src Source address from which tokens will be burned
     * @param amount Amount of tokens to burn
     */
    function burn(address src, uint256 amount) external;

    /**
     * @notice Burn tokens from the caller's address
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external;

    /**
     * @notice Initialize the contract
     * @param _name The token name
     * @param _symbol The token symbol
     */
    function initialize(string calldata _name, string calldata _symbol) external;
}
