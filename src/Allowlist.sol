// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { ECDSA } from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";

// TODO: Convert to OZ TUP
contract Allowlist {

    bytes32 internal constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 internal constant SET_ALLOWED_TYPEHASH = keccak256("SetAllowed(address addr,bool allowed,uint256 expiry,bytes32 nonce)");
    
    bytes32 internal constant SET_FORBIDDEN_TYPEHASH = keccak256("SetForbidden(address addr,bool forbidden,uint256 expiry,bytes32 nonce)");

    string public constant name = "Superstate Allowlist Contract";
    
    string public constant VERSION = "1";

    address public permissionAdmin;

    struct Permission {
        bool allowed;
        bool forbidden;
    }

    mapping(address => Permission) public permissions;
    mapping(uint256 => uint256) public knownNonces;

    event SetAllowed(address indexed addr, bool allowed);
    event SetForbidden(address indexed addr, bool forbidden);

    constructor(address _permissionAdmin) {
        permissionAdmin = _permissionAdmin;
    }

    function getPermissions(address receiver) public view returns (Permission memory) {
        return permissions[receiver];
    }

    function setAllowed(address addr, bool allowed) public {
        require(msg.sender == permissionAdmin, "Not authorized to set allowed addresses");
        permissions[addr].allowed = allowed;

        emit SetAllowed(addr, allowed);
    }

    function setForbidden(address addr, bool forbidden) public {
        require(msg.sender == permissionAdmin, "Not authorized to set forbidden addresses");
        permissions[addr].forbidden = forbidden;

        emit SetForbidden(addr, forbidden);
    }

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

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), keccak256(bytes(VERSION)), block.chainid, address(this)));
    }

    function checkNonce(uint256 nonce) public view returns (bool) {
        uint256 bucket = knownNonces[nonce / 256];
        uint256 position = nonce % 256;
        uint256 mask = 1 << position;
        return (bucket & mask) != 0;
    }

    function markNonce(uint256 nonce) internal {
        require(msg.sender == address(this), "Not authorized to set nonces");
        uint256 bucket = knownNonces[nonce / 256];
        uint256 position = nonce % 256;
        uint256 mask = 1 << position;
        knownNonces[nonce / 256] = bucket ^ mask;
    }

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