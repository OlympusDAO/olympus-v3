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

    constructor(
        Kernel kernel_,
        address[] memory active_,
        address[] memory inactive_
    ) Module(kernel_) {
        // Process inactive addresses.
        uint256 toRegister = inactive_.length;
        for (uint256 i; i < toRegister; ) {
            // Ensure no duplicates in active addresses.
            for (uint256 j; j < toRegister; ) {
                if (i != j && inactive_[i] == inactive_[j]) revert CHREG_InvalidConstructor();
                unchecked {
                    ++j;
                }
            }
            // Add to storage.
            registry.push(inactive_[i]);
            unchecked {
                ++i;
            }
        }
        // Process active addresses.
        uint256 toActivate = active_.length;
        for (uint256 i; i < toActivate; ) {
            // Ensure no duplicates in active addresses.
            for (uint256 j; j < toActivate; ) {
                if (i != j && active_[i] == active_[j]) revert CHREG_InvalidConstructor();
                unchecked {
                    ++j;
                }
            }
            // Ensure clearinghouses are either active or inactive.
            for (uint256 k; k < toRegister; ) {
                if (active_[i] == inactive_[k]) revert CHREG_InvalidConstructor();
                unchecked {
                    ++k;
                }
            }
            // Add to storage.
            active.push(active_[i]);
            registry.push(active_[i]);
            unchecked {
                ++i;
            }
        }

        activeCount = toActivate;
        registryCount = toActivate + toRegister;
    }

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

        // Only add to registry if Clearinghouse is new.
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

    /// @inheritdoc CHREGv1
    function deactivateClearinghouse(address clearinghouse_) external override permissioned {
        // Find index of address in the array.
        uint256 count = activeCount;
        for (uint256 i; i < count; ) {
            if (active[i] == clearinghouse_) {
                // Delete address from array by swapping with last element and popping.
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
