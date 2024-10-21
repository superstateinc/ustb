// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";

import {console} from "forge-std/console.sol";
import {IERC7246} from "src/interfaces/IERC7246.sol";
import {AllowList} from "src/AllowList.sol";

/**
 * @title SuperstateToken
 * @notice A Pausable ERC7246 token contract that interacts with the AllowList contract to check if transfers are allowed
 * @author Superstate
 */
abstract contract SuperstateTokenV2 is ERC20Upgradeable, IERC7246, PausableUpgradeable, Ownable2StepUpgradeable {
    /// @notice The major version of this contract
    string public constant VERSION = "2";

    /// @dev The EIP-712 typehash for authorization via permit
    bytes32 internal constant AUTHORIZATION_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice Admin address with exclusive privileges for minting and burning
    /// @notice As of v2, this field is no longer used due to implementing Ownable2Step. The field is kept here to keep the memory storage layout consistent.
    address public immutable admin;

    /// @notice Address of the AllowList contract which determines permissions for transfers
    AllowList public immutable allowList;

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

    /// @dev Event emitted when tokens are minted
    event Mint(address indexed minter, address indexed to, uint256 amount);

    /// @dev Event emitted when tokens are burned
    event Burn(address indexed burner, address indexed from, uint256 amount);

    /// @dev Emitted when the accounting pause is triggered by `admin`.
    event AccountingPaused(address admin);

    /// @dev Emitted when the accounting pause is lifted by `admin`.
    event AccountingUnpaused(address admin);

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

    /**
     * @notice Construct a new ERC20 token instance with the given admin and AllowList
     * @param _allowList Address of the AllowList contract to use for permission checking
     * @dev Disables initialization on the implementation contract
     */
    constructor(address _existingAdmin, AllowList _allowList) {
        admin = _existingAdmin;
        allowList = _allowList;
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

    // initialize for v2
    function initializeV2() public reinitializer(2) {
        // Last usage of `admin` variable here.
        // After this call, owner() is the source of truth for authorization.
        if (msg.sender != admin) revert Unauthorized();
        __Ownable2Step_init();
    }

    function _requireNotAccountingPaused() internal view {
        if (accountingPaused) revert AccountingIsPaused();
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
    function transfer(address dst, uint256 amount) public override returns (bool) {
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
    function transferFrom(address src, address dst, uint256 amount) public override returns (bool) {
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
    function hasSufficientPermissions(address addr) public view virtual returns (bool);

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
        (address recoveredSigner, ECDSA.RecoverError recoverError) = ECDSA.tryRecover(digest, v, r, s);

        if (recoverError == ECDSA.RecoverError.InvalidSignatureS) revert InvalidSignatureS();
        if (recoverError == ECDSA.RecoverError.InvalidSignature) revert BadSignatory();
        if (recoveredSigner != signer) revert BadSignatory();

        return true;
    }
}
