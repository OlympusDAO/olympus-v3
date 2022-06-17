// SPDX-License-Identifier: AGPL-3.0-only

// [VOTES] The Votes Module is the ERC20 token that represents voting power in the network.
// This is currently a subtitute module that stubs gOHM.

pragma solidity ^0.8.13;

import {Kernel, Module} from "../Kernel.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract Votes is Module, ERC20 {
    constructor(Kernel kernel_)
        Module(kernel_)
        ERC20("Voting Tokens", "VOTES", 18)
    {}

    function KEYCODE() public pure override returns (Kernel.Keycode) {
        return Kernel.Keycode.wrap("VOTES");
    }

    function ROLES()
        public
        pure
        override
        returns (Kernel.Role[] memory roles)
    {}
}
