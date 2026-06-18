// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IUnderlyingShareRedeemableVault
/// @notice Interface for an ERC4626-style vault that can deliver its underlying shares
///         directly instead of redeeming them to the asset.
/// @dev Used by the asset manager when an asset is configured with `redeemForUnderlyingShares`, so a
///      vault can hand out its underlying shares directly.
interface IUnderlyingShareRedeemableVault {
    /// @notice Burns `shares` of this vault and sends the underlying shares to `receiver`.
    /// @param shares The amount of this vault's shares to burn.
    /// @param receiver The address that receives the underlying shares.
    /// @param owner The address whose shares are burned.
    /// @return The amount of underlying shares sent.
    function redeemForUnderlyingShares(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256);
}
