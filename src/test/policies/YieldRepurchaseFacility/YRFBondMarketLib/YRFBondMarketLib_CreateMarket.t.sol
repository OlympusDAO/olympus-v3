// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBondSDA} from "src/interfaces/IBondSDA.sol";

// Libraries
import {YRFBondMarketLib} from "src/policies/YieldRepurchaseFacility/YRFBondMarketLib.sol";

// Contracts
import {Test} from "forge-std/Test.sol";

/// @notice Records the parameters of the market the library submits.
/// @dev The library reaches the auctioneer through `CappedCall.tryCall`, so only
///      `createMarket` is required.
contract MockRecordingAuctioneer {
    IBondSDA.MarketParams public lastParams;
    uint256 public nextMarketId = 7;

    function createMarket(bytes calldata params_) external returns (uint256) {
        lastParams = abi.decode(params_, (IBondSDA.MarketParams));
        return nextMarketId;
    }
}

/// @dev The library is external and reached through `DELEGATECALL`, so the calls below
///      execute in this contract's context, exactly as they do in the facility.
contract YRFBondMarketLibTests_CreateMarket is Test {
    MockRecordingAuctioneer internal auctioneer;

    address internal payoutToken = address(0xBEEF);
    address internal quoteToken = address(0xC0DE);

    /// @notice The OHM price denominated in the reserve, in the 18-decimal oracle scale.
    uint256 internal constant ORACLE_PRICE = 10e18;

    /// @notice The market capacity, in payout token units.
    uint256 internal constant CAPACITY = 1_000e18;

    uint256 internal constant INITIAL_DISCOUNT = 3e16; // 3%
    uint256 internal constant MAX_PRICE_PREMIUM = 10e16; // 10%

    function setUp() public {
        auctioneer = new MockRecordingAuctioneer();
    }

    // ========== HELPERS ========== //

    function _config(
        uint256 initialDiscount_,
        uint256 maxPricePremium_,
        uint8 payoutDecimals_
    ) internal view returns (YRFBondMarketLib.MarketConfig memory) {
        return
            YRFBondMarketLib.MarketConfig({
                auctioneer: IBondSDA(address(auctioneer)),
                payoutToken: payoutToken,
                quoteToken: quoteToken,
                capacity: CAPACITY,
                oraclePrice: ORACLE_PRICE,
                initialDiscount: initialDiscount_,
                maxPricePremium: maxPricePremium_,
                oracleDecimals: 18,
                quoteDecimals: 9,
                payoutDecimals: payoutDecimals_
            });
    }

    // ========== TESTS ========== //

    // createMarket
    // given a 3% initial discount and a 10% max price premium
    //  when the market is created
    //   then the initial price inverts the discounted oracle price and the minimum price
    //   inverts that price raised by the premium
    function test_givenDiscountAndPremium_setsPriceBand() public {
        YRFBondMarketLib.createMarket(_config(INITIAL_DISCOUNT, MAX_PRICE_PREMIUM, 18));

        (
            ,
            ,
            ,
            ,
            ,
            uint256 formattedInitialPrice,
            uint256 formattedMinimumPrice,
            ,
            ,
            ,
            ,

        ) = auctioneer.lastParams();

        // The market quotes OHM per payout unit, so both prices invert the oracle price.
        //
        // effectivePrice = 10e18 * (1e18 - 3e16) / 1e18 = 9.7e18 (18 decimals)
        // maxPrice       = 9.7e18 * (1e18 + 1e17) / 1e18 = 10.67e18 (18 decimals)
        // oracleSquare   = 1e36
        // initialPrice   = 1e36 / 9.7e18  = 103_092_783_505_154_639 (floor)
        // minPrice       = 1e36 / 10.67e18 = 93_720_712_277_413_308 (floor)
        //
        // priceDecimals    = 17 - 18 = -1
        // scaleAdjustment  = 18 - 9 + (-1 / 2) = 9        (Solidity truncates -1 / 2 to 0)
        // oracleScale      = 10 ** (18 - (-1))  = 1e19
        // bondScale        = 10 ** (36 + 9 + 9 - 18 - (-1)) = 1e37
        // formatted price  = price * 1e37 / 1e19 = price * 1e18
        assertEq(
            formattedInitialPrice,
            103_092_783_505_154_639 * 1e18,
            "formatted initial price does not invert the discounted oracle price"
        );
        assertEq(
            formattedMinimumPrice,
            93_720_712_277_413_308 * 1e18,
            "formatted minimum price does not invert the premium-raised price"
        );
    }

    // createMarket
    // given a 3% initial discount and a 10% max price premium
    //  when the market is created
    //   then the payout per quote token is capped at 1.067 times the oracle price
    function test_givenDiscountAndPremium_capsPayoutPerQuoteToken() public {
        YRFBondMarketLib.createMarket(_config(INITIAL_DISCOUNT, MAX_PRICE_PREMIUM, 18));

        (, , , , , , uint256 formattedMinimumPrice, , , , , ) = auctioneer.lastParams();

        // The formatted price is `1e36 / maxPrice * 1e18`, so the payout ceiling is
        // 1e54 / formattedMinimumPrice.
        //
        // Expected: 10e18 * 0.97 * 1.1 = 10.67e18 (18 decimals)
        // The two floors lose at most one wei of the unformatted price, which the
        // inversion scales back up, so the tolerance is one part in 1e18.
        uint256 maxPayoutPerQuoteToken = 1e54 / formattedMinimumPrice;
        assertApproxEqRel(
            maxPayoutPerQuoteToken,
            10.67e18,
            1e12,
            "payout ceiling is not 1.067 times the oracle price"
        );
    }

    // createMarket
    // given a zero max price premium
    //  when the market is created
    //   then the minimum price equals the initial price (the market cannot decay)
    function test_givenZeroPremium_pinsMinimumPriceToInitialPrice() public {
        YRFBondMarketLib.createMarket(_config(INITIAL_DISCOUNT, 0, 18));

        (
            ,
            ,
            ,
            ,
            ,
            uint256 formattedInitialPrice,
            uint256 formattedMinimumPrice,
            ,
            ,
            ,
            ,

        ) = auctioneer.lastParams();

        assertEq(
            formattedMinimumPrice,
            formattedInitialPrice,
            "a zero premium does not pin the minimum price to the initial price"
        );
    }

    // createMarket
    // given a zero initial discount
    //  when the market is created
    //   then the minimum price still sits at or below the initial price
    function test_givenZeroDiscount_keepsMinimumPriceAtOrBelowInitialPrice() public {
        YRFBondMarketLib.createMarket(_config(0, MAX_PRICE_PREMIUM, 18));

        (
            ,
            ,
            ,
            ,
            ,
            uint256 formattedInitialPrice,
            uint256 formattedMinimumPrice,
            ,
            ,
            ,
            ,

        ) = auctioneer.lastParams();

        assertLe(
            formattedMinimumPrice,
            formattedInitialPrice,
            "the minimum price exceeds the initial price"
        );
    }

    // createMarket
    // given any valid discount and premium
    //  when the market is created
    //   then the minimum price never exceeds the initial price
    // @dev The Bond SDA rejects a market whose initial price is below its minimum price.
    function test_givenAnyDiscountAndPremium_keepsPriceOrdering(
        uint256 initialDiscount_,
        uint256 maxPricePremium_
    ) public {
        initialDiscount_ = bound(initialDiscount_, 0, 1e18 - 1);
        maxPricePremium_ = bound(maxPricePremium_, 0, 1e18 - 1);

        YRFBondMarketLib.createMarket(_config(initialDiscount_, maxPricePremium_, 18));

        (
            ,
            ,
            ,
            ,
            ,
            uint256 formattedInitialPrice,
            uint256 formattedMinimumPrice,
            ,
            ,
            ,
            ,

        ) = auctioneer.lastParams();

        assertLe(
            formattedMinimumPrice,
            formattedInitialPrice,
            "the minimum price exceeds the initial price"
        );
    }

    // createMarket
    // given a 6-decimal payout token
    //  when the market is created
    //   then the decay band still spans exactly the max price premium
    function test_givenSixDecimalPayoutToken_keepsBandWidth() public {
        YRFBondMarketLib.createMarket(_config(INITIAL_DISCOUNT, MAX_PRICE_PREMIUM, 6));

        (
            ,
            ,
            ,
            ,
            ,
            uint256 formattedInitialPrice,
            uint256 formattedMinimumPrice,
            ,
            ,
            ,
            ,

        ) = auctioneer.lastParams();

        // initialPrice / minPrice = maxPrice / effectivePrice = 1 + maxPricePremium.
        // Expected: 1.1e18 (18 decimals), independent of the payout token decimals.
        assertApproxEqRel(
            (formattedInitialPrice * 1e18) / formattedMinimumPrice,
            1.1e18,
            1e12,
            "the decay band does not span the max price premium"
        );
    }

    // createMarket
    // given the auctioneer accepts the market
    //  when the market is created
    //   then the assigned market id is returned
    function test_givenAcceptedSubmission_returnsMarketId() public {
        (bool success, uint256 marketId, bytes memory reason) = YRFBondMarketLib.createMarket(
            _config(INITIAL_DISCOUNT, MAX_PRICE_PREMIUM, 18)
        );

        assertTrue(success, "the submission was not accepted");
        assertEq(marketId, auctioneer.nextMarketId(), "market id");
        assertEq(reason.length, 0, "reason is not empty");
    }
}
