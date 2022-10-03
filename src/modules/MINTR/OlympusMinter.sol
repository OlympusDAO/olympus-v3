// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {MINTRv1, OHM} from "src/modules/MINTR/MINTR.v1.sol";
import "src/Kernel.sol";

/// @notice Wrapper for minting and burning functions of OHM token.
contract OlympusMinter is MINTRv1 {
    /*//////////////////////////////////////////////////////////////
                            MODULE INTERFACE
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                               CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc MINTRv1
    function mintOhm(address to_, uint256 amount_) external override permissioned {
        ohm.mint(to_, amount_);
    }

    /// @inheritdoc MINTRv1
    function burnOhm(address from_, uint256 amount_) external override permissioned {
        ohm.burnFrom(from_, amount_);
    }
}
