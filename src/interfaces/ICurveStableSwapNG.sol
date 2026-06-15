// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

// Source: reconstructed from the pool contract’s ABI:
// https://etherscan.io/address/0x57064f49ad7123c92560882a45518374ad982e85

/// @title ICurveStableSwapNG
/// @notice Minimal interface for a Curve StableSwap-NG pool.
/// @dev Only the subset of functions required by the sUSDe swap route is declared.
///      StableSwap-NG `exchange` and `get_dy` use `int128` coin indices, which should
///      be resolved from the `coins` getter.
interface ICurveStableSwapNG {
    /// @notice Returns the address of the coin at index `i`.
    /// @param i The coin index.
    /// @return The coin token address.
    function coins(uint256 i) external view returns (address);

    /// @notice Returns the number of coins held by the pool.
    /// @return The coin count.
    function N_COINS() external view returns (uint256);

    /// @notice Returns the expected output amount of coin `j` for a given input of coin `i`.
    /// @dev This is a spot estimate read from the current pool state and can be
    ///      manipulated within a block, so it must not be used as the sole slippage guard.
    /// @param i The index of the input coin.
    /// @param j The index of the output coin.
    /// @param dx The input amount of coin `i`.
    /// @return The estimated output amount of coin `j`.
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);

    /// @notice Swaps `dx` of coin `i` for coin `j`, sending the output to `receiver`.
    /// @dev Reverts if the output is less than `min_dy`.
    /// @param i The index of the input coin.
    /// @param j The index of the output coin.
    /// @param dx The input amount of coin `i`.
    /// @param min_dy The minimum acceptable output amount of coin `j`.
    /// @param receiver The address that receives coin `j`.
    /// @return The actual output amount of coin `j`.
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy,
        address receiver
    ) external returns (uint256);
}
