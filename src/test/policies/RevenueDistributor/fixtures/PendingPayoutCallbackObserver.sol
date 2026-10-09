// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";

contract PendingPayoutCallbackObserver {
    uint256 public observedPendingPayout;

    function observe(
        IRevenueDistributor distributor_,
        address asset_,
        address recipient_
    ) external {
        observedPendingPayout = distributor_.pendingPayout(asset_, recipient_);
    }
}
