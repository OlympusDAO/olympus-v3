// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {MINTRv1, OHM} from "src/modules/MINTR/MINTR.v1.sol";
import "src/Kernel.sol";

/// @notice Wrapper for minting and burning functions of OHM token.
contract OlympusMinter is MINTRv1 {
    //============================================================================================//
    //                                      MODULE SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_, address ohm_) Module(kernel_) {
        ohm = OHM(ohm_);
    }

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("MINTR");
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc MINTRv1
    function mintOhm(address to_, uint256 amount_) external override permissioned {
        if (amount_ == 0) revert MINTR_ZeroAmount();

        uint256 approval = mintApproval[msg.sender];
        if (approval < amount_) revert MINTR_NotApproved();

        // If not infinite approval, decrement approval by amount
        if (approval != type(uint256).max) {
            unchecked {
                mintApproval[msg.sender] = approval - amount_;
            }
        }

        ohm.mint(to_, amount_);

        emit Mint(msg.sender, to_, amount_);
    }

    /// @inheritdoc MINTRv1
    function burnOhm(address from_, uint256 amount_) external override permissioned {
        ohm.burnFrom(from_, amount_);

        emit Burn(msg.sender, from_, amount_);
    }

    /// @inheritdoc MINTRv1
    function increaseMinterApproval(address policy_, uint256 amount_)
        external
        override
        permissioned
    {
        if (mintApproval[policy_] == type(uint256).max) {
            return;
        }

        uint256 newAmount = type(uint256).max - mintApproval[policy_] < amount_
            ? type(uint256).max
            : mintApproval[policy_] + amount_;
        mintApproval[policy_] = newAmount;
        emit IncreaseMinterApproval(policy_, newAmount);
    }

    /// @inheritdoc MINTRv1
    function decreaseMinterApproval(address policy_, uint256 amount_)
        external
        override
        permissioned
    {
        if (mintApproval[policy_] == 0) {
            return;
        }

        uint256 newAmount = mintApproval[policy_] < amount_ ? 0 : mintApproval[policy_] - amount_;
        mintApproval[policy_] = newAmount;
        emit DecreaseMinterApproval(policy_, newAmount);
    }
}
