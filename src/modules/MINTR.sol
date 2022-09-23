// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {OlympusERC20Token as OHM} from "src/external/OlympusERC20.sol";
import "src/Kernel.sol";

/// @notice Wrapper for minting and burning functions of OHM token.
contract OlympusMinter is Module {
    OHM public immutable ohm;

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
        return (1, 0);
    }

    /*//////////////////////////////////////////////////////////////
                               CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    function mintOhm(address to_, uint256 amount_) public permissioned {
        ohm.mint(to_, amount_);
    }

    function burnOhm(address from_, uint256 amount_) public permissioned {
        ohm.burnFrom(from_, amount_);
    }
}
