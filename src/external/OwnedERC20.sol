// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {ERC20} from "@openzeppelin-5.3.0/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin-5.3.0/access/Ownable.sol";

/// @notice ERC20 token with owner-only mint, and a burn function
contract OwnedERC20 is ERC20, Ownable {
    constructor(
        string memory name_,
        string memory symbol_,
        address initialOwner_
    ) ERC20(name_, symbol_) Ownable(initialOwner_) {}

    /// @notice Mint tokens to the specified address
    /// @dev    Only the owner can mint tokens
    function mint(address to, uint256 amount) public virtual onlyOwner {
        _mint(to, amount);
    }

    /// @notice Burn tokens from the specified address
    /// @dev    Caller needs allowance if burning from another address
    function burn(address from, uint256 amount) public virtual {
        // If the caller is not the token holder, spend the allowance (or revert)
        if (from != msg.sender) {
            _spendAllowance(from, msg.sender, amount);
        }

        // Burn the tokens
        _burn(from, amount);
    }
}
