// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "src/Kernel.sol";

error VOTES_TransferDisabled();

/// @notice Votes module is the ERC20 token that represents voting power in the network.
/// @dev    This is currently a substitute module that stubs gOHM.
contract OlympusVotes is Module, ERC20 {
    /*//////////////////////////////////////////////////////////////
                            MODULE INTERFACE
    //////////////////////////////////////////////////////////////*/

    constructor(Kernel kernel_)
        Module(kernel_)
        ERC20("OlympusDAO Dummy Voting Tokens", "VOTES", 0)
    {}

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("VOTES");
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /*//////////////////////////////////////////////////////////////
                               CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    function mintTo(address wallet_, uint256 amount_) external permissioned {
        _mint(wallet_, amount_);
    }

    function burnFrom(address wallet_, uint256 amount_) external permissioned {
        _burn(wallet_, amount_);
    }

    /// @notice Transfers are locked for this token.
    // solhint-disable-next-line no-unused-vars
    function transfer(address to_, uint256 amount_) public pure override returns (bool) {
        revert VOTES_TransferDisabled();
        return true;
    }

    /// @notice TransferFrom is only allowed by permissioned policies.
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
