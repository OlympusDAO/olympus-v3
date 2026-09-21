// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

/// @title Asset Manager V1.1
/// @notice Extends asset custody with immutable share-token discovery and explicit share-output
///         mode validation.
/// @dev ERC-165 callers should check both the V1 and V1.1 interface IDs because Solidity excludes
///      inherited functions from an interface ID.
interface IAssetManagerV1_1 is IAssetManager {
    // ========== ERRORS ========== //

    /// @notice Thrown when share output is requested for an asset without a configured vault.
    /// @param asset The underlying asset without a configured vault.
    error AssetManager_VaultRequired(address asset);

    /// @notice Thrown when advertised asynchronous capabilities are unsupported or incomplete.
    /// @param asset The configured underlying asset.
    /// @param vault The malformed or unsupported vault.
    error AssetManager_InvalidVaultCapabilities(address asset, address vault);

    /// @notice Thrown when a vault does not expose a usable ERC-20 share token.
    /// @param asset The configured underlying asset.
    /// @param shareToken The invalid share-token address.
    error AssetManager_InvalidShareToken(address asset, address shareToken);

    /// @notice Thrown when a new custody route would reuse a token already managed by another
    ///         asset configuration.
    /// @param token The asset, vault, or external share token that is already managed.
    error AssetManager_TokenAlreadyManaged(address token);

    /// @notice Thrown when a configured custody route requires withdrawals as shares.
    /// @param asset The configured underlying asset.
    /// @param vault The vault whose underlying output is unavailable.
    error AssetManager_RequiresWithdrawAsShares(address asset, address vault);

    /// @notice Thrown when a vault reports shares that do not match the received token balance.
    /// @param asset The configured underlying asset.
    /// @param shareToken The configured share token whose balance was measured.
    /// @param expectedShares The shares reported by the vault.
    /// @param receivedShares The measured share-token balance increase.
    error AssetManager_InexactSharesReceived(
        address asset,
        address shareToken,
        uint256 expectedShares,
        uint256 receivedShares
    );

    // ========== EVENTS ========== //

    /// @notice Emitted when the immutable share token for a configured asset is recorded.
    /// @param asset The configured underlying asset.
    /// @param shareToken The asset for idle custody or the configured vault share token.
    event AssetShareTokenConfigured(address indexed asset, address indexed shareToken);

    /// @notice Emitted when governance changes an asset's explicit share-withdrawal requirement.
    /// @param asset The configured underlying asset.
    /// @param required Whether underlying withdrawals are explicitly disabled for the asset.
    event AssetShareWithdrawalRequirementSet(address indexed asset, bool required);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the token transferred for an asset's requested withdrawal mode.
    /// @dev This reports token identity only; use `validateAssetWithdrawAsShares` to verify whether
    ///      the current vault capabilities support the mode.
    /// @param asset_ The configured underlying asset.
    /// @param withdrawAsShares_ Whether the withdrawal would transfer configured shares.
    /// @return tokenOut The underlying asset or the configured share token.
    function getAssetWithdrawalToken(
        IERC20 asset_,
        bool withdrawAsShares_
    ) external view returns (IERC20 tokenOut);

    /// @notice Returns whether an asset currently requires withdrawals to use its share token.
    /// @dev This combines the explicit per-asset setting with live ERC-7540 async-redeem discovery.
    /// @param asset_ The configured underlying asset.
    /// @return required Whether underlying withdrawal mode is currently unsupported.
    function isAssetShareWithdrawalRequired(IERC20 asset_) external view returns (bool required);

    /// @notice Validates whether a configured asset supports the proposed withdrawal mode.
    /// @param asset_ The configured underlying asset.
    /// @param withdrawAsShares_ Whether withdrawals should transfer vault shares.
    function validateAssetWithdrawAsShares(IERC20 asset_, bool withdrawAsShares_) external view;

    /// @notice Validates an explicit share-withdrawal requirement before it is configured.
    /// @param asset_ The configured underlying asset.
    /// @param required_ Whether underlying withdrawals should be disabled explicitly.
    function validateAssetShareWithdrawalRequired(IERC20 asset_, bool required_) external view;
}
