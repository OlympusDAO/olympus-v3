// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "src/Kernel.sol";
import {CHREGv1} from "modules/CHREG/CHREG.v1.sol";

/// @title  Olympus Clearinghouse Registry
/// @notice Olympus Clearinghouse Registry (Module) Contract
/// @dev    The Olympus Clearinghouse Registry Module tracks the lending facilities that the Olympus
///         protocol deploys to satisfy the Cooler Loan demand. This allows for a single-soure of truth
///         for reporting purposes around the total Treasury holdings as well as its projected receivables.
contract OlympusClearinghouseRegistry is CHREGv1 {
    //============================================================================================//
    //                                      MODULE SETUP                                          //
    //============================================================================================//

    /// @notice Can be initialized with an active Clearinghouse and list of inactive ones.
    /// @param  kernel_ contract address.
    /// @param  active_ Address of the active Clearinghouse. Set to address(0) if none.
    /// @param  inactive_ List of inactive Clearinghouses. Leave empty if none.
    constructor(Kernel kernel_, address active_, address[] memory inactive_) Module(kernel_) {
        // Process inactive addresses.
        uint256 toRegister = inactive_.length;
        for (uint256 i; i < toRegister; ) {
            // Ensure clearinghouses are either active or inactive.
            if (inactive_[i] == active_) revert CHREG_InvalidConstructor();
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
        // Process active address.
        if (active_ == address(0)) {
            registryCount = toRegister;
        } else {
            active.push(active_);
            registry.push(active_);
            registryCount = toRegister + 1;
            activeCount = 1;
        }
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
            if (active[i] == clearinghouse_) revert CHREG_AlreadyActivated(clearinghouse_);
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
        if (!registered) {
            registry.push(clearinghouse_);
            unchecked {
                ++registryCount;
            }
        }

        emit ClearinghouseActivated(clearinghouse_);
    }

    /// @inheritdoc CHREGv1
    function deactivateClearinghouse(address clearinghouse_) external override permissioned {
        bool found;
        uint256 count = activeCount;
        for (uint256 i; i < count; ) {
            if (active[i] == clearinghouse_) {
                // Delete address from array by swapping with last element and popping.
                active[i] = active[count - 1];
                active.pop();
                --activeCount;
                found = true;
                break;
            }

            unchecked {
                ++i;
            }
        }

        // If Clearinghouse was not active, revert. Otherwise, emit event.
        if (!found) revert CHREG_NotActivated(clearinghouse_);
        emit ClearinghouseDeactivated(clearinghouse_);
    }
}
