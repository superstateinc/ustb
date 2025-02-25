// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {AllowList} from "src/allowlist/AllowList.sol";
import {IAllowListV2} from "src/interfaces/allowlist/IAllowListV2.sol";

interface ISuperstateToken is IERC20Upgradeable {
    // V1 remaining

    /// @dev Event emitted when tokens are minted
    event Mint(address indexed minter, address indexed to, uint256 amount);

    /// @dev Emitted when the accounting pause is triggered by `admin`.
    event AccountingPaused(address admin);

    /// @dev Emitted when the accounting pause is lifted by `admin`.
    event AccountingUnpaused(address admin);

    /// @dev Thrown when a request is not sent by the authorized admin
    error Unauthorized();

    /// @dev Thrown when an address does not have sufficient permissions, as dictated by the AllowList
    error InsufficientPermissions();

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

    /// @dev Thrown if array length arguments aren't equal
    error InvalidArgumentLengths();

    /**
     * @notice Returns the domain separator used in the encoding of the
     * signature for permit
     * @return bytes32 The domain separator
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice The next expected nonce for an address, for validating authorizations via signature
    function nonces(address toFind) external view returns (uint256);

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
     * @notice Initialize the contract
     * @param _name The token name
     * @param _symbol The token symbol
     */
    function initialize(string calldata _name, string calldata _symbol) external;

    // V2 remaining

    /// @dev Thrown if an attempt to call `renounceOwnership` is made
    error RenounceOwnershipDisabled();

    /**
     * @notice Initialize version 2 of the contract.
     * @notice If creating an entirely new contract, the original `initialize` method still needs to be called.
     */
    function initializeV2() external;

    // V3 remaining

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

    /// @dev Thrown when the msg.sender would receive 0 Superstate tokens out for their call to subscribe, or trying to bridge 0 tokens
    error ZeroSuperstateTokensOut();

    function allowListV2() external view returns (IAllowListV2);

    /**
     * @notice Initialize version 3 of the contract
     * @notice If creating an entirely new contract, the original `initialize` method still needs to be called.
     */
    function initializeV3(AllowList _allowList) external;

    // V4

    /// @dev Event emitted when the admin burns tokens
    event AdminBurn(address indexed burner, address indexed src, uint256 amount);

    /// @dev Event emitted when the user wants to bridge their tokens to another chain or book entry
    event Bridge(
        address caller,
        address indexed src,
        uint256 amount,
        address indexed ethDestinationAddress,
        string indexed otherDestinationAddress,
        uint256 chainId
    );

    /// @dev Event emitted when the users wants to redeem their shares with an offchain payout
    event OffchainRedeem(address indexed burner, address indexed src, uint256 amount);

    /// @dev Event emitted when the owner changes the redemption contract address
    event SetRedemptionContract(address oldRedemptionContract, address newRedemptionContract);

    /// @notice Emitted when a chain ID's support status is updated
    event SetChainIdSupport(uint256 indexed chainId, bool oldSupported, bool newSupported);

    /// @dev Thrown when bridge function arguments have two destinations
    error TwoDestinationsInvalid();

    /// @dev Thrown when bridge function chainId is set to 0 but onchain destination arguments are provided
    error OnchainDestinationSetForBridgeToBookEntry();

    /// @dev Thrown when bridge function chainId is not supported
    error BridgeChainIdDestinationNotSupported();

    /**
     * @notice Check permissions of an address for transferring
     * @param addr Address to check permissions for
     * @return bool True if the address has sufficient permission, false otherwise
     */
    function isAllowed(address addr) external view returns (bool);

    /**
     * @notice Burn tokens from a given source address
     * @dev Only callable by the admin
     * @param src Source address from which tokens will be burned
     * @param amount Amount of tokens to burn
     */
    function adminBurn(address src, uint256 amount) external;

    /**
     * @notice Burn tokens from the caller's address for offchain redemption
     * @param amount Amount of tokens to burn
     */
    function offchainRedeem(uint256 amount) external;

    /**
     * @notice Burn tokens from the caller's address to bridge to another chain
     * @dev If destination address on chainId isn't on allowlist, or chainID isn't supported, tokens wind up in book entry
     * @param amount Amount of tokens to burn
     * @param ethDestinationAddress ETH address to send to on another chain
     * @param otherDestinationAddress Non-EVM addresses to send to on another chain
     * @param chainId Numerical identifier of destination chain to send tokens to
     */
    function bridge(
        uint256 amount,
        address ethDestinationAddress,
        string calldata otherDestinationAddress,
        uint256 chainId
    ) external;

    /**
     * @notice Burn tokens from the caller's address to bridge to Superstate book entry
     * @param amount Amount of tokens to burn
     */
    function bridgeToBookEntry(uint256 amount) external;

    /**
     * @notice Sets redemption contract address
     * @dev Used for convenience for devs
     * @dev Set to address(0) if no such contract exists for the token
     * @param _newRedemptionContract New contract address
     */
    function setRedemptionContract(address _newRedemptionContract) external;

    /**
     * @notice Sets support status for a specific chain ID
     * @param _chainId The chain ID to update
     * @param _supported Whether the chain ID should be supported
     */
    function setChainIdSupport(uint256 _chainId, bool _supported) external;
}
