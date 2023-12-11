// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC7246 standard.
 */
interface IERC7246 {
    /**
     * @dev Emitted when `amount` tokens are pledged from `owner` to `taker`.
     */
    event Pledge(address indexed owner, address indexed taker, uint256 amount);

    /**
     * @dev Emitted when the pledge of an `owner` to a `taker` is reduced
     * by `amount`.
     */
    event Release(address indexed owner, address indexed taker, uint256 amount);

    /**
     * @dev Returns the total amount of tokens owned by `owner` that are
     * currently pledged.  MUST never exceed `balanceOf(owner)`
     *
     * Any function which would reduce balanceOf(owner) below
     * pledgedBalanceOf(owner) MUST revert
     */
    function pledgedBalanceOf(address owner) external view returns (uint256);

    /**
     * @dev Returns the number of tokens that `owner` has pledged to `taker`.
     *
     * This value increases when {pledge} or {pledgeFrom} are called by the
     * `owner` or by another permitted account.
     * This value decreases when {release} and {transferFrom} are called by
     * `taker`.
     */
    function pledgedAmounts(address owner, address taker) external view returns (uint256);

    /**
     * @dev Increases the amount of tokens that the caller has pledged to
     * `taker` by `amount`.
     * Grants to `taker` a guaranteed right to transfer `amount` from the
     * caller's balance by using `transferFrom`.
     *
     * MUST revert if caller does not have `amount` tokens available (e.g. if
     * `balanceOf(caller) - pledges(caller) < amount`).
     *
     * Emits an {Pledge} event.
     */
    function pledge(address taker, uint256 amount) external;

    /**
     * @dev Increases the amount of tokens that `owner` has pledged to
     * `taker` by `amount`.
     * Grants to `taker` a guaranteed right to transfer `amount` from `owner`
     * using transferFrom
     *
     * The function SHOULD revert unless the owner account has deliberately
     * authorized the sender of the message via some mechanism.
     *
     * MUST revert if `owner` does not have `amount` tokens available (e.g. if
     * `balanceOf(owner) - pledges(owner) < amount`).
     *
     * Emits an {Pledge} event.
     */
    function pledgeFrom(address owner, address taker, uint256 amount) external;

    /**
     * @dev Reduces amount of tokens pledged from `owner` to caller by
     * `amount`.
     *
     * Emits an {Release} event.
     */
    function release(address owner, uint256 amount) external;

    /**
     * @dev Convenience function for reading the unpledged balance of an address.
     * Trivially implemented as `balanceOf(owner) - pledgedBalanceOf(owner)`
     */
    function availableBalanceOf(address owner) external view returns (uint256);
}
