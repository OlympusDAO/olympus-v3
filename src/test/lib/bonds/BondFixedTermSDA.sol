// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.15;

import {BondBaseSDA, IBondAggregator, Authority} from "./bases/BondBaseSDA.sol";
import {IBondTeller} from "./interfaces/IBondTeller.sol";

/// @title Bond Fixed-Term Sequential Dutch Auctioneer
/// @notice Bond Fixed-Term Sequential Dutch Auctioneer Contract
/// @dev Bond Protocol is a permissionless system to create Olympus-style bond markets
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
contract BondFixedTermSDA is BondBaseSDA {
    /* ========== CONSTRUCTOR ========== */
    constructor(
        IBondTeller teller_,
        IBondAggregator aggregator_,
        address guardian_,
        Authority authority_
    ) BondBaseSDA(teller_, aggregator_, guardian_, authority_) {}

    /* ========== MARKET FUNCTIONS ========== */
    /// @inheritdoc BondBaseSDA
    function createMarket(bytes calldata params_) external override returns (uint256) {
        // Decode params into the struct type expected by this auctioneer
        MarketParams memory params = abi.decode(params_, (MarketParams));

        // Check that the vesting parameter is valid for a fixed-term market
        if (params.vesting != 0 && (params.vesting < 1 days || params.vesting > MAX_FIXED_TERM))
            revert Auctioneer_InvalidParams();

        // Create market and return market ID
        return _createMarket(params);
    }

    // Tests previously destructured the inherited twelve-value markets() getter. These two narrow
    // getters return only the fields they use, avoiding stack exhaustion in unoptimized call sites.
    function getMarketIdentity(
        uint256 id_
    )
        external
        view
        returns (
            address owner,
            address payoutToken,
            address quoteToken,
            address callbackAddr,
            bool capacityInQuote
        )
    {
        return (
            markets[id_].owner,
            address(markets[id_].payoutToken),
            address(markets[id_].quoteToken),
            markets[id_].callbackAddr,
            markets[id_].capacityInQuote
        );
    }

    function getMarketValues(
        uint256 id_
    )
        external
        view
        returns (uint256 capacity, uint256 minPrice, uint256 maxPayout, uint256 sold, uint256 scale)
    {
        return (
            markets[id_].capacity,
            markets[id_].minPrice,
            markets[id_].maxPayout,
            markets[id_].sold,
            markets[id_].scale
        );
    }
}
