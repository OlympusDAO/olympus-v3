// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {BondBaseCDA, IBondAggregator, Authority} from "./bases/BondBaseCDA.sol";
import {IBondTeller} from "./interfaces/IBondTeller.sol";

/// @title Bond Fixed-Term Continuous Dutch Auctioneer
/// @notice Bond Fixed-Term Continuous Dutch Auctioneer Contract
/// @dev Bond is a permissionless system to create Olympus-style bond markets
///      for any token pair. The markets do not require maintenance and will manage
///      bond prices based on activity. Bond issuers create BondMarkets that pay out
///      a Payout Token in exchange for deposited Quote Tokens. Users can purchase
///      future-dated Payout Tokens with Quote Tokens at the current market price and
///      receive Bond Tokens to represent their position while their bond vests.
///      Once the Bond Tokens vest, they can redeem it for the Quote Tokens.
///
/// @dev The Fixed-Term Auctioneer is an implementation of the
///      Bond Base Auctioneer contract specific to creating bond markets where
///      purchases vest in a fixed amount of time after purchased (rounded to the day).
///
/// @author Oighty, Zeus, Potted Meat, indigo
contract BondFixedTermCDA is BondBaseCDA {
    /* ========== CONSTRUCTOR ========== */
    constructor(
        IBondTeller teller_,
        IBondAggregator aggregator_,
        address guardian_,
        Authority authority_
    ) BondBaseCDA(teller_, aggregator_, guardian_, authority_) {}

    /* ========== MARKET FUNCTIONS ========== */
    /// @inheritdoc BondBaseCDA
    function createMarket(MarketParams memory params_) external override returns (uint256) {
        return _createMarket(params_);
    }
}
