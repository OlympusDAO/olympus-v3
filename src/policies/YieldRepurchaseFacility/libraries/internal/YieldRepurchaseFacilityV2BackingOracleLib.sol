// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IKernel} from "src/interfaces/IKernel.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

/// @title YieldRepurchaseFacilityV2BackingOracleLib
/// @notice The read of the backing value that the YieldRepurchaseFacilityV2 and its lens
///         share: the value the price gate compares against and the burn of the purchased
///         OHM is priced by.
/// @dev An internal library: the function is compiled into each contract that calls it,
///      the linked `YieldRepurchaseFacilityV2DependenciesLib` (for the facility) and the
///      lens.
library YieldRepurchaseFacilityV2BackingOracleLib {
    /// @notice Returns the backing value of `backingOracle_`, in 18 decimals, or zero while
    ///         the oracle is not an active policy of `kernel_` or is disabled.
    /// @dev The oracle keeps serving `backing()` while it is inactive or disabled: zero
    ///      before its first enable, the last value after a disable. Neither is returned.
    ///      The Kernel binding and the enabled state are read before the Kernel membership,
    ///      so an oracle that is not active still reverts on an unreadable or foreign
    ///      binding.
    ///
    ///      Reverts if:
    ///      - The `kernel()` read of the oracle fails or returns a malformed word
    ///        (`PolicyDependency_InvalidDependency`).
    ///      - The oracle reports a kernel other than `kernel_`
    ///        (`PolicyDependency_KernelMismatch`).
    ///      - The `isEnabled()` read of the oracle fails or returns a malformed word
    ///        (`PolicyDependency_InvalidDependency`).
    ///      - The `backing()` read of an active and enabled oracle reverts.
    /// @param kernel_ The Kernel of the facility.
    /// @param backingOracle_ The backing oracle policy of the facility.
    /// @return The backing value, in 18 decimals, or zero.
    function readBacking(address kernel_, address backingOracle_) internal view returns (uint256) {
        PolicyDependency.requireSameKernel(backingOracle_, kernel_);
        if (
            !PolicyDependency.readEnabled(backingOracle_) ||
            !IKernel(kernel_).isPolicyActive(backingOracle_)
        ) return 0;
        return IBackingOracle(backingOracle_).backing();
    }
}
