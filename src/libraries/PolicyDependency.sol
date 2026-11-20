// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IKernel} from "src/interfaces/IKernel.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {SafeCallDecoder} from "src/libraries/SafeCallDecoder.sol";

/// @notice Shared Kernel compatibility and readiness checks for Policy dependencies.
/// @dev Consumers retain their interface, system-binding and caller-authorization checks.
library PolicyDependency {
    /// @notice The dependency's Kernel or enabled-state getter failed or returned malformed data.
    error PolicyDependency_InvalidDependency(address dependency);

    /// @notice The dependency reports a different Kernel from its consumer.
    error PolicyDependency_KernelMismatch(
        address dependency,
        address expectedKernel,
        address reportedKernel
    );

    /// @notice A compatible dependency is inactive in the intended Kernel or locally disabled.
    error PolicyDependency_NotActive(address dependency);

    bytes4 internal constant _KERNEL_SELECTOR = 0xd4aae0c4; // kernel()

    /// @notice Requires a canonical Kernel getter matching the consumer's Kernel.
    /// @dev Does not require membership or local enablement, allowing deployment before activation.
    function requireSameKernel(address dependency_, address kernel_) internal view {
        (bool success, address reported) = SafeCallDecoder.safeReadAddress(
            dependency_,
            _KERNEL_SELECTOR
        );
        // Invalid metadata must reject every selected dependency, including inside caller batches.
        // forge-lint: disable-next-line(require-revert-in-loop)
        if (!success) revert PolicyDependency_InvalidDependency(dependency_);
        if (reported != kernel_) {
            // A mismatch must reject the selected dependency even when admission runs in a batch.
            // forge-lint: disable-next-line(require-revert-in-loop)
            revert PolicyDependency_KernelMismatch(dependency_, kernel_, reported);
        }
    }

    /// @notice Reads canonical local enablement without requiring it to be true.
    function readEnabled(address dependency_) internal view returns (bool enabled) {
        bool success;
        (success, enabled) = SafeCallDecoder.safeReadBool(dependency_, IEnabler.isEnabled.selector);
        // Invalid metadata must reject every selected dependency, including inside caller batches.
        // forge-lint: disable-next-line(require-revert-in-loop)
        if (!success) revert PolicyDependency_InvalidDependency(dependency_);
    }

    /// @notice Requires matching Kernel binding and membership, independently of local enablement.
    function requireActive(address dependency_, address kernel_) internal view {
        requireSameKernel(dependency_, kernel_);
        // Each selected dependency needs its own current Kernel-membership check.
        // forge-lint: disable-next-line(calls-loop)
        if (!IKernel(kernel_).isPolicyActive(dependency_)) {
            // Any unavailable dependency must reject the caller's entire batch.
            // forge-lint: disable-next-line(require-revert-in-loop)
            revert PolicyDependency_NotActive(dependency_);
        }
    }

    /// @notice Requires compatible metadata, matching Kernel membership and local enablement.
    /// @dev Compatibility precedes readiness, so inactivity cannot mask a readable mismatch.
    function requireActiveAndEnabled(address dependency_, address kernel_) internal view {
        requireSameKernel(dependency_, kernel_);
        bool enabled = readEnabled(dependency_);
        // Each selected dependency needs its own current Kernel-membership check.
        // forge-lint: disable-next-line(calls-loop)
        if (!IKernel(kernel_).isPolicyActive(dependency_) || !enabled) {
            // Any unavailable dependency must reject the caller's entire batch.
            // forge-lint: disable-next-line(require-revert-in-loop)
            revert PolicyDependency_NotActive(dependency_);
        }
    }
}
