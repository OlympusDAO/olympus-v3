// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Yield Claim Interface
/// @notice Minimal capability for claiming and distributing Burner Loans collateral yield.
interface IBurnerLoansYieldClaim {
    /// @notice Claims and distributes excess collateral yield for every registered asset.
    /// @dev Permissionless, atomic, and fail-closed. Asset-origination disable does not block a
    ///      claim. Iterates the append-only asset registry and emits `YieldClaimed` for each asset
    ///      with nonzero claimable yield.
    /// @dev Reverts if Burner Loans or DepositManager is disabled; any registered asset has an
    ///      unsupported or insolvent custody route; a nonzero recipient allocation has an invalid
    ///      live vault-asset route; DepositManager cannot claim the requested yield; or a recipient
    ///      or Treasury transfer fails. Any failure reverts the complete all-asset operation.
    function claimYield() external;
}
