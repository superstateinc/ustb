// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MockUSTBv1} from "test/token/mocks/MockUSTBv1.sol";
import {MockAllowList} from "test/allowlist/mocks/MockAllowList.sol";

contract MockUSCCv1 is MockUSTBv1 {
    /**
     * @notice Construct a new ERC20 token instance with the given admin and AllowList
     * @param _admin The address designated as the admin with special privileges
     * @param _allowList Address of the AllowList contract to use for permission checking
     * @dev Disables initialization on the implementation contract
     */
    constructor(address _admin, MockAllowList _allowList) MockUSTBv1(_admin, _allowList) {}

    /**
     * @notice Moves `amount` tokens from the caller's account to `dst`
     * @dev Confirms the available balance of the caller is sufficient to cover
     * transfer
     * @dev Includes extra functionality to burn tokens if `dst` is the USTB token address, namely its TransparentUpgradeableProxy
     * @param dst Address to transfer tokens to
     * @param amount Amount of token to transfer
     * @return bool Whether the operation was successful
     */
    function transfer(address dst, uint256 amount) public override returns (bool) {
        // check but dont spend encumbrance
        if (availableBalanceOf(msg.sender) < amount) revert InsufficientAvailableBalance();
        MockAllowList.Permission memory senderPermissions = allowList.getPermission(msg.sender);
        if (!senderPermissions.state1) revert InsufficientPermissions();

        if (dst == address(this)) {
            _requireNotAccountingPaused();
            _burn(msg.sender, amount);
            emit Burn(msg.sender, msg.sender, amount);
        } else {
            _requireNotPaused();
            MockAllowList.Permission memory dstPermissions = allowList.getPermission(dst);
            if (!dstPermissions.state1 || !dstPermissions.state7) revert InsufficientPermissions();
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
        if (encumberedToTaker < amount && !allowList.getPermission(src).state1) {
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
            _releaseEncumbrance(src, msg.sender, encumberedToTaker);

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
            MockAllowList.Permission memory dstPermissions = allowList.getPermission(dst);
            if (!dstPermissions.state1 || !dstPermissions.state7) revert InsufficientPermissions();
            _transfer(src, dst, amount);
        }

        return true;
    }

    /**
     * @notice Check permissions of an address for transferring / encumbering
     * @param addr Address to check permissions for
     * @return bool True if the address has sufficient permission, false otherwise
     */
    function hasSufficientPermissions(address addr) public view override returns (bool) {
        MockAllowList.Permission memory permissions = allowList.getPermission(addr);
        return permissions.state1 && permissions.state7;
    }

    function _mintLogic(address dst, uint256 amount) internal {
        if (!allowList.getPermission(dst).state1) revert InsufficientPermissions();

        _mint(dst, amount);
        emit Mint(msg.sender, dst, amount);
    }

    /**
     * @notice Burn tokens from the caller's address
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external {
        _requireNotAccountingPaused();
        if (availableBalanceOf(msg.sender) < amount) revert InsufficientAvailableBalance();
        MockAllowList.Permission memory senderPermissions = allowList.getPermission(msg.sender);
        if (!senderPermissions.state1) revert InsufficientPermissions();

        _burn(msg.sender, amount);
        emit Burn(msg.sender, msg.sender, amount);
    }

    /**
     * @dev Increase `owner`'s encumbrance to `taker` by `amount`
     */
    function _encumber(address owner, address taker, uint256 amount) internal override {
        if (owner == taker) revert SelfEncumberNotAllowed();
        if (availableBalanceOf(owner) < amount) revert InsufficientAvailableBalance();
        MockAllowList.Permission memory permissions = allowList.getPermission(owner);
        if (!permissions.state1 || !permissions.state7) revert InsufficientPermissions();

        encumbrances[owner][taker] += amount;
        encumberedBalanceOf[owner] += amount;
        emit Encumber(owner, taker, amount);
    }
}
