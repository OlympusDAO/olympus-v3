// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

//import {IOHM} from "../../external/OlympusERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

interface IOHM {
    function mint(address account_, uint256 amount_) external;

    function burn(uint256 amount) external;

    function burnFrom(address account_, uint256 amount_) external;
}

contract MockOhm is IOHM, ERC20 {
    constructor() ERC20("Olympus", "OHM", 9) {}

    function mint(address account_, uint256 amount_) external override {
        _mint(account_, amount_);
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account_, uint256 amount_) external override {
        _burn(account_, amount_);
    }
}
