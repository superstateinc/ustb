// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";

/**
 * @title Permissionlist
 * @notice A contract that provides allowlist and forbidlist functionalities with nonce management
 * @author Compound
 *
 * TODO: Convert to OZ Transparent Upgradeable Proxy
 */
contract Permissionlist {
    /// @notice The name of this contract
    string public constant name = "Superstate Permissionlist Contract";

    /// @notice The major version of this contract
    string public constant VERSION = "1";

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev EIP-712 typehash for setting permissions for an address
    bytes32 internal constant SET_PERMISSION_TYPEHASH =
        keccak256("SetAllowed(address addr,Permission permission,uint256 expiry,bytes32 nonce)");

    // @dev Address of the administrator with permissions to update the allowlist
    address public permissionAdmin;

    /// @dev Mapping of addresses to their permissions
    struct Permission {
        bool allowed;
        bool forbidden;
    }

    /// @notice A record of permissions for each address determining if they are allowed or forbidden
    mapping(address => Permission) public permissions;

    /// @notice Tracking used nonces based on bucketing to ensure unique nonces are utilized
    mapping(uint256 => uint256) public knownNonces;

    /// @notice Tracking the last nonce for a given user account. Used to order transactions per user.
    mapping(address => uint256) public userNonces;

    /// @notice An event emitted when an address's permission status is changed
    event PermissionSet(address indexed addr, Permission permission);

    /**
     * @notice Construct a new Permissionlist instance
     * @param _permissionAdmin Address of the permission administrator
     */
    constructor(address _permissionAdmin) {
        permissionAdmin = _permissionAdmin;
    }

    /**
     * @notice Fetches the permissions for a given address
     * @param receiver The address whose permissions are to be fetched
     * @return Permission The permissions of the address
     */
    function getPermission(address receiver) public view returns (Permission memory) {
        return permissions[receiver];
    }

    /**
     * @notice Sets permissions for a given address
     * @param addr The address to be updated
     * @param permission The permission status to set
     */
    function setPermission(address addr, Permission memory permission) public {
        require(msg.sender == permissionAdmin, "Not authorized to set permissions");
        permissions[addr] = permission;

        emit PermissionSet(addr, permission);
    }

    /**
     * @notice Sets permissions for a given address using an off-chain signature
     * @param addr The address to be updated
     * @param permission The permission status to set
     * @param nonce Unique value to prevent replay attacks
     * @param expiry Timestamp after which the signature is invalid
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function setPermissionBySig(
        address addr,
        Permission memory permission,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        require(block.timestamp <= expiry, "Signature expired");
        require(userNonces[addr] <= nonce, "Nonce already used");

        uint256 bucketValue = knownNonces[nonce / 256];
        require(!nonceUsed(nonce, bucketValue), "Nonce already used");

        bytes32 structHash = keccak256(abi.encode(SET_PERMISSION_TYPEHASH, addr, permission, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        require(isValidSignature(permissionAdmin, digest, v, r, s), "Invalid signature");

        uint256 newBucketValue = markNonce(nonce, bucketValue);
        knownNonces[nonce / 256] = newBucketValue;
        userNonces[addr] = nonce + 1;
        permissions[addr] = permission;
        emit PermissionSet(addr, permission);
    }

    /**
     * @notice Returns the domain separator used in the encoding of the
     * signature for permit
     * @return bytes32 The domain separator
     */
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), keccak256(bytes(VERSION)), block.chainid, address(this))
        );
    }

    /**
     * @notice Checks if a nonce has been used
     * @param nonce The nonce to check
     * @param bucketValue The value of the bucket `nonce` is located it. Each bucket groups nonces in chunks of 256.
     * @return bool True if nonce has been used, false otherwise
     */
    function nonceUsed(uint256 nonce, uint256 bucketValue) public pure returns (bool) {
        uint256 position = nonce % 256;
        uint256 mask = 1 << position;
        return (bucketValue & mask) != 0;
    }

    /**
     * @dev Marks a nonce as used. This function ensures that a nonce is not reused, preventing replay attacks. Can only be called internally by this contract
     * @param nonce The nonce to mark as used
     * @param bucketValue The value of the bucket `nonce` is located it. Each bucket groups nonces in chunks of 256.
     * @return uint256 The new (bitwise-or)'ed value to set for the bucket
     */
    function markNonce(uint256 nonce, uint256 bucketValue) internal view returns (uint256) {
        require(msg.sender == address(this), "Not authorized to set nonces");
        uint256 position = nonce % 256;
        uint256 mask = 1 << position;
        return bucketValue ^ mask;
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
        require(recoverError != ECDSA.RecoverError.InvalidSignatureS, "Invalid value s");
        require(recoverError != ECDSA.RecoverError.InvalidSignature, "Bad signatory");
        require(recoveredSigner == signer, "Bad signatory");
        return true;
    }
}
