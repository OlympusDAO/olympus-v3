// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IDistributor {
    // =========  ERRORS ========= //

    error Distributor_NoRebaseOccurred();
    error Distributor_OnlyStaking();
    error Distributor_NotUnlocked();

    // =========  CORE FUNCTIONS ========= //

    /// @notice Trigger rebases via distributor. There is an error in Staking's `stake` function
    ///         which pulls forward part of the rebase for the next epoch. This path triggers a
    ///         rebase by calling `unstake` (which does not have the issue). The patch also
    ///         restricts `distribute` to only be able to be called from a tx originating in this
    ///         function.
    function triggerRebase() external;

    /// @notice Send the epoch's reward to the staking contract, and mint rewards to Uniswap V2 pools.
    ///         This removes opportunity cost for liquidity providers by sending rebase rewards
    ///         directly into the liquidity pool.
    ///
    ///         NOTE: This does not add additional emissions (user could be staked instead and get the
    ///         same tokens).
    function distribute() external;

    /// @notice Mints the bounty (if > 0) to the staking contract for distribution.
    /// @return uint256 The amount of OHM minted as a bounty.
    function retrieveBounty() external returns (uint256);
}
