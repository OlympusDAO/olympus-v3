// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {LQREGv1} from "src/modules/LQREG/LQREG.v1.sol";
import {BaseLiquidityAMO} from "src/policies/lending/abstracts/BaseLiquidityAMO.sol";
import "src/Kernel.sol";

import {console2} from "forge-std/console2.sol";

/// @title  Olympus Liquidity AMO Registry
/// @notice Olympus Liquidity AMO Registry (Module) Contract
/// @dev    The Olympus Liquidity AMO Registry Module tracks the single-sided liquidity AMOs
///         that are approved to be used by the Olympus protocol. This allows for a single-soure
///         of truth for reporting purposes around total OHM deployed and net emissions.
contract OlympusLiquidityRegistry is LQREGv1 {
    //============================================================================================//
    //                                      MODULE SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_) Module(kernel_) {}

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("LQREG");
    }

    /// @inheritdoc Module
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc LQREGv1
    function addAMO(address amo_) external override permissioned {
        activeAMOs.push(amo_);
        ++activeAMOCount;
    }

    /// @inheritdoc LQREGv1
    function removeAMO(uint256 index_, address amo_) external override permissioned {
        // Sanity check that the AMO at index_ is the same as amo_
        if (activeAMOs[index_] != amo_) revert LQREG_RemovalMismatch();

        // Delete AMO from array by swapping with last element and popping
        activeAMOs[index_] = activeAMOs[activeAMOs.length - 1];
        activeAMOs.pop();
        --activeAMOCount;
    }
}
