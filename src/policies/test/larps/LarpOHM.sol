// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract LarpOHM is ERC20 {
    constructor() ERC20("LarpOHM", "OHM", 9) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
