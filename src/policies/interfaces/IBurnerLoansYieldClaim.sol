// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Yield Claim Interface
/// @notice Minimal capability for claiming and distributing Burner Loans collateral yield.
interface IBurnerLoansYieldClaim {
    /// @notice Claims and atomically distributes excess collateral yield for one asset.
    /// @dev Permissionless and enabled-only. Reverts without retaining the claim or any partial
    ///      distribution when custody, active repurchase routing, or a recipient transfer fails.
    /// @param asset_ Registered collateral asset to claim.
    /// @return claimed Actual yield claimed and distributed, in collateral token decimals.
    function claimYield(address asset_) external returns (uint256 claimed);
}
