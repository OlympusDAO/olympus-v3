// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";

/// @title  IBunniManager
/// @author 0xJem
/// @notice Bophades policy to manage UniswapV3 positions.
/// @dev    This policy is paired with a BunniHub instance to manage the lifecycle of BunniTokens.
///
///         What this policy does not cover:
///         - Migrating positions between BunniHub deployments. (This could be achieved by withdrawing and depositing into the new BunniHub instance.)
///         - Migrating positions between Uniswap V3 pools. (This could be achieved by withdrawing and depositing into the new Uniswap V3 pool.)
///         - Managing positions that were not deployed by this policy. (This could be achieved by deploying a new BunniToken and depositing into it.)
///         - Harvesting pool fees. (There is a separate, public policy for this purpose.)
///         - Migrating LP tokens between addresses. (This could be achieved by transferring the ERC20 tokens to the new address.)
///         - Setting the protocol fee on the BunniHub instance (applied when compounding pool fees), as there is no use for having the protocol fees applied.
interface IBunniManager {
    // =========  EVENTS ========= //

    // =========  ERRORS ========= //

    // =========  CORE FUNCTIONS ========= //

    /// @notice       Deploys a new ERC20 token for the given Uniswap V3 pool
    /// @dev          The BunniToken contract is used to wrap the Uniswap V3 position,
    ///               as TRSRY cannot receive ERC721 Uniswap V3 positions.
    ///
    ///               As Olympus Protocol-Owned Liquidity is full-range, the token
    ///               will be deployed with tickLower and tickUpper set to the pool's min and max.
    ///
    /// @param pool_  The address of the Uniswap V3 pool
    /// @return token The ERC20-compatible BunniToken
    function deployToken(address pool_) external returns (IBunniToken token);

    /// @notice         Deposits liquidity into the given Uniswap V3 pool
    ///
    ///                 This can only be called after `deployToken` has been called
    ///                 to deploy the ERC20 token for this pool.
    ///
    ///                 The ordering of tokenA and tokenB is irrelevant. The `deposit` function
    ///                 will handle the ordering of the tokens.
    ///
    /// @param pool_    The address of the Uniswap V3 pool
    /// @param tokenA_  The address of a token (used to determine the orientation of pool tokens)
    /// @param amountA_ The amount of tokenA to deposit
    /// @param amountB_ The amount of tokenB to deposit
    /// @return shares  The amount of shares minted
    function deposit(
        address pool_,
        address tokenA_,
        uint256 amountA_,
        uint256 amountB_
    ) external returns (uint256 shares);

    /// @notice         Withdraws liquidity from the given Uniswap V3 pool
    ///
    ///                 This can only be called after `deployToken` has been called
    ///                 to deploy the ERC20 token for this pool.
    ///
    ///                 The LP tokens will be withdrawn from TRSRY and burned.
    ///
    /// @param pool_    The address of the Uniswap V3 pool
    /// @param shares_  The amount of shares to withdraw
    function withdraw(address pool_, uint256 shares_) external;

    // =========  VIEW FUNCTIONS ========= //

    /// @notice         Get the ERC20-compatible BunniToken for the given Uniswap V3 pool address
    /// @dev            Reverts if:
    ///                 - `pool_` is not managed by this policy and its BunniHub instance
    ///
    /// @param pool_    The address of the Uniswap V3 pool
    /// @return token   The ERC20-compatible BunniToken
    function getToken(address pool_) external view returns (IBunniToken token);

    /// @notice         Gets the balance in TRSRY of the ERC20 token for the given Uniswap V3 pool address
    ///
    /// @param pool_    The address of the Uniswap V3 pool
    /// @return balance The balance of the ERC20 token, or 0
    function getTRSRYBalance(address pool_) external view returns (uint256 balance);

    // =========  ADMIN FUNCTIONS ========= //

    /// @notice             Sets the BunniHub contract
    /// @param newBunniHub_ The new address to use
    function setBunniHub(address newBunniHub_) external;

    /// @notice             Sets the owner of the BunniHub contract
    /// @dev                This can be used when a new policy is deployed that needs to manage the
    ///                     Uniswap V3 positions through the BunniHub.
    ///
    /// @param newOwner_    The address of the new owner
    function setBunniOwner(address newOwner_) external;
}
