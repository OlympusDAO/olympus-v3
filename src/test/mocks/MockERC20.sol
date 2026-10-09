// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.27;

// Contracts
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";

/// @notice Mintable OZ token with configurable metadata for tests.
// This general token intentionally does not depend on a DepositManager fixture interface.
// forge-lint: disable-next-line(missing-inheritance)
contract MockERC20 is ERC20 {
    uint8 internal immutable _TOKEN_DECIMALS;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _TOKEN_DECIMALS = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _TOKEN_DECIMALS;
    }

    function mint(address recipient_, uint256 amount_) public {
        _mint(recipient_, amount_);
    }

    function burn(address account_, uint256 amount_) public {
        _burn(account_, amount_);
    }

    function burnFrom(address account_, uint256 amount_) public {
        _spendAllowance(account_, msg.sender, amount_);
        _burn(account_, amount_);
    }
}
