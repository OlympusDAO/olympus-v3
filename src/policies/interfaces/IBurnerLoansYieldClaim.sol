// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Yield Claim Interface
/// @notice Minimal capability for claiming Burner Loans collateral yield to its selected destination.
interface IBurnerLoansYieldClaim {
    /// @notice Emitted after DepositManager delivers custody yield to the selected recipient.
    /// @param asset Collateral asset whose yield was claimed.
    /// @param requestedAssetAmount Yield requested in collateral asset units.
    /// @param tokenOut Token delivered by DepositManager.
    /// @param amountOut Amount delivered in `tokenOut` units.
    /// @param recipient Selected yield recipient.
    event YieldClaimed(
        address indexed asset,
        uint256 requestedAssetAmount,
        address indexed tokenOut,
        uint256 amountOut,
        address indexed recipient
    );

    /// @notice Claims excess collateral yield directly to the selected recipient.
    /// @dev Permissionless and enabled-only. The distributor's enabled and Kernel state do not
    ///      govern this claim. A failed recipient transfer leaves yield in DepositManager custody.
    /// @param asset_ Registered collateral asset to claim.
    /// @return tokenOut Token claimed.
    /// @return amountOut Actual yield claimed, in `tokenOut` decimals.
    function claimYield(address asset_) external returns (address tokenOut, uint256 amountOut);
}
