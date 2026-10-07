// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title IYieldRepoV1
/// @notice The subset of the deployed YieldRepurchaseFacility v1.2 surface used by the
///         migration to the multi-asset v2.
/// @dev `shutdown` is declared with `address[]`, which is ABI-identical to the
///      `ERC20[]` parameter of the deployed contract.
interface IYieldRepoV1 {
    /// @notice Returns the running epoch counter.
    /// @return The epoch counter.
    function epoch() external view returns (uint48);

    /// @notice Returns whether the facility has been shut down.
    /// @return Whether the facility has been shut down.
    function isShutdown() external view returns (bool);

    /// @notice Returns the yield to be funded at the next weekly reset, in USDS (18
    ///         decimals).
    /// @return The stored next yield.
    function nextYield() external view returns (uint256);

    /// @notice Returns the reserve balance snapshot of the last weekly reset, in USDS
    ///         (18 decimals).
    /// @return The reserve balance snapshot.
    function lastReserveBalance() external view returns (uint256);

    /// @notice Returns the conversion rate snapshot of the last weekly reset: the USDS
    ///         amount redeemable for 1e18 sUSDS shares.
    /// @return The conversion rate snapshot.
    function lastConversionRate() external view returns (uint256);

    /// @notice Shuts the facility down: burns its OHM balance and transfers the listed
    ///         token balances to the treasury.
    /// @dev Callable by the loop_daddy role.
    /// @param tokensToTransfer The tokens whose full balances are transferred to the
    ///        treasury.
    function shutdown(address[] memory tokensToTransfer) external;
}
