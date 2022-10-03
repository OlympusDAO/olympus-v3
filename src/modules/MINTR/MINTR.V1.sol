// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {OlympusERC20Token as OHM} from "src/external/OlympusERC20.sol";
import "src/Kernel.sol";

/// @notice Wrapper for minting and burning functions of OHM token.
abstract contract MINTRv1 is Module {
    // STATE

    OHM public ohm;

    // FUNCTIONS

    function mintOhm(address to_, uint256 amount_) external virtual;

    function burnOhm(address from_, uint256 amount_) external virtual;
}
