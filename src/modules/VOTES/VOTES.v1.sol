// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "src/Kernel.sol";

abstract contract VOTESv1 is Module, ERC20 {
    //============================================================================================//
    //                                           ERRORS                                           //
    //============================================================================================//

    error VOTES_TransferDisabled();

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @notice Mint VOTES token to an address
    function mintTo(address wallet_, uint256 amount_) external virtual;

    /// @notice Burn VOTES token from an address. Needs approval.
    function burnFrom(address wallet_, uint256 amount_) external virtual;
}
