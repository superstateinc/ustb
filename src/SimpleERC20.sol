// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Permissionlist} from "src/Permissionlist.sol";

contract SimpleERC20 is ERC20 {
    Permissionlist public immutable list;

    error TransferNotAllowed();

    constructor(uint256 initialSupply, Permissionlist _list) ERC20("SimpleERC20", "SERC20") {
        list = _list;
        _mint(msg.sender, initialSupply);
    }

    // For this dummy contract we only check permissions for the transfer-to function
    function transfer(address to, uint256 value) public override returns (bool) {
        if (!list.getPermission(to).allowed) {
            revert TransferNotAllowed();
        }

        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }
}
