// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Yield Claim Interface
/// @notice Minimal capability for claiming Burner Loans collateral yield to its selected destination.
interface IBurnerLoansYieldClaim {
    // ========== EVENTS ========== //

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

    // ========== STRUCTS ========== //

    /// @notice Projected claimable yield for one collateral asset.
    /// @param tokenOut Token returned by DepositManager.
    /// @param requestedAssetAmount Claimable yield requested from DepositManager, in underlying
    ///        collateral decimals.
    /// @param amountOut Amount expected from DepositManager, in `tokenOut` decimals.
    /// @param recipient Destination selected by the current yield flag and distributor pointer;
    ///        zero when requestedAssetAmount is zero and no delivery occurs.
    /// @param executable Whether the claim is executable under current state.
    struct ClaimYieldPreview {
        address tokenOut;
        uint256 requestedAssetAmount;
        uint256 amountOut;
        address recipient;
        bool executable;
    }

    // ========== FUNCTIONS ========== //

    /// @notice Claims excess collateral yield directly to the selected recipient.
    /// @dev Permissionless and enabled-only. The distributor's enabled and Kernel state do not
    ///      govern this claim. A failed recipient transfer leaves yield in DepositManager custody.
    /// @param asset_ Registered collateral asset to claim.
    /// @return tokenOut Token claimed.
    /// @return amountOut Actual yield claimed, in `tokenOut` decimals.
    function claimYield(address asset_) external returns (address tokenOut, uint256 amountOut);

    /// @notice Quotes direct DepositManager yield output and Custody-selected recipient.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @return result Direct yield token/amount, asset request and selected recipient.
    function previewClaimYield(
        address asset_
    ) external view returns (IBurnerLoansYieldClaim.ClaimYieldPreview memory result);
}
