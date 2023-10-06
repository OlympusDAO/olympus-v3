// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import "src/Kernel.sol";

/// @title  Olympus Clearinghouse Registry
/// @notice Olympus Clearinghouse Registry (Module) Contract
/// @dev    The Olympus Clearinghouse Registry Module tracks the lending facilities that the Olympus
///         protocol deploys to satisfy the Cooler Loan demand. This allows for a single-soure of truth
///         for reporting purposes around the total Treasury holdings as well as its projected receivables.
contract OlympusClearinghouseRegistry is CHREGv1 {
    //============================================================================================//
    //                                      MODULE SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_) Module(kernel_) {}

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("CHREG");
    }

    /// @inheritdoc Module
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc CHREGv1
    function activateClearinghouse(address clearinghouse_) external override permissioned {
        _activateClearinghouse(clearinghouse_);
    }

    /// @inheritdoc CHREGv1
    function manuallyActivateClearinghouse(
        address clearinghouse_
    ) external override onlyKernelExecutor {
        _activateClearinghouse(clearinghouse_);
    }

    /// @inheritdoc CHREGv1
    function deactivateClearinghouse(address clearinghouse_) external override permissioned {
        _deactivateClearinghouse(clearinghouse_);
    }

    /// @inheritdoc CHREGv1
    function manuallyDeactivateClearinghouse(
        address clearinghouse_
    ) external override onlyKernelExecutor {
        _deactivateClearinghouse(clearinghouse_);
    }

    // ========= INTERNAL FUNCTIONS ========= //

    /// @notice internal function to add a new Clearinghouse to the registry.
    function _activateClearinghouse(address clearinghouse_) internal {
        // Ensure Clearinghouse is not currently registered as active.
        uint256 count = activeCount;
        for (uint256 i; i < count; ) {
            if (active[i] == clearinghouse_) revert CHREG_AlreadyRegistered(clearinghouse_);
            unchecked {
                ++i;
            }
        }
        active.push(clearinghouse_);
        unchecked {
            ++activeCount;
        }

        // Only add to registry if it is a new Clearinghouse.
        count = registry.length;
        bool registered;
        for (uint256 i; i < count; ) {
            if (registry[i] == clearinghouse_) registered = true;
            unchecked {
                ++i;
            }
        }
        if (!registered) registry.push(clearinghouse_);

        emit ClearinghouseActivated(clearinghouse_);
    }

    /// @notice internal function to deactivate a clearinghouse from the registry.
    function _deactivateClearinghouse(address clearinghouse_) internal {
        // Find index of vault in array
        uint256 count = activeCount;
        for (uint256 i; i < count; ) {
            if (active[i] == clearinghouse_) {
                // Delete vault from array by swapping with last element and popping
                active[i] = active[count - 1];
                active.pop();
                --activeCount;
                break;
            }

            unchecked {
                ++i;
            }
        }

        emit ClearinghouseDeactivated(clearinghouse_);
    }
}
