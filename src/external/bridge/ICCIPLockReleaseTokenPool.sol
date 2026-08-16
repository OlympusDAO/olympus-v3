// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {ICCIPLiquidityContainer} from "src/external/bridge/ICCIPLiquidityContainer.sol";

/// @title ICCIPLockReleaseTokenPool
/// @notice The liquidity surface of a Chainlink CCIP `LockReleaseTokenPool` (version 1.5.1).
/// @dev The pool keeps no internal liquidity accounting: it releases from and reports its token
///      balance. `withdrawLiquidity` and `provideLiquidity` are restricted to the rebalancer, and
///      `provideLiquidity` additionally requires the pool to have been deployed with liquidity
///      acceptance enabled.
interface ICCIPLockReleaseTokenPool is ICCIPLiquidityContainer {
    // ========== EVENTS ========== //

    /// @notice Emitted when liquidity is pulled from another pool into this pool.
    /// @param from The pool the liquidity was pulled from.
    /// @param amount The amount transferred.
    event LiquidityTransferred(address indexed from, uint256 amount);

    // ========== ERRORS ========== //

    /// @notice Thrown when a withdrawal exceeds the pool balance.
    error InsufficientLiquidity();

    /// @notice Thrown when liquidity is provided to a pool deployed without liquidity acceptance.
    error LiquidityNotAccepted();

    // ========== FUNCTIONS ========== //

    /// @notice Returns the rebalancer, or the zero address if none is set.
    /// @return rebalancer The rebalancer.
    function getRebalancer() external view returns (address rebalancer);

    /// @notice Sets the rebalancer. Restricted to the pool owner. The zero address clears the
    ///         rebalancer. No event is emitted by the pool.
    /// @param rebalancer The rebalancer address.
    function setRebalancer(address rebalancer) external;

    /// @notice Returns whether the pool accepts liquidity through `provideLiquidity`. The flag
    ///         is fixed at pool construction.
    /// @return accepts True if the pool accepts liquidity.
    function canAcceptLiquidity() external view returns (bool accepts);

    /// @notice Pulls liquidity from another lock/release pool into this pool by calling
    ///         `withdrawLiquidity` on it. Restricted to the pool owner. This pool must be the
    ///         rebalancer of `from`.
    /// @param from The pool to pull liquidity from.
    /// @param amount The amount to transfer.
    function transferLiquidity(address from, uint256 amount) external;
}
