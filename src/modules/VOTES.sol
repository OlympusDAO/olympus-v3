// SPDX-License-Identifier: AGPL-3.0-only

// [VOTES] The Votes Module is the ERC20 token that represents voting power in the network.
// This is currently a subtitute module that stubs gOHM.

pragma solidity ^0.8.13;

import {Kernel, Module} from "../Kernel.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract OlympusVotes is Module, ERC20 {
    Kernel.Role public constant ISSUER = Kernel.Role.wrap("VOTES_Issuer");

    constructor(Kernel kernel_)
        Module(kernel_)
        ERC20("OlympusDAO Dummy Voting Tokens", "VOTES", 0)
    {}

    function KEYCODE() public pure override returns (Kernel.Keycode) {
        return Kernel.Keycode.wrap("VOTES");
    }

    function ROLES() public pure override returns (Kernel.Role[] memory roles) {
        roles = new Kernel.Role[](1);
        roles[0] = ISSUER;
    }

    // Policy Interface

    function mintTo(address wallet_, uint256 amount_)
        external
        onlyRole(ISSUER)
    {
        _mint(wallet_, amount_);
    }

    function burnFrom(address wallet_, uint256 amount_)
        external
        onlyRole(ISSUER)
    {
        _burn(wallet_, amount_);
    }
}
