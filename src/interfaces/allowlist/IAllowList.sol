// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IAllowList {
    /// @dev Mapping of addresses to their permissions
    struct Permission {
        bool isAllowed;
        bool state1;
        bool state2;
        bool state3;
        bool state4;
        bool state5;
    }

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

    /// @dev An address's entityId can not be changed once set, it can only be unset and then set to a new value
    error NonZeroEntityIdMustBeChangedToZero();

    /**
     * @notice Fetches the permissions for a given address
     * @param addr The address whose permissions are to be fetched
     * @return Permission The permissions of the address
     */
    function getPermission(address addr) external view returns (Permission memory);

    /**
     * @notice Sets the entityId for a given address. Setting to 0 removes the address from the allowList
     * @param entityId The entityId to associate with an address
     * @param addr The address to associate with an entityId
     */
    function setEntityIdForAddress(uint256 entityId, address addr) external;

    /**
     * @notice Sets the entity Id for a list of addresses. Setting to 0 removes the address from the allowList
     * @param entityId The entityId to associate with an address
     * @param addresses The addresses to associate with an entityId
     */
    function setEntityIdForMultipleAddresses(uint256 entityId, address[] calldata addresses) external;

    /**
     * @notice Sets permissions for a given entityId
     * @param entityId The entityId to be updated
     * @param permission The permission status to set
     */
    function setPermission(uint256 entityId, Permission calldata permission) external;

    /**
     * @notice Sets entity for an array of addresses and sets permissions for an entity
     * @param entityId The entityId to be updated
     * @param addresses The addresses to associate with an entityId
     * @param permission The permissions to set
     */
    function setEntityPermissionAndAddresses(
        uint256 entityId,
        address[] calldata addresses,
        Permission calldata permission
    ) external;

    /**
     * @notice Sets isAllowed permissions for a given entityId
     * @param entityId The entityId to be updated
     * @param value The isAllowed status to set
     */
    function setIsAllowed(uint256 entityId, bool value) external;

    /**
     * @notice Sets the nth permission for a given entityId
     * @param entityId The entityId to be updated
     * @param index The index of the permission to update
     * @param value The status to set
     * @dev Permissions are 0 indexed, meaning the first permission (isAllowed) has an index of 0
     */
    function setNthPermission(uint256 entityId, uint256 index, bool value) external;
}
