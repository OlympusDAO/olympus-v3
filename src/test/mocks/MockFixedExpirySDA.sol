// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract MockFixedExpirySDA {
    // ========= DATA STRUCTURES ========= //

    struct BondMarket {
        address owner; // market owner. sends payout tokens, receives quote tokens (defaults to creator)
        MockERC20 payoutToken; // token to pay depositors with
        MockERC20 quoteToken; // token to accept as payment
        address callbackAddr; // address to call for any operations on bond purchase. Must inherit to IBondCallback.
        bool capacityInQuote; // capacity limit is in payment token (true) or in payout (false, default)
        uint256 capacity; // capacity remaining
        uint256 totalDebt; // total payout token debt from market
        uint256 minPrice; // minimum price (debt will stop decaying to maintain this)
        uint256 maxPayout; // max payout tokens out in one order
        uint256 sold; // payout tokens out
        uint256 purchased; // quote tokens in
        uint256 scale; // scaling factor for the market (see MarketParams struct)
    }

    struct MarketParams {
        MockERC20 payoutToken;
        MockERC20 quoteToken;
        address callbackAddr;
        bool capacityInQuote;
        uint256 capacity;
        uint256 formattedInitialPrice;
        uint256 formattedMinimumPrice;
        uint32 debtBuffer;
        uint48 vesting;
        uint48 conclusion;
        uint32 depositInterval;
        int8 scaleAdjustment;
    }

    // ========= STATE VARIABLES ========= //

    uint256 public marketCount;

    mapping(uint256 => BondMarket) public markets;

    // ========= CONSTRUCTOR ========= //

    constructor() {}

    // ========= MARKET CREATION ========= //

    function createMarket(bytes calldata params_) external returns (uint256) {
        uint256 marketId = marketCount++;

        MarketParams memory params = abi.decode(params_, (MarketParams));
        markets[marketId] = BondMarket({
            owner: msg.sender,
            payoutToken: params.payoutToken,
            quoteToken: params.quoteToken,
            callbackAddr: params.callbackAddr,
            capacityInQuote: params.capacityInQuote,
            capacity: params.capacity,
            totalDebt: 0,
            minPrice: params.formattedMinimumPrice,
            maxPayout: params.capacity,
            sold: 0,
            purchased: 0,
            scale: 0
        });

        return marketId;
    }

    // ========= MARKET CLOSURE ========= //

    function closeMarket(uint256 id_) external {
        markets[id_].capacity = 0;
    }

    // ========= VIEW FUNCTIONS ========= //

    function getMarketInfoForPurchase(
        uint256 id_
    )
        external
        view
        returns (
            address owner,
            address callbackAddr,
            MockERC20 payoutToken,
            MockERC20 quoteToken,
            uint48 vesting,
            uint256 maxPayout
        )
    {
        BondMarket memory market = markets[id_];
        return (
            market.owner,
            market.callbackAddr,
            market.payoutToken,
            market.quoteToken,
            0,
            market.maxPayout
        );
    }

    function isLive(uint256 id_) public view returns (bool) {
        return (markets[id_].capacity != 0);
    }
}
