// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {SimplePermissionlist} from "src/SimplePermissionlist.sol";

contract SimpleERC20 is ERC20 {
    SimplePermissionlist public immutable list;

    error TransferNotAllowed();

    constructor(uint256 initialSupply, SimplePermissionlist _list) ERC20("SimpleERC20", "SERC20") {
        list = _list;
        _mint(msg.sender, initialSupply);
    }

    // For this dummy contract we only check permissions for the transfer-to function
    function transfer(address to, uint256 value) public override returns (bool) {
        if (list.getPermission(to).forbidden || !list.getPermission(to).allowed) {
            revert TransferNotAllowed();
        }

        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }
}
