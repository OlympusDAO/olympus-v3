// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Yield Repurchase Recipient Interface
/// @notice Describes the asset routes through which a repurchase facility can receive protocol yield.
/// @dev Implementations may use any administrative or accounting model. This interface standardizes
///      only read access required to discover supported vault-asset pairs and their routing state.
///      Routes require nonzero ERC4626 vault addresses; direct-custody assets are unsupported.
///      Throughout this interface, `asset` denotes the underlying asset of a vault, as in ERC4626,
///      and not the vault or its share token.
interface IYieldRepurchaseRecipient {
    /// @notice Configuration of one vault through which an underlying asset can be received.
    /// @param vault Nonzero ERC4626 vault registered by the yield repurchase recipient.
    /// @param shareToken ERC20 token representing the shares of the vault: the vault itself for an
    ///        ordinary ERC4626 vault, or the token returned by `share()` for an ERC7575 vault.
    /// @param asset Underlying asset associated with the vault.
    /// @param enabled Whether the recipient currently accepts yield for this vault-asset pair.
    struct VaultConfig {
        address vault;
        address shareToken;
        address asset;
        bool enabled;
    }

    /// @notice The requested vault is not registered by the yield repurchase recipient.
    /// @param vault Unregistered vault address.
    error YieldRepurchaseRecipient_VaultNotRegistered(address vault);

    /// @notice Returns every vault registered by the yield repurchase recipient.
    /// @dev The ordering is implementation-defined and may change when the recipient's
    ///      administrative configuration changes.
    /// @return vaults Registered vault addresses.
    function getVaults() external view returns (address[] memory vaults);

    /// @notice Returns the repurchase-recipient route configured for a vault.
    /// @dev Reverts with `YieldRepurchaseRecipient_VaultNotRegistered` when `vault_` is unknown.
    /// @param vault_ Nonzero ERC4626 vault whose recipient route is requested.
    /// @return config Registered vault, share token, underlying asset, and route enablement state.
    function getVaultConfig(address vault_) external view returns (VaultConfig memory config);

    /// @notice Returns the vault registered by the yield repurchase recipient for an underlying asset.
    /// @dev `asset_` is the underlying asset of the requested vault, the token its `asset()` returns,
    ///      and not the vault or its share token.
    ///      A recipient registers at most one vault for an underlying asset. Does not revert when
    ///      `asset_` is unknown, so a consumer can query candidate tokens without handling reverts.
    /// @param asset_ Underlying asset whose vault is requested.
    /// @return vault Vault registered for `asset_`, or the zero address when none is registered.
    function getAssetVault(address asset_) external view returns (address vault);
}
