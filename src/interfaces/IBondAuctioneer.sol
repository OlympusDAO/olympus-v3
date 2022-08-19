// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IBondTeller} from "./IBondTeller.sol";
import {IBondAggregator} from "./IBondAggregator.sol";

interface IBondAuctioneer {
    /// @notice             Creates a new bond market
    /// @dev                Note price should be passed in a specific format:
    ///                     formatted price = (payoutPriceCoefficient / quotePriceCoefficient)
    ///                             * 10**(36 + scaleAdjustment + quoteDecimals - payoutDecimals + payoutPriceDecimals - quotePriceDecimals)
    ///                     where:
    ///                         payoutDecimals - Number of decimals defined for the payoutToken in its ERC20 contract
    ///                         quoteDecimals - Number of decimals defined for the quoteToken in its ERC20 contract
    ///                         payoutPriceCoefficient - The coefficient of the payoutToken price in scientific notation (also known as the significant digits)
    ///                         payoutPriceDecimals - The significand of the payoutToken price in scientific notation (also known as the base ten exponent)
    ///                         quotePriceCoefficient - The coefficient of the quoteToken price in scientific notation (also known as the significant digits)
    ///                         quotePriceDecimals - The significand of the quoteToken price in scientific notation (also known as the base ten exponent)
    ///                         scaleAdjustment - see below
    ///                         * In the above definitions, the "prices" need to have the same unit of account (i.e. both in OHM, $, ETH, etc.)
    ///                         If price is not provided in this format, the market will not behave as intended.
    /// @param params_      Encoded bytes array, with the following elements
    /// @dev                    0. Payout Token (token paid out)
    /// @dev                    1. Quote Token (token to be received)
    /// @dev                    2. Callback contract address, should conform to IBondCallback. If 0x00, tokens will be transferred from market.owner
    /// @dev                    3. Is Capacity in Quote Token?
    /// @dev                    4. Capacity (amount in quoteDecimals or amount in payoutDecimals)
    /// @dev                    5. Formatted initial price (see note above)
    /// @dev                    6. Formatted minimum price (see note above)
    /// @dev                    7. Debt buffer. Percent with 3 decimals. Percentage over the initial debt to allow the market to accumulate at anyone time.
    /// @dev                       Works as a circuit breaker for the market in case external conditions incentivize massive buying (e.g. stablecoin depeg).
    /// @dev                       Minimum is the greater of 10% or initial max payout as a percentage of capacity.
    /// @dev                       If the value is too small, the market will not be able function normally and close prematurely.
    /// @dev                       If the value is too large, the market will not circuit break when intended. The value must be > 10% but can exceed 100% if desired.
    /// @dev                    8. Is fixed term ? Vesting length (seconds) : Vesting expiration (timestamp).
    /// @dev                        A 'vesting' param longer than 50 years is considered a timestamp for fixed expiry.
    /// @dev                    9. Conclusion (timestamp)
    /// @dev                    10. Deposit interval (seconds)
    /// @dev                    11. Market scaling factor adjustment, ranges from -24 to +24 within the configured market bounds.
    /// @dev                        Should be calculated as: (payoutDecimals - quoteDecimals) - ((payoutPriceDecimals - quotePriceDecimals) / 2)
    /// @dev                        Providing a scaling factor adjustment that doesn't follow this formula could lead to under or overflow errors in the market.
    /// @return                 ID of new bond market
    struct MarketParams {
        ERC20 payoutToken;
        ERC20 quoteToken;
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

    /// @notice                 Creates a new bond market
    /// @param params_          Configuration data needed for market creation
    /// @return id              ID of new bond market
    function createMarket(MarketParams memory params_) external returns (uint256);

    /// @notice                 Disable existing bond market
    /// @notice                 Must be market owner
    /// @param id_              ID of market to close
    function closeMarket(uint256 id_) external;

    /// @notice                 Exchange quote tokens for a bond in a specified market
    /// @notice                 Must be teller
    /// @param id_              ID of the Market the bond is being purchased from
    /// @param amount_          Amount to deposit in exchange for bond (after fee has been deducted)
    /// @param minAmountOut_    Minimum acceptable amount of bond to receive. Prevents frontrunning
    /// @return payout          Amount of payout token to be received from the bond
    function purchaseBond(
        uint256 id_,
        uint256 amount_,
        uint256 minAmountOut_
    ) external returns (uint256 payout);

    /// @notice                         Set market intervals to different values than the defaults
    /// @notice                         Must be market owner
    /// @dev                            Changing the intervals could cause markets to behave in unexpected way
    ///                                 tuneInterval should be greater than tuneAdjustmentDelay
    /// @param id_                      Market ID
    /// @param intervals_               Array of intervals (3)
    ///                                 1. Tune interval - Frequency of tuning
    ///                                 2. Tune adjustment delay - Time to implement downward tuning adjustments
    ///                                 3. Debt decay interval - Interval over which debt should decay completely
    function setIntervals(uint256 id_, uint32[3] calldata intervals_) external;

    /// @notice                      Designate a new owner of a market
    /// @notice                      Must be market owner
    /// @dev                         Doesn't change permissions until newOwner calls pullOwnership
    /// @param id_                   Market ID
    /// @param newOwner_             New address to give ownership to
    function pushOwnership(uint256 id_, address newOwner_) external;

    /// @notice                      Accept ownership of a market
    /// @notice                      Must be market newOwner
    /// @dev                         The existing owner must call pushOwnership prior to the newOwner calling this function
    /// @param id_                   Market ID
    function pullOwnership(uint256 id_) external;

    /// @notice             Set the auctioneer defaults
    /// @notice             Must be policy
    /// @param defaults_    Array of default values
    ///                     1. Tune interval - amount of time between tuning adjustments
    ///                     2. Tune adjustment delay - amount of time to apply downward tuning adjustments
    ///                     3. Minimum debt decay interval - minimum amount of time to let debt decay to zero
    ///                     4. Minimum deposit interval - minimum amount of time to wait between deposits
    ///                     5. Minimum market duration - minimum amount of time a market can be created for
    ///                     6. Minimum debt buffer - the minimum amount of debt over the initial debt to trigger a market shutdown
    /// @dev                The defaults set here are important to avoid edge cases in market behavior, e.g. a very short market reacts doesn't tune well
    /// @dev                Only applies to new markets that are created after the change
    function setDefaults(uint32[6] memory defaults_) external;

    /// @notice             Change the status of the auctioneer to allow creation of new markets
    /// @dev                Setting to false and allowing active markets to end will sunset the auctioneer
    /// @param status_      Allow market creation (true) : Disallow market creation (false)
    function setAllowNewMarkets(bool status_) external;

    /// @notice             Change whether a market creator is allowed to use a callback address in their markets or not
    /// @notice             Must be guardian
    /// @dev                Callback is believed to be safe, but a whitelist is implemented to prevent abuse
    /// @param creator_     Address of market creator
    /// @param status_      Allow callback (true) : Disallow callback (false)
    function setCallbackAuthStatus(address creator_, bool status_) external;

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice                 Provides information for the Teller to execute purchases on a Market
    /// @param id_              Market ID
    /// @return owner           Address of the market owner (tokens transferred from this address if no callback)
    /// @return callbackAddr    Address of the callback contract to get tokens for payouts
    /// @return payoutToken     Payout Token (token paid out) for the Market
    /// @return quoteToken      Quote Token (token received) for the Market
    /// @return vesting         Timestamp or duration for vesting, implementation-dependent
    /// @return maxPayout       Maximum amount of payout tokens you can purchase in one transaction
    function getMarketInfoForPurchase(uint256 id_)
        external
        view
        returns (
            address owner,
            address callbackAddr,
            ERC20 payoutToken,
            ERC20 quoteToken,
            uint48 vesting,
            uint256 maxPayout
        );

    /// @notice             Calculate current market price of payout token in quote tokens
    /// @param id_          ID of market
    /// @return             Price for market in configured decimals
    //
    // if price is below minimum price, minimum price is returned
    // this is enforced on deposits by manipulating total debt (see _decay())
    function marketPrice(uint256 id_) external view returns (uint256);

    /// @notice             Payout due for amount of quote tokens
    /// @dev                Accounts for debt and control variable decay so it is up to date
    /// @param amount_      Amount of quote tokens to spend
    /// @param id_          ID of market
    /// @param referrer_    Address of referrer, used to get fees to calculate accurate payout amount.
    ///                     Inputting the zero address will take into account just the protocol fee.
    /// @return             amount of payout tokens to be paid
    function payoutFor(
        uint256 amount_,
        uint256 id_,
        address referrer_
    ) external view returns (uint256);

    /// @notice             Returns maximum amount of quote token accepted by the market
    /// @param id_          ID of market
    /// @param referrer_    Address of referrer, used to get fees to calculate accurate payout amount.
    ///                     Inputting the zero address will take into account just the protocol fee.
    function maxAmountAccepted(uint256 id_, address referrer_) external view returns (uint256);

    /// @notice             Does market send payout immediately
    /// @param id_          Market ID to search for
    function isInstantSwap(uint256 id_) external view returns (bool);

    /// @notice             Is a given market accepting deposits
    /// @param id_          ID of market
    function isLive(uint256 id_) external view returns (bool);

    /// @notice             Returns the address of the market owner
    /// @param id_          ID of market
    function ownerOf(uint256 id_) external view returns (address);

    /// @notice             Returns the Teller that services the Auctioneer
    function getTeller() external view returns (IBondTeller);

    /// @notice             Returns the Aggregator that services the Auctioneer
    function getAggregator() external view returns (IBondAggregator);

    /// @notice             Returns current capacity of a market
    function currentCapacity(uint256 id_) external view returns (uint256);
}
