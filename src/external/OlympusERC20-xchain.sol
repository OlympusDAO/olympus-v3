// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

interface IOHM {
    function mint(address to_, uint256 amount_) external;

    function burn(uint256 amount_) external;

    function burnFrom(address from_, uint256 amount_) external;
}

contract OlympusERC20 is ERC20, IOHM, Owned {
    constructor() ERC20("Olympus", "OHM", 9) Owned(msg.sender) {}

    function mint(address to_, uint256 amount_) external onlyOwner {
        _mint(to_, amount_);
    }

    function burn(uint256 amount_) external {
        _burn(msg.sender, amount_);
    }

    function burnFrom(address from_, uint256 amount_) external {
        _burnFrom(from_, amount_);
    }

    function _burnFrom(address from_, uint256 amount_) internal {
        uint256 allowed = allowance[from_][msg.sender];
        if (allowed != type(uint256).max) allowance[from_][msg.sender] = allowed - amount_;

        _burn(from_, amount_);
    }
}
