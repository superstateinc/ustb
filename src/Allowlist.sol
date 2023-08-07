// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

import { ECDSA } from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";

/**
 * @title Allowlist
 * @notice A contract that provides allowlist functionalities with nonce management
 * @author Compound
 *
 * TODO: Convert to OZ Transparent Upgradeable Proxy
 */
contract Allowlist {
    /// @notice The name of this contract
    string public constant name = "Superstate Allowlist Contract";
    
    /// @notice The major version of this contract
    string public constant VERSION = "1";

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 internal constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev EIP-712 typehash for setting allowed addresses
    bytes32 internal constant SET_ALLOWED_TYPEHASH = keccak256("SetAllowed(address addr,bool allowed,uint256 expiry,bytes32 nonce)");
    
    /// @dev EIP-712 typehash for setting forbidden addresses
    bytes32 internal constant SET_FORBIDDEN_TYPEHASH = keccak256("SetForbidden(address addr,bool forbidden,uint256 expiry,bytes32 nonce)");

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

    /// @notice An event emitted when an address's allowed status is changed
    event SetAllowed(address indexed addr, bool allowed);
    /// @notice An event emitted when an address's forbidden status is changed
    event SetForbidden(address indexed addr, bool forbidden);

    /**
     * @notice Construct a new Allowlist instance
     * @param _permissionAdmin Address of the permission administrator
     **/
    constructor(address _permissionAdmin) {
        permissionAdmin = _permissionAdmin;
    }

    /**
     * @notice Fetches the permissions for a given address
     * @param receiver The address whose permissions are to be fetched
     * @return Permission The permissions of the address
     */
    function getPermissions(address receiver) public view returns (Permission memory) {
        return permissions[receiver];
    }

    /**
     * @notice Sets an address as allowed or not
     * @param addr The address to be updated
     * @param allowed The allowed status to set
     */
    function setAllowed(address addr, bool allowed) public {
        require(msg.sender == permissionAdmin, "Not authorized to set allowed addresses");
        permissions[addr].allowed = allowed;

        emit SetAllowed(addr, allowed);
    }

    /**
     * @notice Sets an address as forbidden or not
     * @param addr The address to be updated
     * @param forbidden The forbidden status to set
     */
    function setForbidden(address addr, bool forbidden) public {
        require(msg.sender == permissionAdmin, "Not authorized to set forbidden addresses");
        permissions[addr].forbidden = forbidden;

        emit SetForbidden(addr, forbidden);
    }

    /**
     * @notice Sets an address as allowed or not using an off-chain signature
     * @param addr The address to be updated
     * @param allowed The allowed status to set
     * @param nonce Unique value to prevent replay attacks
     * @param expiry Timestamp after which the signature is invalid
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function setAllowedBySig(address addr, bool allowed, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) public {
        require(block.timestamp <= expiry, "Signature expired");
        require(!checkNonce(nonce), "Nonce already used");

        bytes32 structHash = keccak256(abi.encode(SET_ALLOWED_TYPEHASH, addr, allowed, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        require(isValidSignature(permissionAdmin, digest, v, r, s), "Invalid signature");

        markNonce(nonce);
        permissions[addr].allowed = allowed;
        emit SetAllowed(addr, allowed);
    }


     /**
     * @notice Sets an address as forbidden or not using an off-chain signature
     * @param addr The address to be updated
     * @param forbidden The forbidden status to set
     * @param nonce Unique value to prevent replay attacks
     * @param expiry Timestamp after which the signature is invalid
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function setForbiddenBySig(address addr, bool forbidden, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) public {
        require(block.timestamp <= expiry, "Signature expired");
        require(!checkNonce(nonce), "Nonce already used");

        bytes32 structHash = keccak256(abi.encode(SET_FORBIDDEN_TYPEHASH, addr, forbidden, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        require(isValidSignature(permissionAdmin, digest, v, r, s), "Invalid signature");

        markNonce(nonce);
        permissions[addr].forbidden = forbidden;
        emit SetForbidden(addr, forbidden);
    }

    /**
     * @notice Returns the domain separator used in the encoding of the
     * signature for permit
     * @return bytes32 The domain separator
     */
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), keccak256(bytes(VERSION)), block.chainid, address(this)));
    }

    /**
     * @notice Checks if a nonce has been used
     * @param nonce The nonce to check
     * @return bool True if nonce has been used, false otherwise
     */
    function checkNonce(uint256 nonce) public view returns (bool) {
        uint256 bucket = knownNonces[nonce / 256];
        uint256 position = nonce % 256;
        uint256 mask = 1 << position;
        return (bucket & mask) != 0;
    }

    /**
     * @dev Marks a nonce as used. This function ensures that a nonce is not reused, preventing replay attacks. Can only be called internally by this contract
     * @param nonce The nonce to mark as used
     */
    function markNonce(uint256 nonce) internal {
        require(msg.sender == address(this), "Not authorized to set nonces");
        uint256 bucket = knownNonces[nonce / 256];
        uint256 position = nonce % 256;
        uint256 mask = 1 << position;
        knownNonces[nonce / 256] = bucket ^ mask;
    }

    /**
     * @notice Generates the next available nonce
     * @dev Iterates through nonce buckets to find the next unused nonce
     * @return uint256 The next available nonce
     */
    function getNextNonce() public view returns (uint256) {
        uint256 bucketNumber = 0;
        uint256 maxBuckets = 100000;


        while (knownNonces[bucketNumber] == type(uint256).max && bucketNumber < maxBuckets) {
            bucketNumber++;
        }

        if (bucketNumber == maxBuckets) {
            revert("All nonces in the range are used up");
        }

        uint256 bucketValue = knownNonces[bucketNumber];
        uint256 position = 0;

        while (position < 256 && (bucketValue & (1 << position)) != 0) {
            position++;
        }

        return (bucketNumber * 256) + position;
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
    function isValidSignature(
        address signer,
        bytes32 digest,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (bool) {
        (address recoveredSigner, ECDSA.RecoverError recoverError) = ECDSA.tryRecover(digest, v, r, s);
        require(recoverError != ECDSA.RecoverError.InvalidSignatureS, "Invalid value s");
        require(recoverError != ECDSA.RecoverError.InvalidSignature, "Bad signatory");
        require(recoveredSigner == signer, "Bad signatory");
        return true;
    }
 
}