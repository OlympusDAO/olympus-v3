// SPDX-License-Identifier: AGPL-3.0-only

// [VOTES] The Votes Module is the ERC20 token that represents voting power in the network.
// This is currently a subtitute module that stubs gOHM.

pragma solidity ^0.8.10;

import {Kernel, Module} from "../Kernel.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";

contract Votes is Module, ERC20("Voting Tokens", "VOTES", 18) {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (bytes5) {
        return "VOTES";
    }
}
