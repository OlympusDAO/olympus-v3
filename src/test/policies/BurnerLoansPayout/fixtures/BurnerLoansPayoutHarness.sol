// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Libraries
import {EnumerableSet} from "@openzeppelin-5.7.0/utils/structs/EnumerableSet.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansPayout} from "src/policies/burnerloans/BurnerLoansPayout.sol";

/// @dev Exposes raw accounting and set membership; setup uses production credit paths.
contract BurnerLoansPayoutHarness is BurnerLoansPayout {
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(Kernel kernel_, address core_) BurnerLoansPayout(kernel_, core_) {}

    function keeperReward(address token_, address keeper_) external view returns (uint256) {
        return _payouts.pendingKeeperRewards[token_][keeper_];
    }

    function hasPendingToken(address token_) external view returns (bool) {
        return _payouts.pendingTokens.contains(token_);
    }

    function hasPendingKeeper(address token_, address keeper_) external view returns (bool) {
        return _payouts.pendingKeeperRecipients[token_].contains(keeper_);
    }

    function hasPendingReferrer(address token_, address recipient_) external view returns (bool) {
        return _payouts.pendingReferralRecipients[token_].contains(recipient_);
    }
}
