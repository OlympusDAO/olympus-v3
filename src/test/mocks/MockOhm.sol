// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract MockOhm is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }

    function burnFrom(address from, uint256 value) public virtual {
        uint256 currentAllowance = allowance[from][msg.sender];
        require(currentAllowance >= value, "ERC20: burn amount exceeds allowance");
        uint256 currentBalance = balanceOf[from];
        require(currentBalance >= value, "ERC20: burn amount exceeds balance");

        allowance[msg.sender][from] = currentAllowance - value;
        _burn(from, value);
    }
}
