// SPDX-License-Identifier: AGPL-3.0-only

// [VOTES] The Votes Module is the ERC20 token that represents voting power in the network.
// This is currently a subtitute module that stubs gOHM.

pragma solidity 0.8.15;

import "src/Kernel.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

error VOTES_TransferDisabled();

contract OlympusVotes is Module, ERC20 {
    Role public constant ISSUER = Role.wrap("VOTES_Issuer");
    Role public constant GOVERNOR = Role.wrap("VOTES_Governor");

    constructor(Kernel kernel_)
        Module(kernel_)
        ERC20("OlympusDAO Dummy Voting Tokens", "VOTES", 0)
    {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("VOTES");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // Policy Interface

    function mintTo(address wallet_, uint256 amount_) external permissioned {
        _mint(wallet_, amount_);
    }

    function burnFrom(address wallet_, uint256 amount_) external permissioned {
        _burn(wallet_, amount_);
    }

    // solhint-disable-next-line no-unused-vars
    function transfer(address to_, uint256 amount_) public pure override returns (bool) {
        revert VOTES_TransferDisabled();
        return true;
    }

    function transferFrom(
        address from_,
        address to_,
        uint256 amount_
    ) public override permissioned returns (bool) {
        balanceOf[from_] -= amount_;
        unchecked {
            balanceOf[to_] += amount_;
        }

        emit Transfer(from_, to_, amount_);
        return true;
    }
}
