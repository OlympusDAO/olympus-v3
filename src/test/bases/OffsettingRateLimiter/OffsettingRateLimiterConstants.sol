// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.18;

/// @notice Shared constants used across the OffsettingRateLimiter unit, fuzz
///         and invariant test suites. Lives in a free-standing library so the
///         invariant entrypoint (which inherits `StdInvariant, Test` and not
///         `OffsettingRateLimiterTestBase`) can reference the same values
///         without duplicating literals.
library OffsettingRateLimiterConstants {
    /// @dev A non-zero starting timestamp used by every test's `setUp` so
    ///      decay arithmetic that subtracts `lastUpdated` is well-defined.
    ///      Picked large enough to allow long warps without crossing the
    ///      uint48 ceiling, and clearly distinct from raw test-defined
    ///      offsets.
    uint256 internal constant START_TIMESTAMP = 1_000_000;
}
