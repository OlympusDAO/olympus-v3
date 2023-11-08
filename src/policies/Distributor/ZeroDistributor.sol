// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {IDistributor} from "src/policies/RBS/interfaces/IDistributor.sol";
import {IStaking} from "src/interfaces/IStaking.sol";

contract ZeroDistributor is IDistributor {
    IStaking public immutable staking;
    bool private unlockRebase;

    constructor(address staking_) {
        staking = IStaking(staking_);
    }

    /// @notice Trigger 0 rebase via distributor. There is an error in Staking's stake function
    ///         which pulls forward part of the rebase for the next epoch. This path triggers a
    ///         rebase by calling unstake (which does not have the issue). The patch also
    ///         restricts distribute to only be able to be called from a tx originating in this
    ///         function.
    function triggerRebase() external {
        unlockRebase = true;
        staking.unstake(address(this), 0, true, true);
        if (unlockRebase) revert Distributor_NoRebaseOccurred();
    }

    /// @notice Endpoint must be available for Staking to call. Zero emission.
    function distribute() external {
        if (msg.sender != address(staking)) revert Distributor_OnlyStaking();
        if (!unlockRebase) revert Distributor_NotUnlocked();
        unlockRebase = false;
    }

    /// @notice Endpoint must be available for Staking to call. Zero emission.
    function retrieveBounty() external pure returns (uint256) {
        return 0;
    }
}
