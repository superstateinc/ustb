// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { ERC20Upgradeable } from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { PausableUpgradeable } from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import { ECDSA } from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";

import { IERC7246 } from "src/interfaces/IERC7246.sol";
import { PermissionList } from "src/PermissionList.sol";

/**
 * @title SUPTB
 * @notice A Pausable ERC7246 token contract that interacts with the PermissionList contract to check if transfers are allowed
 * @author Compound
 */
contract SUPTB is ERC20Upgradeable, IERC7246, PausableUpgradeable {
    /// @notice The major version of this contract
    string public constant VERSION = "1";

    /// @dev The EIP-712 typehash for authorization via permit
    bytes32 internal constant AUTHORIZATION_TYPEHASH =
        keccak256("Authorization(address owner,address spender,uint256 amount,uint256 nonce,uint256 expiry)");

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice Admin address with exclusive privileges for minting and burning
    address public immutable admin;

    /// @notice Address of the PermissionList contract which determines permissions for transfers
    PermissionList public immutable permissionList;

    /// @notice The next expected nonce for an address, for validating authorizations via signature
    mapping(address => uint256) public nonces;

    /// @notice Amount of an address's token balance that is encumbered
    mapping(address => uint256) public encumberedBalanceOf;

    /// @notice Amount encumbered from owner to taker (owner => taker => balance)
    mapping(address => mapping(address => uint256)) public encumbrances;

    /// @notice Number of decimals used for the user representation of the token
    uint8 private constant DECIMALS = 6;

    /// @dev Event emitted when tokens are minted
    event Mint(address indexed minter, address indexed to, uint256 amount);

    /// @dev Event emitted when tokens are burned
    event Burn(address indexed burner, address indexed from, uint256 amount);

    /// @dev Thrown when a request is not sent by the authorized admin
    error Unauthorized();

    /// @dev Thrown when an address does not have sufficient permissions, as dicatated by the PermissionList
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

    /**
     * @notice Construct a new ERC20 token instance with the given admin and PermissionList
     * @param _admin The address designated as the admin with special privileges
     * @param _permissionList Address of the PermissionList contract to use for permission checking
     * @dev Disables initialization on the implementation contract
     */
    constructor(address _admin, PermissionList _permissionList) {
        admin = _admin;
        permissionList = _permissionList;

        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param _name The token name
     * @param _symbol The token symbol
     */
    function initialize(string calldata _name, string calldata _symbol) initializer public {
        __ERC20_init(_name, _symbol);
    }

    /**
     * @notice Invokes the {Pausable-_pause} internal function
     * @dev Can only be called by the admin
     */
    function pause() external {
        if (msg.sender != admin) revert Unauthorized();

        _pause();
    }

    /**
     * @notice Invokes the {Pausable-_unpause} internal function
     * @dev Can only be called by the admin
     */
    function unpause() external {
        if (msg.sender != admin) revert Unauthorized();

        _unpause();
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
     * @dev Includes extra functionality to burn tokens if `dst` is the zero address
     * @param dst Address to transfer tokens to
     * @param amount Amount of token to transfer
     * @return bool Whether the operation was successful
     */
    function transfer(address dst, uint256 amount) public override whenNotPaused returns (bool) {
        // check but dont spend encumbrance
        if (availableBalanceOf(msg.sender) < amount) revert InsufficientAvailableBalance();
        PermissionList.Permission memory senderPermissions = permissionList.getPermission(msg.sender);
        if (!senderPermissions.isAllowed) revert InsufficientPermissions();

        if (dst == address(0)) {
            _burn(msg.sender, amount);
            emit Burn(msg.sender, msg.sender, amount);
        } else {
            PermissionList.Permission memory dstPermissions = permissionList.getPermission(dst);
            if (!dstPermissions.isAllowed) revert InsufficientPermissions();
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
    function transferFrom(address src, address dst, uint256 amount) public override whenNotPaused returns (bool) {
        uint256 encumberedToTaker = encumbrances[src][msg.sender];
        // check src permissions if transferFrom doesn't use any encumbrances
        if (encumberedToTaker == 0 && !permissionList.getPermission(src).isAllowed) {
            revert InsufficientPermissions();
        }

        if (amount > encumberedToTaker) {
            uint256 excessAmount = amount - encumberedToTaker;

            // Exceeds Encumbrance, so spend all of it
            _releaseEncumbrance(src, msg.sender, encumberedToTaker);

            // Having spent all the tokens encumbered to the mover,
            // We are now moving only "available" tokens and must check
            // to not unfairly move tokens encumbered to others

            if (availableBalanceOf(src) < excessAmount) revert InsufficientAvailableBalance();

            _spendAllowance(src, msg.sender, excessAmount);
        } else {
            _releaseEncumbrance(src, msg.sender, amount);
        }

        if (dst == address(0)) {
            _burn(src, amount);
            emit Burn(msg.sender, src, amount);
        } else {
            PermissionList.Permission memory dstPermissions = permissionList.getPermission(dst);
            if (!dstPermissions.isAllowed) revert InsufficientPermissions();
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
    function release(address owner, uint256 amount) external whenNotPaused {
        _releaseEncumbrance(owner, msg.sender, amount);
    }

    /**
     * @notice Sets approval amount for a spender via signature from signatory
     * @param owner The address that signed the signature
     * @param spender The address to authorize (or rescind authorization from)
     * @param amount Amount that `owner` is approving for `spender`
     * @param expiry Expiration time for the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function permit(address owner, address spender, uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        external
    {
        if (block.timestamp >= expiry) revert SignatureExpired();

        uint256 nonce = nonces[owner];
        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, owner, spender, amount, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        if (isValidSignature(owner, digest, v, r, s)) {
            nonces[owner]++;
            _approve(owner, spender, amount);
        }
    }

    /**
     * @notice Check permissions of an address for transferring / encumbering
     * @param addr Address to check permissions for
     * @return bool True if the address has sufficient permission, false otherwise
     */
    function hasSufficientPermissions(address addr) public view returns (bool) {
        PermissionList.Permission memory permissions = permissionList.getPermission(addr);
        return permissions.isAllowed;
    }

    /**
     * @notice Mint new tokens to a recipient
     * @dev Only callable by the admin
     * @param dst Recipient of the minted tokens
     * @param amount Amount of tokens to mint
     */
    function mint(address dst, uint256 amount) external whenNotPaused {
        if (msg.sender != admin) revert Unauthorized();
        if (!permissionList.getPermission(dst).isAllowed) revert InsufficientPermissions();

        _mint(dst, amount);
        emit Mint(msg.sender, dst, amount);
    }

    /**
     * @notice Burn tokens from a given source address
     * @dev Only callable by the admin
     * @param src Source address from which tokens will be burned
     * @param amount Amount of tokens to burn
     */
    function burn(address src, uint256 amount) external whenNotPaused {
        if (msg.sender != admin) revert Unauthorized();
        if (availableBalanceOf(src) < amount) revert InsufficientAvailableBalance();

        _burn(src, amount);
        emit Burn(msg.sender, src, amount);
    }

    /**
     * @dev Increase `owner`'s encumbrance to `taker` by `amount`
     */
    function _encumber(address owner, address taker, uint256 amount) private {
        if (availableBalanceOf(owner) < amount) revert InsufficientAvailableBalance();
        PermissionList.Permission memory permissions = permissionList.getPermission(owner);
        if (!permissions.isAllowed) revert InsufficientPermissions();

        encumbrances[owner][taker] += amount;
        encumberedBalanceOf[owner] += amount;
        emit Encumber(owner, taker, amount);
    }

    /**
     * @dev Reduce `owner`'s encumbrance to `taker` by `amount`
     */
    function _releaseEncumbrance(address owner, address taker, uint256 amount) private {
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
