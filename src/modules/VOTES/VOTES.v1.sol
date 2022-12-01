// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import "src/Kernel.sol";

abstract contract VOTESv1 is Module, ERC4626 {
    // =========  STATE ========= //

    ERC20 public gOHM;
    mapping(address => uint256) public lastActionTimestamp;
    mapping(address => uint256) public lastDepositTimestamp;

    // =========  FUNCTIONS ========= //

    function resetActionTimestamp(address wallet_) external virtual;
}
