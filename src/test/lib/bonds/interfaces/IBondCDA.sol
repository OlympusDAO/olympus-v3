// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IBondAuctioneer} from "../interfaces/IBondAuctioneer.sol";

interface IBondCDA is IBondAuctioneer {
    /// @notice Main information pertaining to bond market
    struct BondMarket {
        address owner; // market owner. sends payout tokens, receives quote tokens (defaults to creator)
        ERC20 payoutToken; // token to pay depositors with
        ERC20 quoteToken; // token to accept as payment
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

    /// @notice Information used to control how a bond market changes
    struct BondTerms {
        uint256 controlVariable; // scaling variable for price
        uint256 maxDebt; // max payout token debt accrued
        uint48 vesting; // length of time from deposit to maturity if fixed-term, vesting timestamp if fixed-expiry
        uint48 conclusion; // timestamp when market no longer offered
    }

    /// @notice Data needed for tuning bond market
    /// @dev Has timestamps in uint32 (not int32), so is not subject to Y2K38 overflow
    struct BondMetadata {
        uint48 lastTune; // last timestamp when control variable was tuned
        uint48 lastDecay; // last timestamp when market was created and debt was decayed
        uint32 length; // time from creation to conclusion.
        uint32 depositInterval; // target frequency of deposits
        uint32 tuneInterval; // frequency of tuning
        uint32 tuneAdjustmentDelay; // time to implement downward tuning adjustments
        uint32 debtDecayInterval; // interval over which debt should decay completely
        uint256 tuneIntervalCapacity; // capacity expected to be used during a tuning interval
        uint256 tuneBelowCapacity; // capacity that the next tuning will occur at
        uint256 lastTuneDebt; // target debt calculated at last tuning
    }

    /// @notice Control variable adjustment data
    struct Adjustment {
        uint256 change;
        uint48 lastAdjustment;
        uint48 timeToAdjusted; // how long until adjustment happens
        bool active;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice             Calculate current market price of payout token in quote tokens
    /// @dev                Accounts for debt and control variable decay since last deposit (vs _marketPrice())
    /// @param id_          ID of market
    /// @return             Price for market in configured decimals (see MarketParams)
    //
    // price is derived from the equation
    //
    // p = c * d
    //
    // where
    // p = price
    // c = control variable
    // d = debt
    //
    // d -= ( d * (dt / l) )
    //
    // where
    // dt = change in time
    // l = length of program
    //
    // if price is below minimum price, minimum price is returned
    // this is enforced on deposits by manipulating total debt (see _decay())
    function marketPrice(uint256 id_) external view override returns (uint256);

    /// @notice             Calculate debt factoring in decay
    /// @dev                Accounts for debt decay since last deposit
    /// @param id_          ID of market
    /// @return             Current debt for market in payout token decimals
    function currentDebt(uint256 id_) external view returns (uint256);

    /// @notice             Up to date control variable
    /// @dev                Accounts for control variable adjustment
    /// @param id_          ID of market
    /// @return             Control variable for market in payout token decimals
    function currentControlVariable(uint256 id_) external view returns (uint256);
}
