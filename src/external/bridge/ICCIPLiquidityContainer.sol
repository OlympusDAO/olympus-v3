// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title ICCIPLiquidityContainer
/// @notice The liquidity container interface of Chainlink CCIP lock/release token pools.
/// @dev The functions match `ILiquidityContainer` of Chainlink CCIP 1.6.0, so
///      `type(ICCIPLiquidityContainer).interfaceId` equals the identifier that a lock/release
///      pool advertises through ERC165. Both functions are restricted to the pool's rebalancer.
interface ICCIPLiquidityContainer {
    // ========== EVENTS ========== //

    /// @notice Emitted when liquidity is provided to the container.
    /// @param provider The address that provided the liquidity.
    /// @param amount The amount provided.
    event LiquidityAdded(address indexed provider, uint256 indexed amount);

    /// @notice Emitted when liquidity is withdrawn from the container.
    /// @param provider The address that received the liquidity.
    /// @param amount The amount withdrawn.
    event LiquidityRemoved(address indexed provider, uint256 indexed amount);

    // ========== FUNCTIONS ========== //

    /// @notice Transfers `amount` of the pool token from the caller into the container. The
    ///         caller must have approved the container beforehand.
    /// @param amount The amount to provide.
    function provideLiquidity(uint256 amount) external;

    /// @notice Transfers `amount` of the pool token from the container to the caller.
    /// @param amount The amount to withdraw.
    function withdrawLiquidity(uint256 amount) external;
}
