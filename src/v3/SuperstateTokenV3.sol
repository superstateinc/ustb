// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import {ISuperstateTokenV3} from "src/interfaces/ISuperstateTokenV3.sol";
import {IERC7246} from "src/interfaces/IERC7246.sol";
import {IAllowList} from "src/interfaces/allowlist/IAllowList.sol";
import {IAllowListV2} from "src/interfaces/allowlist/IAllowListV2.sol";
import {AllowList} from "src/allowlist/AllowList.sol";

import {SuperstateOracle} from "onchain-redemptions/src/oracle/SuperstateOracle.sol";
import {AggregatorV3Interface} from
    "lib/onchain-redemptions/lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title SuperstateToken
 * @notice A Pausable ERC7246 token contract that interacts with the AllowList contract to check if transfers are allowed
 * @author Superstate
 */
contract SuperstateTokenV3 is ISuperstateTokenV3, ERC20Upgradeable, PausableUpgradeable, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @dev This empty reserved space is put in place to allow future versions to inherit from new contracts
     * without impacting the fields within `SuperstateToken`.
     */
    uint256[500] private __inheritanceGap;

    /// @notice The major version of this contract
    string public constant VERSION = "3";

    /// @dev The EIP-712 typehash for authorization via permit
    bytes32 internal constant AUTHORIZATION_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice Admin address with exclusive privileges for minting and burning
    /// @notice As of v2, this field is no longer used due to implementing Ownable2Step. The field is kept here to properly implement the transfer of ownership and will be removed in subsequent contract versions.
    address public immutable _deprecatedAdmin;

    /// @notice Address of the AllowList contract which determines permissions for transfers
    /// @notice As of v3, this field is
    IAllowList public immutable _deprecatedAllowList;

    /// @notice The next expected nonce for an address, for validating authorizations via signature
    mapping(address => uint256) public nonces;

    /// @notice Amount of an address's token balance that is encumbered
    mapping(address => uint256) public encumberedBalanceOf;

    /// @notice Amount encumbered from owner to taker (owner => taker => balance)
    mapping(address => mapping(address => uint256)) public encumbrances;

    /// @notice If all minting and burning operations are paused
    bool public accountingPaused;

    /// @notice Number of decimals used for the user representation of the token
    uint8 private constant DECIMALS = 6;

    /// @notice Base 10000 for 0.01% precision
    uint256 public constant FEE_DENOMINATOR = 10_000;

    /// @notice Precision of SUPERSTATE_TOKEN
    uint256 public constant SUPERSTATE_TOKEN_PRECISION = 10 ** DECIMALS;

    /// @notice Lowest acceptable chainlink oracle price
    uint256 public immutable MINIMUM_ACCEPTABLE_PRICE;

    /// @notice Value, in seconds, that determines if chainlink data is too old
    uint256 public maximumOracleDelay;

    /// @notice The address of the oracle used to calculate the Net Asset Value per Share
    address public superstateOracle;

    /// @notice Mapping from a stablecoin's address to its configuration
    mapping(address stablecoin => StablecoinConfig) public supportedStablecoins;

    /// @notice Address of the AllowList contract which determines permissions for transfers
    IAllowListV2 public allowListV2;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new fields without impacting
     * any contracts that inherit `SuperstateToken`
     */
    uint256[97] private __additionalFieldsGap;

    /**
     * @notice Construct a new ERC20 token instance with the given admin and AllowList
     * @dev Disables initialization on the implementation contract
     */
    constructor() {
        // SUPERSTATE_TOKEN starts at $10.000000, Chainlink oracle with 6 decimals would represent as 10_000_000.
        // This math will give us 7_000_000 or $7.000000.
        MINIMUM_ACCEPTABLE_PRICE = 7 * (10 ** uint256(DECIMALS));

        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param _name The token name
     * @param _symbol The token symbol
     */
    function initialize(string calldata _name, string calldata _symbol) public initializer {
        __ERC20_init(_name, _symbol);
        __Pausable_init();
    }

    /**
     * @notice Initialize version 2 of the contract.
     * @notice If creating an entirely new contract, the original `initialize` method still needs to be called.
     */
    function initializeV2() public reinitializer(2) {
        // Last usage of `_deprecatedAdmin` variable here.
        // After this call, owner() is the source of truth for authorization.
        if (msg.sender != _deprecatedAdmin) revert Unauthorized();
        __Ownable2Step_init();
    }

    /**
     * @notice Initialize version 3 of the contract
     * @notice If creating an entirely new contract, the original `initialize` method still needs to be called.
     */
    function initializeV3(AllowList _allowList) public reinitializer(3) {
        _checkOwner();

        allowListV2 = _allowList;
    }

    function _requireNotAccountingPaused() internal view {
        if (accountingPaused) revert AccountingIsPaused();
    }

    function _requireOnchainSubscriptionsEnabled() internal view {
        if (superstateOracle == address(0) || maximumOracleDelay == 0) revert OnchainSubscriptionsDisabled();
    }

    /**
     * @notice Invokes the {Pausable-_pause} internal function
     * @dev Can only be called by the admin
     */
    function pause() external {
        _checkOwner();
        _requireNotPaused();

        _pause();
    }

    /**
     * @notice Invokes the {Pausable-_unpause} internal function
     * @dev Can only be called by the admin
     */
    function unpause() external {
        _checkOwner();
        _requirePaused();

        _unpause();
    }

    /**
     * @notice Pauses mint and burn
     * @dev Can only be called by the admin
     */
    function accountingPause() external {
        _checkOwner();
        _requireNotAccountingPaused();

        accountingPaused = true;
        emit AccountingPaused(msg.sender);
    }

    /**
     * @notice Unpauses mint and burn
     * @dev Can only be called by the admin
     */
    function accountingUnpause() external {
        _checkOwner();
        if (!accountingPaused) revert AccountingIsNotPaused();

        accountingPaused = false;
        emit AccountingUnpaused(msg.sender);
    }

    function renounceOwnership() public virtual override onlyOwner {
        revert RenounceOwnershipDisabled();
    }

    /**
     * @notice Number of decimals used for the user representation of the token
     */
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @notice Amount of an address's token balance that is not encumbered
     * @param owner Address to check the available balance of
     * @return uint256 Unencumbered balance
     */
    function availableBalanceOf(address owner) public view returns (uint256) {
        return balanceOf(owner) - encumberedBalanceOf[owner];
    }

    /**
     * @notice Moves `amount` tokens from the caller's account to `dst`
     * @dev Confirms the available balance of the caller is sufficient to cover
     * transfer
     * @dev Includes extra functionality to burn tokens if `dst` is the token address, namely its TransparentUpgradeableProxy
     * @param dst Address to transfer tokens to
     * @param amount Amount of token to transfer
     * @return bool Whether the operation was successful
     */
    function transfer(address dst, uint256 amount)
        public
        override(IERC20Upgradeable, ERC20Upgradeable)
        returns (bool)
    {
        // check but dont spend encumbrance
        if (availableBalanceOf(msg.sender) < amount) revert InsufficientAvailableBalance();
        if (!hasSufficientPermissions(msg.sender)) revert InsufficientPermissions();

        if (dst == address(this)) {
            _requireNotAccountingPaused();
            _burn(msg.sender, amount);
            emit Burn(msg.sender, msg.sender, amount);
        } else {
            _requireNotPaused();
            if (!hasSufficientPermissions(dst)) revert InsufficientPermissions();
            _transfer(msg.sender, dst, amount);
        }

        return true;
    }

    /**
     * @notice Moves `amount` tokens from `src` to `dst` using the encumbrance
     * and allowance of the caller
     * @dev Spends the caller's encumbrance from `src` first, then their
     * allowance from `src` (if necessary)
     * @param src Address to transfer tokens from
     * @param dst Address to transfer tokens to
     * @param amount Amount of token to transfer
     * @return bool Whether the operation was successful
     */
    function transferFrom(address src, address dst, uint256 amount)
        public
        override(IERC20Upgradeable, ERC20Upgradeable)
        returns (bool)
    {
        uint256 encumberedToTaker = encumbrances[src][msg.sender];
        // check src permissions if amount encumbered is less than amount being transferred
        if (encumberedToTaker < amount && !hasSufficientPermissions(src)) {
            revert InsufficientPermissions();
        }

        if (amount > encumberedToTaker) {
            uint256 excessAmount;
            unchecked {
                excessAmount = amount - encumberedToTaker;
            }
            // Ensure that `src` has enough available balance (funds not encumbered to others)
            // to cover the excess amount
            if (availableBalanceOf(src) < excessAmount) revert InsufficientAvailableBalance();

            // Exceeds Encumbrance, so spend all of it
            if (encumberedToTaker > 0) {
                _releaseEncumbrance(src, msg.sender, encumberedToTaker);
            }

            _spendAllowance(src, msg.sender, excessAmount);
        } else {
            _releaseEncumbrance(src, msg.sender, amount);
        }

        if (dst == address(this)) {
            _requireNotAccountingPaused();
            _burn(src, amount);
            emit Burn(msg.sender, src, amount);
        } else {
            _requireNotPaused();
            if (!hasSufficientPermissions(dst)) revert InsufficientPermissions();
            _transfer(src, dst, amount);
        }

        return true;
    }

    /**
     * @notice Increases the amount of tokens that the caller has encumbered to
     * `taker` by `amount`
     * @param taker Address to increase encumbrance to
     * @param amount Amount of tokens to increase the encumbrance by
     */
    function encumber(address taker, uint256 amount) external whenNotPaused {
        _encumber(msg.sender, taker, amount);
    }

    /**
     * @notice Increases the amount of tokens that `owner` has encumbered to
     * `taker` by `amount`.
     * @dev Spends the caller's `allowance`
     * @param owner Address to increase encumbrance from
     * @param taker Address to increase encumbrance to
     * @param amount Amount of tokens to increase the encumbrance to `taker` by
     */
    function encumberFrom(address owner, address taker, uint256 amount) external whenNotPaused {
        // spend caller's allowance
        _spendAllowance(owner, msg.sender, amount);
        _encumber(owner, taker, amount);
    }

    /**
     * @notice Reduces amount of tokens encumbered from `owner` to caller by
     * `amount`
     * @dev Reverts if `amount` is greater than `owner`'s current encumbrance to caller
     * @param owner Address to decrease encumbrance from
     * @param amount Amount of tokens to decrease the encumbrance by
     */
    function release(address owner, uint256 amount) external {
        _releaseEncumbrance(owner, msg.sender, amount);
    }

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
        external
    {
        if (block.timestamp > deadline) revert SignatureExpired();

        uint256 nonce = nonces[owner];
        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        if (isValidSignature(owner, digest, v, r, s)) {
            nonces[owner]++;
            _approve(owner, spender, value);
        }
    }

    /**
     * @notice Check permissions of an address for transferring / encumbering
     * @param addr Address to check permissions for
     * @return bool True if the address has sufficient permission, false otherwise
     */
    function hasSufficientPermissions(address addr) public view virtual returns (bool) {
        return allowListV2.isAddressAllowedForFund(addr, symbol());
    }

    function allowList() external pure returns (IAllowList) {
        revert DeprecatedAllowList();
    }

    function _mintLogic(address dst, uint256 amount) internal {
        if (!hasSufficientPermissions(dst)) revert InsufficientPermissions();

        _mint(dst, amount);
        emit Mint(msg.sender, dst, amount);
    }

    /**
     * @notice Mint new tokens to a recipient
     * @dev Only callable by the admin
     * @param dst Recipient of the minted tokens
     * @param amount Amount of tokens to mint
     */
    function mint(address dst, uint256 amount) external {
        _checkOwner();
        _requireNotAccountingPaused();

        _mintLogic({dst: dst, amount: amount});
    }

    /**
     * @notice Mint new tokens to many recipients
     * @dev Only callable by the admin
     * @param dsts Recipients of the minted tokens
     * @param amounts Amounts of tokens to mint
     */
    function bulkMint(address[] calldata dsts, uint256[] calldata amounts) external {
        _checkOwner();
        _requireNotAccountingPaused();
        if (dsts.length != amounts.length || dsts.length == 0) revert InvalidArgumentLengths();

        uint256 length = dsts.length;

        for (uint256 i = 0; i < length; ++i) {
            _mintLogic({dst: dsts[i], amount: amounts[i]});
        }
    }

    /**
     * @notice Burn tokens from a given source address
     * @dev Only callable by the admin
     * @param src Source address from which tokens will be burned
     * @param amount Amount of tokens to burn
     */
    function burn(address src, uint256 amount) external {
        _checkOwner();
        _requireNotAccountingPaused();
        if (availableBalanceOf(src) < amount) revert InsufficientAvailableBalance();

        _burn(src, amount);
        emit Burn(msg.sender, src, amount);
    }

    /**
     * @notice Burn tokens from the caller's address
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external {
        _requireNotAccountingPaused();
        if (availableBalanceOf(msg.sender) < amount) revert InsufficientAvailableBalance();
        if (!hasSufficientPermissions(msg.sender)) revert InsufficientPermissions();

        _burn(msg.sender, amount);
        emit Burn(msg.sender, msg.sender, amount);
    }

    /**
     * @notice The ```setOracle``` function sets the address of the AggregatorV3Interface to be used to price the SuperstateToken
     * @dev Requires msg.sender to be the owner address
     * @param _newOracle The address of the oracle contract to update to
     */
    function setOracle(address _newOracle) external {
        _checkOwner();

        if (_newOracle == superstateOracle) revert BadArgs();
        emit SetOracle({oldOracle: superstateOracle, newOracle: _newOracle});
        superstateOracle = _newOracle;
    }

    // Oracle integration inspired by: https://github.com/FraxFinance/frax-oracles/blob/bd56532a3c33da95faed904a5810313deab5f13c/src/abstracts/ChainlinkOracleWithMaxDelay.sol
    function _setMaximumOracleDelay(uint256 _newMaxOracleDelay) internal {
        if (maximumOracleDelay == _newMaxOracleDelay) revert BadArgs();
        emit SetMaximumOracleDelay({oldMaxOracleDelay: maximumOracleDelay, newMaxOracleDelay: _newMaxOracleDelay});
        maximumOracleDelay = _newMaxOracleDelay;
    }
    /**
     * @notice The ```setMaximumOracleDelay``` function sets the max oracle delay to determine if Chainlink data is stale
     * @dev Requires msg.sender to be the owner address
     * @param _newMaxOracleDelay The new max oracle delay
     */

    function setMaximumOracleDelay(uint256 _newMaxOracleDelay) external {
        _checkOwner();
        _setMaximumOracleDelay(_newMaxOracleDelay);
    }

    /**
     * @notice The ```updateStablecoinConfig``` function sets the configuration fields for accepted stablecoins for onchain subscriptions
     * @dev Requires msg.sender to be the owner address
     * @param stablecoin The address of the stablecoin
     * @param newSweepDestination The new address to sweep stablecoin subscriptions to
     * @param newFee The new fee in basis points to charge for subscriptions in ```stablecoin```
     */
    function setStablecoinConfig(address stablecoin, address newSweepDestination, uint96 newFee) external {
        if (newFee > 10) revert FeeTooHigh(); // Max 0.1% fee
        _checkOwner();

        StablecoinConfig memory oldConfig = supportedStablecoins[stablecoin];
        if (newSweepDestination == oldConfig.sweepDestination && newFee == oldConfig.fee) revert BadArgs();

        supportedStablecoins[stablecoin] = StablecoinConfig({sweepDestination: newSweepDestination, fee: newFee});

        emit SetStablecoinConfig({
            stablecoin: stablecoin,
            oldSweepDestination: oldConfig.sweepDestination,
            newSweepDestination: newSweepDestination,
            oldFee: oldConfig.fee,
            newFee: newFee
        });
    }

    function _getChainlinkPrice() internal view returns (bool _isBadData, uint256 _updatedAt, uint256 _price) {
        _requireOnchainSubscriptionsEnabled();

        (, int256 _answer,, uint256 _chainlinkUpdatedAt,) = AggregatorV3Interface(superstateOracle).latestRoundData();

        // If data is stale or below first price, set bad data to true and return
        // 1_000_000_000 is $10.000000 in the oracle format, that was our starting NAV per Share price for SUPERSTATE_TOKEN
        // The oracle should never return a price much lower than this
        _isBadData =
            _answer < int256(MINIMUM_ACCEPTABLE_PRICE) || ((block.timestamp - _chainlinkUpdatedAt) > maximumOracleDelay);
        _updatedAt = _chainlinkUpdatedAt;
        _price = uint256(_answer);
    }

    /**
     * @notice The ```getChainlinkPrice``` function returns the chainlink price and the timestamp of the last update
     * @return _isBadData True if the data is stale or negative
     * @return _updatedAt The timestamp of the last update
     * @return _price The price
     */
    function getChainlinkPrice() external view returns (bool _isBadData, uint256 _updatedAt, uint256 _price) {
        return _getChainlinkPrice();
    }

    function calculateFee(uint256 amount, uint256 subscriptionFee) public pure returns (uint256) {
        return (amount * subscriptionFee) / FEE_DENOMINATOR;
    }

    /**
     * @notice The ```calculateSuperstateTokenOut``` function calculates the total amount of Superstate tokens you'll receive for the inAmount of stablecoin. Treats all stablecoins as if they are always worth a dollar.
     * @param inAmount The amount of the stablecoin in
     * @param stablecoin The address of the stablecoin to calculate with
     * @return superstateTokenOutAmount The amount of Superstate tokens received for inAmount of stablecoin
     * @return stablecoinInAmountAfterFee The amount of the stablecoin in after any fees
     * @return feeOnStablecoinInAmount The amount of the stablecoin taken in fees
     */
    function calculateSuperstateTokenOut(uint256 inAmount, address stablecoin)
        public
        view
        returns (uint256 superstateTokenOutAmount, uint256 stablecoinInAmountAfterFee, uint256 feeOnStablecoinInAmount)
    {
        StablecoinConfig memory config = supportedStablecoins[stablecoin];
        if (config.sweepDestination == address(0)) revert StablecoinNotSupported();

        feeOnStablecoinInAmount = calculateFee({amount: inAmount, subscriptionFee: config.fee});
        stablecoinInAmountAfterFee = inAmount - feeOnStablecoinInAmount;

        (bool isBadData,, uint256 usdPerSuperstateTokenChainlinkRaw) = _getChainlinkPrice();
        if (isBadData) revert BadChainlinkData();

        uint256 stablecoinDecimals = IERC20Metadata(stablecoin).decimals();
        uint256 stablecoinPrecision = 10 ** stablecoinDecimals;
        uint256 chainlinkFeedPrecision = 10 ** AggregatorV3Interface(superstateOracle).decimals();

        // converts from a USD amount to a SUPERSTATE_TOKEN amount
        superstateTokenOutAmount = (stablecoinInAmountAfterFee * chainlinkFeedPrecision * SUPERSTATE_TOKEN_PRECISION)
            / (usdPerSuperstateTokenChainlinkRaw * stablecoinPrecision);
    }

    /**
     * @notice The ```subscribe``` function takes in stablecoins and mints SuperstateToken in the proper amount for the msg.sender depending on the current Net Asset Value per Share.
     * @param inAmount The amount of the stablecoin in
     * @param stablecoin The address of the stablecoin to calculate with
     */
    function subscribe(uint256 inAmount, address stablecoin) external {
        if (inAmount == 0) revert BadArgs();
        _requireNotPaused();
        _requireNotAccountingPaused();

        (uint256 superstateTokenOutAmount, uint256 stablecoinInAmountAfterFee,) =
            calculateSuperstateTokenOut({inAmount: inAmount, stablecoin: stablecoin});

        if (superstateTokenOutAmount == 0) revert ZeroSuperstateTokensOut();

        IERC20(stablecoin).safeTransferFrom({
            from: msg.sender,
            to: supportedStablecoins[stablecoin].sweepDestination,
            value: inAmount
        });
        _mintLogic({dst: msg.sender, amount: superstateTokenOutAmount});

        emit Subscribe({
            subscriber: msg.sender,
            stablecoin: stablecoin,
            stablecoinInAmount: inAmount,
            stablecoinInAmountAfterFee: stablecoinInAmountAfterFee,
            superstateTokenOutAmount: superstateTokenOutAmount
        });
    }

    /**
     * @dev Increase `owner`'s encumbrance to `taker` by `amount`
     */
    function _encumber(address owner, address taker, uint256 amount) internal {
        if (owner == taker) revert SelfEncumberNotAllowed();
        if (availableBalanceOf(owner) < amount) revert InsufficientAvailableBalance();
        if (!hasSufficientPermissions(owner)) revert InsufficientPermissions();

        encumbrances[owner][taker] += amount;
        encumberedBalanceOf[owner] += amount;
        emit Encumber(owner, taker, amount);
    }

    /**
     * @dev Reduce `owner`'s encumbrance to `taker` by `amount`
     */
    function _releaseEncumbrance(address owner, address taker, uint256 amount) internal {
        if (encumbrances[owner][taker] < amount) revert InsufficientEncumbrance();

        encumbrances[owner][taker] -= amount;
        encumberedBalanceOf[owner] -= amount;
        emit Release(owner, taker, amount);
    }

    /**
     * @notice Returns the domain separator used in the encoding of the
     * signature for permit
     * @return bytes32 The domain separator
     */
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256(bytes(name())), keccak256(bytes(VERSION)), block.chainid, address(this)
            )
        );
    }

    /**
     * @notice Checks if a signature is valid
     * @param signer The address that signed the signature
     * @param digest The hashed message that is signed
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     * @return bool Whether the signature is valid
     */
    function isValidSignature(address signer, bytes32 digest, uint8 v, bytes32 r, bytes32 s)
        internal
        pure
        returns (bool)
    {
        (address recoveredSigner, ECDSA.RecoverError recoverError,) = ECDSA.tryRecover(digest, v, r, s);

        if (recoverError == ECDSA.RecoverError.InvalidSignatureS) revert InvalidSignatureS();
        if (recoverError == ECDSA.RecoverError.InvalidSignature) revert BadSignatory();
        if (recoveredSigner != signer) revert BadSignatory();

        return true;
    }
}
