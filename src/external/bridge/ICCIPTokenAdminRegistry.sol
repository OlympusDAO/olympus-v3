// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title ICCIPTokenAdminRegistry
/// @notice The token-specific surface of the Chainlink CCIP `TokenAdminRegistry` (version 1.5.0):
///         the per-token administrator, its two-step transfer and the pool registration.
/// @dev The registry holds one configuration per token. The administrator of a token selects the
///      pool used for that token and nominates its successor; the successor completes the
///      transfer by accepting it. Registering the zero address as pool delists the token.
///      Functions that change the configuration of a token are restricted to its administrator,
///      except `acceptAdminRole`, which is restricted to its pending administrator, and
///      `proposeAdministrator`, which is restricted to the registry owner and its registry
///      modules.
interface ICCIPTokenAdminRegistry {
    // ========== DATA STRUCTURES ========== //

    /// @notice The configuration of a token.
    /// @param administrator The current administrator of the token.
    /// @param pendingAdministrator The address nominated to become the administrator, or the
    ///        zero address when no transfer is pending.
    /// @param tokenPool The pool registered for the token, or the zero address when the token is
    ///        not deployed or not configured.
    struct TokenConfig {
        address administrator;
        address pendingAdministrator;
        address tokenPool;
    }

    // ========== EVENTS ========== //

    /// @notice Emitted when the pool of a token changes.
    /// @param token The token.
    /// @param previousPool The pool registered before the change.
    /// @param newPool The pool registered after the change.
    event PoolSet(address indexed token, address indexed previousPool, address indexed newPool);

    /// @notice Emitted when an administrator transfer is requested.
    /// @param token The token.
    /// @param currentAdmin The current administrator, or the zero address for a first-time
    ///        proposal.
    /// @param newAdmin The nominated administrator.
    event AdministratorTransferRequested(
        address indexed token,
        address indexed currentAdmin,
        address indexed newAdmin
    );

    /// @notice Emitted when an administrator transfer is accepted.
    /// @param token The token.
    /// @param newAdmin The new administrator.
    event AdministratorTransferred(address indexed token, address indexed newAdmin);

    // ========== ERRORS ========== //

    /// @notice Thrown when `proposeAdministrator` is called by an address that is neither a
    ///         registry module nor the registry owner.
    /// @param sender The rejected caller.
    error OnlyRegistryModuleOrOwner(address sender);

    /// @notice Thrown when an administrator function is called by an address other than the
    ///         administrator of the token.
    /// @param sender The rejected caller.
    /// @param token The token.
    error OnlyAdministrator(address sender, address token);

    /// @notice Thrown when `acceptAdminRole` is called by an address other than the pending
    ///         administrator of the token, including when no transfer is pending.
    /// @param sender The rejected caller.
    /// @param token The token.
    error OnlyPendingAdministrator(address sender, address token);

    /// @notice Thrown when an administrator is proposed for a token that already has one.
    /// @param token The token.
    error AlreadyRegistered(address token);

    /// @notice Thrown when the zero address is proposed as administrator.
    error ZeroAddress();

    /// @notice Thrown when the pool to register does not support the token.
    /// @param token The token.
    error InvalidTokenPoolToken(address token);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the pool registered for a token.
    /// @param token The token.
    /// @return pool The pool, or the zero address if none is registered.
    function getPool(address token) external view returns (address pool);

    /// @notice Returns the configuration of a token.
    /// @param token The token.
    /// @return config The configuration, with every field zero for an unknown token.
    function getTokenConfig(address token) external view returns (TokenConfig memory config);

    /// @notice Returns whether an address is the administrator of a token.
    /// @param localToken The token.
    /// @param administrator The address to check.
    /// @return isAdmin True if `administrator` is the administrator of `localToken`.
    function isAdministrator(
        address localToken,
        address administrator
    ) external view returns (bool isAdmin);

    // ========== ADMINISTRATOR FUNCTIONS ========== //

    /// @notice Registers the pool of a token. The pool must support the token. The zero address
    ///         delists the token from CCIP. Restricted to the administrator of the token.
    /// @param localToken The token.
    /// @param pool The pool to register.
    function setPool(address localToken, address pool) external;

    /// @notice Nominates a new administrator of a token. The current administrator keeps the role
    ///         until the nominee accepts. The zero address cancels a pending transfer. Restricted
    ///         to the administrator of the token.
    /// @param localToken The token.
    /// @param newAdmin The nominated administrator.
    function transferAdminRole(address localToken, address newAdmin) external;

    /// @notice Accepts the administrator role of a token. Restricted to the pending administrator
    ///         of the token.
    /// @param localToken The token.
    function acceptAdminRole(address localToken) external;

    /// @notice Proposes the first administrator of a token. Restricted to the registry owner and
    ///         its registry modules.
    /// @param localToken The token.
    /// @param administrator The proposed administrator.
    function proposeAdministrator(address localToken, address administrator) external;
}
