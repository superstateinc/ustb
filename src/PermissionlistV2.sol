// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

import "openzeppelin/security/PausableUpgradeable.sol";
import "openzeppelin/access/OwnableUpgradeable.sol";
import "openzeppelin/proxy/utils/Initializable.sol";

/**
 * @title PermissionlistV2
 * @notice A contract that provides allowlist and other permission functionalities
 * @author Compound
 */
contract PermissionlistV2 is Initializable, PausableUpgradeable, OwnableUpgradeable {
    /// @dev Address of the administrator with permissions to update the allowlist
    address public permissionAdmin;

    /// @dev Mapping of addresses to their permissions
    struct Permission {
        bool allowed;
        bool isKyc;
        bool isAccredited;
    }

    /// @notice A record of permissions for each address determining if they are allowed
    mapping(address => Permission) public permissions;

    /// @notice An event emitted when an address's permission status is changed
    event PermissionSet(address indexed addr, Permission permission);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize a new Permissionlist instance
     * @param _permissionAdmin Address of the permission administrator
     */
    function initialize(address _permissionAdmin) public initializer {
        __Pausable_init();
        __Ownable_init();
        permissionAdmin = _permissionAdmin;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
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
    function setPermission(address addr, Permission memory permission) external {
        require(msg.sender == permissionAdmin, "Not authorized to set permissions");
        permissions[addr] = permission;

        emit PermissionSet(addr, permission);
    }
}
