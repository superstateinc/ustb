// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
        require(msg.sender == permissionAdmin, "Not authorized");
        permissions[addr].allowed = allowed;

        emit SetAllowed(addr, allowed);
    }

    function setForbidden(address addr, bool forbidden) public {
        require(msg.sender == permissionAdmin, "Not authorized");
        permissions[addr].forbidden = forbidden;

        emit SetForbidden(addr, forbidden);
    }

    // TODO
    // function setAllowedBySig(address addr, bool allowed, bytes32 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) public {
    // }

    // TODO
    // function setForbiddenBySig(address addr, bool forbidden, bytes32 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) public {
    // }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), keccak256(bytes(VERSION)), block.chainid, address(this)));
    }

    // TODO
    // function checkNonce(uint256 nonce) internal view returns (bool) {
    // }

    // TODO
    // function markNonce(uint256 nonce) internal view returns (bool) {
    // }

}