// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title PermissionList
 * @notice A contract that provides allowlist functionalities
 * @author Compound
 */
contract PermissionList {
    /// @notice The major version of this contract
    string public constant VERSION = "1";

    /// @dev Address of the administrator with permissions to update the allowlist
    address public immutable permissionAdmin;

    /// @dev Mapping of addresses to their permissions
    struct Permission {
        bool isAllowed;
        bool state1;
        bool state2;
        bool state3;
        bool state4;
        bool state5;
    }

    /// @notice A record of permissions for each entityId determining if they are allowed. One indexed, since 0 is the default value for all addresses
    mapping(uint256 => Permission) public permissions;

    /// @notice A record of entityIds associated with each address. Setting to 0 removes the address from the permissionList. 
    mapping(address => uint256) public addressEntityIds;

    /// @notice An event emitted when an entityId's permission status is changed
    event PermissionSet(uint256 indexed entityId, Permission permission);

    /// @notice An event emitted when an address is associated with an entityId
    event EntityIdSet(address indexed addr, uint256 indexed entityId);

    /// @dev Thrown when a request is not sent by the authorized admin
    error Unauthorized();

    /// @dev Thrown when the input for a function is invalid
    error BadData();

    /// @dev Thrown when the input is already equivalent to the storage being set
    error AlreadySet();

    /// @dev Default value for the addressEntityIds mapping is 0, so entityIds are 1 indexed and setting permissions for 0 is not allowed
    error ZeroEntityIdNotAllowed();

    /// @dev An adresses's entity ID can not be changed once set, it can only be unset and then set to a new value
    error EntityIdAlreadySet();

    /**
     * @notice Construct a new PermissionList instance
     * @param _permissionAdmin Address of the permission administrator
     */
    constructor(address _permissionAdmin) {
        permissionAdmin = _permissionAdmin;
    }

    /**
     * @notice Checks if the currentValue equals newValue and reverts if so
     * @param currentValue The bool currently written to storage
     * @param newValue The new bool passed in to change currentValue's storage to
     */
    function _comparePermissionBooleans(bool currentValue, bool newValue) internal pure {
        if (currentValue == newValue) revert AlreadySet();
    }

    /**
     * @notice Checks if the currentPermission equals newPermission and reverts if so
     * @param currentPermission The Permission currently written to storage
     * @param newPermission The new Permission passed in to change currentPermission's storage to
     */
    function _comparePermissionStructs(Permission memory currentPermission, Permission memory newPermission) internal pure{
        bytes32 currentHash = keccak256(abi.encode(currentPermission));
        bytes32 newHash = keccak256(abi.encode(newPermission));
        if (currentHash == newHash) revert AlreadySet();
    }

    /**
     * @notice Fetches the permissions for a given address
     * @param addr The entityId whose permissions are to be fetched
     * @return Permission The permissions of the address
     */
    function getPermission(address addr) external view returns (Permission memory) {
        uint256 entityId = addressEntityIds[addr];
        return permissions[entityId];
    }

    // caller must check auth before calling this function
    function _setEntityAddressInternal(address addr, uint256 entityId) internal {
        uint256 prevId = addressEntityIds[addr];

        if (prevId == entityId) revert EntityIdAlreadySet();

        // must set entityId to 0 before setting to a new value
        // if prev id is nonzero 0, entityId must be 0
        if (prevId != 0 && entityId != 0) revert EntityIdAlreadySet();

        addressEntityIds[addr] = entityId;
        emit EntityIdSet(addr, entityId);
    }

    /**
    * @notice Sets the entity Id for a given address. Setting to 0 removes the address from the permissionList
    * @param addr The address to associate with an entityId
    * @param entityId The entityId to associate with an address
    */
    function setEntityIdForAddress(address addr, uint256 entityId) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();
        _setEntityAddressInternal(addr, entityId);
    }

    /**
    * @notice Sets the entity Id for a list of addresses. Setting to 0 removes the address from the permissionList
    * @param addresses The addresses to associate with an entityId
    * @param entityId The entityId to associate with an address
    */
    function setEntityIdForMultipleAddresses(address[] calldata addresses, uint256 entityId) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();

        for (uint256 i = 0; i < addresses.length; ) {
            _setEntityAddressInternal(addresses[i], entityId);
            unchecked { ++i; }
        }
    }
    

    // Internal function to set permissions for a given entityId, auth must be checked by caller
    function _setPermissionInternal(uint256 entityId, Permission calldata permission) internal {
        if (entityId == 0) revert ZeroEntityIdNotAllowed();

        _comparePermissionStructs(permissions[entityId], permission);

        permissions[entityId] = permission;

        emit PermissionSet(entityId, permission);
    }

    /**
     * @notice Sets permissions for a given entityId
     * @param entityId The entityId to be updated
     * @param permission The permission status to set
     */
    function setPermission(uint256 entityId, Permission calldata permission) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();
        _setPermissionInternal(entityId, permission);
    }

    /**
     * @notice Sets permissions for a list of entityIds
     * @param entityIds The entityIds to be updated
     * @param perms The permission statuses to set
     */
    function setMultiplePermissions(uint256[] calldata entityIds, Permission[] calldata perms) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();
        if (entityIds.length != perms.length) revert BadData();

        for (uint256 i = 0; i < entityIds.length; ) {
            _comparePermissionStructs(permissions[entityIds[i]], perms[i]);
            if (entityIds[i] == 0) revert ZeroEntityIdNotAllowed();

            permissions[entityIds[i]] = perms[i];

            emit PermissionSet(entityIds[i], perms[i]);

            unchecked { ++i; }
        }
    }

    function setEntityPermsAndAddresses(uint256 entityId, address[] calldata addresses, Permission calldata permission) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();
        _setPermissionInternal(entityId, permission);

        for (uint256 i = 0; i < addresses.length; ) {
            _setEntityAddressInternal(addresses[i], entityId);
            unchecked { ++i; }
        }
    }

    /**
     * @notice Sets isAllowed permissions for a given entityId
     * @param entityId The entityId to be updated
     * @param value The isAllowed status to set
     */
    function setIsAllowed(uint256 entityId, bool value) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();
        if (entityId == 0) revert ZeroEntityIdNotAllowed();

        Permission storage perms = permissions[entityId];
        _comparePermissionBooleans(perms.isAllowed, value);
        perms.isAllowed = value;

        emit PermissionSet(entityId, perms);
    }

    /**
     * @notice Sets isAllowed permissions for a list of entityIds
     * @param entityIds The entityId to be updated
     * @param values The isAllowed statuses to set
     */
    function setMultipleIsAllowed(uint256[] calldata entityIds, bool[] calldata values) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();
        if (entityIds.length != values.length) revert BadData();

        for (uint256 i = 0; i < entityIds.length; ) {
            uint256 entityId = entityIds[i];
            if (entityId == 0) revert ZeroEntityIdNotAllowed();
            Permission storage perms = permissions[entityId];
            _comparePermissionBooleans(perms.isAllowed, values[i]);
            perms.isAllowed = values[i];

            emit PermissionSet(entityId, perms);

            unchecked { ++i; }
        }
    }

    /**
     * @notice Sets the nth permission for a given entityId
     * @param entityId The entityId to be updated
     * @param index The index of the permission to update
     * @param value The status to set
     * @dev Permissions are 0 indexed, meaning the first permission (isAllowed) has an index of 0
     */
    function setNthPermission(uint256 entityId, uint256 index, bool value) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();
        if (entityId == 0) revert ZeroEntityIdNotAllowed();

        Permission memory perms = permissions[entityId];
        perms = setPermissionAtIndex(perms, index, value);
        permissions[entityId] = perms;

        emit PermissionSet(entityId, perms);
    }

    /**
     * @notice Sets the nth permissions for a list of entityIds
     * @param entityIds The entityIds to be updated
     * @param indices The indices of the permissions to update
     * @param values The statuses to set
     */
    function setMultipleNthPermissions(uint256[] calldata entityIds, uint256[] calldata indices, bool[] calldata values) external {
        if (msg.sender != permissionAdmin) revert Unauthorized();
        if (entityIds.length != indices.length || entityIds.length != values.length) revert BadData();

        for (uint256 i = 0; i < entityIds.length; ) {
            uint256 entityId = entityIds[i];
            if (entityId == 0) revert ZeroEntityIdNotAllowed();

            Permission memory perms = permissions[entityId];
            perms = setPermissionAtIndex(perms, indices[i], values[i]);
            permissions[entityId] = perms;

            emit PermissionSet(entityId, perms);

            unchecked { ++i; }
        }
    }



    /**
     * @dev Sets the nth permission for a Permission and returns the updated struct
     * @param perms The Permission to be updated
     * @param index The index of the permission to update
     * @param value The status to set
     */
    function setPermissionAtIndex(Permission memory perms, uint256 index, bool value) internal pure returns (Permission memory) {
        if (index == 0) {
            _comparePermissionBooleans(perms.isAllowed, value);
            perms.isAllowed = value;
        } else if (index == 1) {
            _comparePermissionBooleans(perms.state1, value);
            perms.state1 = value;
        } else if (index == 2) {
            _comparePermissionBooleans(perms.state2, value);
            perms.state2 = value;
        } else if (index == 3) {
            _comparePermissionBooleans(perms.state3, value);
            perms.state3 = value;
        } else if (index == 4) {
            _comparePermissionBooleans(perms.state4, value);
            perms.state4 = value;
        } else if (index == 5) {
            _comparePermissionBooleans(perms.state5, value);
            perms.state5 = value;
        } else {
            revert BadData();
        }

        return perms;
    }
}
