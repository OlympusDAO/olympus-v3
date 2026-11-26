// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @notice Read-only Core services consumed by ordinary authorization implementations.
/// @dev Core advertises this interface through ERC165 independently of its lifecycle and Auth selection.
interface IBurnerLoansAuthTarget {
    /// @notice Returns the selected verifier and monotonically increasing global revocation epoch.
    /// @return auth Currently selected verifier, or zero before initial selection.
    /// @return globalAuthEpoch Monotonic verifier-installation epoch.
    function authConfig() external view returns (address auth, uint256 globalAuthEpoch);

    /// @notice Returns Core's current Kernel for binding and authoritative membership checks.
    /// @return Current Kernel address.
    function kernel() external view returns (address);

    /// @notice Returns Core's local operational enablement.
    /// @return Whether Core is locally enabled, independently of Kernel membership.
    function isEnabled() external view returns (bool);

    /// @notice Returns whether Core has registered the explicit collateral asset.
    /// @param asset Collateral asset to look up.
    /// @return Whether the asset is registered.
    function isAssetRegistered(address asset) external view returns (bool);
}
