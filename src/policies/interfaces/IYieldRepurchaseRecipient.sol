// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Yield Repurchase Recipient Interface
/// @notice Describes the asset routes through which a repurchase facility can receive protocol yield.
/// @dev Implementations may use any administrative or accounting model. This interface standardizes
///      only read access required to discover supported vault-asset pairs and their routing state.
///      Routes require nonzero ERC4626 vault addresses; direct-custody assets are unsupported.
interface IYieldRepurchaseRecipient {
    /// @notice Configuration of one vault through which an underlying asset can be received.
    /// @param vault Nonzero ERC4626 vault registered by the yield repurchase recipient.
    /// @param asset Underlying asset associated with the vault.
    /// @param enabled Whether the recipient currently accepts yield for this vault-asset pair.
    struct VaultConfig {
        address vault;
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
    /// @return config Registered vault, underlying asset, and route enablement state.
    function getVaultConfig(address vault_) external view returns (VaultConfig memory config);
}
