// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Yield Recipient Interface
/// @notice Describes the asset routes through which a contract can receive protocol yield.
/// @dev Implementations may use any administrative or accounting model. This interface standardizes
///      only read access required to discover supported vault-asset pairs and their routing state.
///      Routes are keyed by vault, so an implementation cannot distinguish multiple assets that
///      share one vault key. In particular, a vault-keyed recipient cannot represent multiple
///      direct-custody assets whose vault is the zero address.
interface IYieldRecipient {
    /// @notice Configuration of one vault through which an underlying asset can be received.
    /// @param vault Vault registered by the yield recipient.
    /// @param asset Underlying asset associated with the vault.
    /// @param enabled Whether the recipient currently accepts yield for this vault-asset pair.
    struct VaultConfig {
        address vault;
        address asset;
        bool enabled;
    }

    /// @notice The requested vault is not registered by the yield recipient.
    /// @param vault Unregistered vault address.
    error YieldRecipient_VaultNotRegistered(address vault);

    /// @notice Returns every vault registered by the yield recipient.
    /// @dev The ordering is implementation-defined and may change when the recipient's
    ///      administrative configuration changes.
    /// @return vaults Registered vault addresses.
    function getVaults() external view returns (address[] memory vaults);

    /// @notice Returns the recipient route configured for a vault.
    /// @dev Reverts with `YieldRecipient_VaultNotRegistered` when `vault_` is unknown.
    /// @param vault_ Vault whose recipient route is requested.
    /// @return config Registered vault, underlying asset, and route enablement state.
    function getVaultConfig(address vault_) external view returns (VaultConfig memory config);
}
