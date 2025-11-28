// SPDX-License-Identifier: Unlicense
// solhint-disable contract-name-camelcase
/// forge-lint: disable-start(mixed-case-variable,mixed-case-function,unwrapped-modifier-logic)
pragma solidity >=0.8.0;

// Test
import {Test} from "@forge-std-1.9.6/Test.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

// Mocks
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";

// Interfaces
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IPRICEv1} from "src/modules/PRICE/IPRICE.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

// Libraries
import {ERC165Helper} from "src/test/lib/ERC165.sol";

// Bophades
import {Actions, Kernel} from "src/Kernel.sol";
import {ModuleWithSubmodules} from "src/Submodules.sol";
import {toSubKeycode} from "src/Submodules.sol";
import {OlympusPricev1_2} from "src/modules/PRICE/OlympusPrice.v1_2.sol";
import {OlympusPricev2} from "src/modules/PRICE/OlympusPrice.v2.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

contract OlympusPricev1_2Test is Test {
    using ModuleTestFixtureGenerator for OlympusPricev1_2;

    // Mock contracts
    MockERC20 internal ohm;
    MockERC20 internal reserveA;
    MockERC20 internal reserveB;
    MockPriceFeed internal ohmUsdPriceFeed;
    MockPriceFeed internal reserveAUsdPriceFeed;
    MockPriceFeed internal reserveBUsdPriceFeed;

    // System contracts
    Kernel internal kernel;
    OlympusPricev1_2 internal price;
    ChainlinkPriceFeeds internal chainlinkPrice;
    SimplePriceFeedStrategy internal strategy;

    // Permissioned addresses
    address internal moduleWriter;
    address internal priceWriterV1_2;
    address internal priceWriterV2;

    // Constants
    uint32 internal constant OBSERVATION_FREQUENCY = 8 hours;
    uint256 internal constant MINIMUM_TARGET_PRICE = 10e18; // 10 USD
    uint256 internal constant OHM_PRICE = 10e18; // 10 USD (18 decimals)
    uint256 internal constant RESERVE_A_PRICE = 5e17; // 0.5 USD (18 decimals)
    uint256 internal constant RESERVE_B_PRICE = 125e16; // 1.25 USD (18 decimals)

    // Events
    event MinimumTargetPriceChanged(uint256 minimumTargetPrice_);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021

        {
            // Deploy mock tokens
            ohm = new MockERC20("Olympus", "OHM", 9);
            reserveA = new MockERC20("Reserve A", "RSVA", 18);
            reserveB = new MockERC20("Reserve B", "RSVB", 18);

            // Deploy mock price feeds
            ohmUsdPriceFeed = new MockPriceFeed();
            ohmUsdPriceFeed.setDecimals(8);
            ohmUsdPriceFeed.setLatestAnswer(int256(10e8)); // $10
            ohmUsdPriceFeed.setTimestamp(block.timestamp);
            ohmUsdPriceFeed.setRoundId(1);
            ohmUsdPriceFeed.setAnsweredInRound(1);

            reserveAUsdPriceFeed = new MockPriceFeed();
            reserveAUsdPriceFeed.setDecimals(8);
            reserveAUsdPriceFeed.setLatestAnswer(int256(5e7)); // $0.50
            reserveAUsdPriceFeed.setTimestamp(block.timestamp);
            reserveAUsdPriceFeed.setRoundId(1);
            reserveAUsdPriceFeed.setAnsweredInRound(1);

            reserveBUsdPriceFeed = new MockPriceFeed();
            reserveBUsdPriceFeed.setDecimals(8);
            reserveBUsdPriceFeed.setLatestAnswer(int256(125e6)); // $1.25
            reserveBUsdPriceFeed.setTimestamp(block.timestamp);
            reserveBUsdPriceFeed.setRoundId(1);
            reserveBUsdPriceFeed.setAnsweredInRound(1);
        }

        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy price module
            price = new OlympusPricev1_2(
                kernel,
                address(ohm),
                OBSERVATION_FREQUENCY,
                MINIMUM_TARGET_PRICE
            );

            // Deploy mock module writer
            moduleWriter = price.generateGodmodeFixture(type(ModuleWithSubmodules).name);
            priceWriterV1_2 = price.generateGodmodeFixture(type(OlympusPricev1_2).name);
            priceWriterV2 = price.generateGodmodeFixture(type(OlympusPricev2).name);

            // Deploy price submodules
            chainlinkPrice = new ChainlinkPriceFeeds(price);
            strategy = new SimplePriceFeedStrategy(price);
        }

        {
            // Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(price));
            kernel.executeAction(Actions.ActivatePolicy, address(moduleWriter));
            kernel.executeAction(Actions.ActivatePolicy, address(priceWriterV1_2));
            kernel.executeAction(Actions.ActivatePolicy, address(priceWriterV2));

            // Install submodules on price module
            vm.startPrank(moduleWriter);
            price.installSubmodule(chainlinkPrice);
            price.installSubmodule(strategy);
            vm.stopPrank();
        }
    }

    // ========== MODIFIERS ========== //

    modifier givenOhmIsConfigured() {
        _configureOhmAsset();
        _;
    }

    modifier givenOhmIsConfiguredWithMovingAverage() {
        _configureOhmAssetWithMovingAverage();
        _;
    }

    modifier givenAllAssetsAreConfigured() {
        _configureAllAssets();
        _;
    }

    modifier givenObservationFrequencyHasElapsed() {
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY);
        _;
    }

    modifier givenOhmPrice(uint256 price_) {
        /// forge-lint: disable-next-line(unsafe-typecast)
        ohmUsdPriceFeed.setLatestAnswer(int256(price_));
        _;
    }

    modifier givenReserveAPrice(uint256 price_) {
        /// forge-lint: disable-next-line(unsafe-typecast)
        reserveAUsdPriceFeed.setLatestAnswer(int256(price_));
        _;
    }

    modifier givenReserveBPrice(uint256 price_) {
        /// forge-lint: disable-next-line(unsafe-typecast)
        reserveBUsdPriceFeed.setLatestAnswer(int256(price_));
        _;
    }

    modifier givenOhmPriceIsStored() {
        vm.prank(priceWriterV2);
        price.storePrice(address(ohm));
        _;
    }

    modifier givenReserveAPriceIsStored() {
        vm.prank(priceWriterV2);
        price.storePrice(address(reserveA));
        _;
    }

    modifier givenReserveBPriceIsStored() {
        vm.prank(priceWriterV2);
        price.storePrice(address(reserveB));
        _;
    }

    // ========== HELPER FUNCTIONS ========== //

    function _configureOhmAsset() internal {
        vm.startPrank(priceWriterV2);

        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedParams = ChainlinkPriceFeeds.OneFeedParams(
            ohmUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ohmFeedParams)
        );

        price.addAsset(
            address(ohm),
            false, // storeMovingAverage
            false, // useMovingAverage
            uint32(0), // movingAverageDuration
            uint48(0), // lastObservationTime
            new uint256[](0), // observations
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // strategy
            feeds
        );

        vm.stopPrank();
    }

    function _configureOhmAssetWithMovingAverage() internal {
        vm.startPrank(priceWriterV2);

        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedParams = ChainlinkPriceFeeds.OneFeedParams(
            ohmUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ohmFeedParams)
        );

        // Create initial observations for moving average
        uint256[] memory observations = new uint256[](2);
        observations[0] = OHM_PRICE;
        observations[1] = OHM_PRICE;

        price.addAsset(
            address(ohm),
            true, // storeMovingAverage
            false, // useMovingAverage
            uint32(2 * OBSERVATION_FREQUENCY), // movingAverageDuration (2 observations)
            uint48(block.timestamp), // lastObservationTime
            observations,
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // strategy
            feeds
        );

        vm.stopPrank();
    }

    function _configureAllAssets() internal {
        vm.startPrank(priceWriterV2);

        // Configure OHM with moving average
        {
            ChainlinkPriceFeeds.OneFeedParams memory ohmFeedParams = ChainlinkPriceFeeds
                .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

            IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
            feeds[0] = IPRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(ohmFeedParams)
            );

            uint256[] memory observations = new uint256[](2);
            observations[0] = OHM_PRICE;
            observations[1] = OHM_PRICE;

            price.addAsset(
                address(ohm),
                true, // storeMovingAverage
                false, // useMovingAverage
                uint32(2 * OBSERVATION_FREQUENCY),
                uint48(block.timestamp),
                observations,
                IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)),
                feeds
            );
        }

        // Configure reserveA without moving average
        {
            ChainlinkPriceFeeds.OneFeedParams memory reserveAFeedParams = ChainlinkPriceFeeds
                .OneFeedParams(reserveAUsdPriceFeed, uint48(24 hours));

            IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
            feeds[0] = IPRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(reserveAFeedParams)
            );

            price.addAsset(
                address(reserveA),
                false, // storeMovingAverage
                false, // useMovingAverage
                uint32(0),
                uint48(0),
                new uint256[](0),
                IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)),
                feeds
            );
        }

        // Configure reserveB with moving average
        {
            ChainlinkPriceFeeds.OneFeedParams memory reserveBFeedParams = ChainlinkPriceFeeds
                .OneFeedParams(reserveBUsdPriceFeed, uint48(24 hours));

            IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
            feeds[0] = IPRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(reserveBFeedParams)
            );

            uint256[] memory observations = new uint256[](2);
            observations[0] = RESERVE_B_PRICE;
            observations[1] = RESERVE_B_PRICE;

            price.addAsset(
                address(reserveB),
                true, // storeMovingAverage
                false, // useMovingAverage
                uint32(2 * OBSERVATION_FREQUENCY),
                uint48(block.timestamp),
                observations,
                IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)),
                feeds
            );
        }

        vm.stopPrank();
    }

    // ========== TESTS ========== //

    // ========== CONSTRUCTOR ========== //

    // given the OHM address is zero
    //  [X] it reverts with PRICE_InvalidParams
    function test_constructor_givenOhmAddressIsZero_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            OlympusPricev1_2.PRICE_InvalidParams.selector,
            "OHM"
        );
        vm.expectRevert(err);

        new OlympusPricev1_2(kernel, address(0), OBSERVATION_FREQUENCY, MINIMUM_TARGET_PRICE);
    }

    // given valid parameters
    //  [X] it deploys successfully
    //  [X] OHM address is set correctly
    //  [X] minimumTargetPrice is set correctly
    //  [X] observationFrequency is set correctly
    //  [X] decimals returns 18
    //  [X] MinimumTargetPriceChanged event is emitted
    function test_constructor_givenValidParameters() public {
        // Verify OHM address is set correctly
        assertEq(price.OHM(), address(ohm), "OHM address should be set correctly");

        // Verify minimum target price is set correctly
        assertEq(
            price.minimumTargetPrice(),
            MINIMUM_TARGET_PRICE,
            "Minimum target price should be set correctly"
        );

        // Verify observation frequency is set correctly
        assertEq(
            price.observationFrequency(),
            OBSERVATION_FREQUENCY,
            "Observation frequency should be set correctly"
        );

        // Verify decimals returns 18
        assertEq(price.decimals(), 18, "Decimals should return 18");

        // Verify event is emitted on deployment
        Kernel testKernel = new Kernel();
        vm.expectEmit(true, false, false, true);
        emit MinimumTargetPriceChanged(MINIMUM_TARGET_PRICE);
        new OlympusPricev1_2(testKernel, address(ohm), OBSERVATION_FREQUENCY, MINIMUM_TARGET_PRICE);
    }

    // ========== VIEW FUNCTIONS ========== //

    // getCurrentPrice
    //  given OHM asset is configured
    //   [X] it returns the current price from PRICEv2
    //   [X] it returns price in 18 decimals
    function test_getCurrentPrice_givenOhmAssetIsConfigured() public givenOhmIsConfigured {
        uint256 currentPrice = price.getCurrentPrice();

        assertEq(currentPrice, OHM_PRICE, "Current price should equal OHM_PRICE");
    }

    // getCurrentPrice
    //  given OHM asset is not configured
    //   [X] it reverts with PRICE_AssetNotApproved
    function test_getCurrentPrice_givenOhmAssetIsNotConfigured_reverts() public {
        bytes memory err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(ohm));
        vm.expectRevert(err);

        price.getCurrentPrice();
    }

    // getLastPrice
    //  given OHM has had the price stored since being added
    //   [X] it returns the last cached price
    //   [X] it returns price in 18 decimals
    function test_getLastPrice_givenCachedInCurrentBlock()
        public
        givenOhmIsConfigured
        givenObservationFrequencyHasElapsed
        givenOhmPrice(11e8) // $11
        givenOhmPriceIsStored
        givenOhmPrice(10e8) // $10
    {
        uint256 lastPrice = price.getLastPrice();

        // Price should be in 18 decimals (11e18 = $11)
        assertEq(lastPrice, 11e18, "Last price should be in 18 decimals (11e18)");
    }

    // getLastPrice
    //  given OHM has not had the price stored since being added
    //   [X] it returns the previous price
    function test_getLastPrice_givenCachedInPreviousBlock()
        public
        givenOhmIsConfigured
        givenObservationFrequencyHasElapsed
        givenOhmPrice(11e8) // $11
    {
        uint256 lastPrice = price.getLastPrice();

        assertEq(lastPrice, OHM_PRICE, "Last price should be the initial price");
    }

    // getLastPrice
    //  given OHM asset is not configured
    //   [X] it reverts with PRICE_AssetNotApproved
    function test_getLastPrice_givenOhmAssetIsNotConfigured_reverts() public {
        bytes memory err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(ohm));
        vm.expectRevert(err);

        price.getLastPrice();
    }

    // getMovingAverage
    //  given OHM has moving average configured
    //   [X] it returns the moving average
    //   [X] it returns price in 18 decimals
    function test_getMovingAverage_givenOhmHasMovingAverageConfigured()
        public
        givenOhmIsConfiguredWithMovingAverage
        givenObservationFrequencyHasElapsed
        givenOhmPrice(11e8) // $11
        givenOhmPriceIsStored
        givenObservationFrequencyHasElapsed
        givenOhmPrice(13e8) // $13
        givenOhmPriceIsStored
    {
        uint256 movingAverage = price.getMovingAverage();

        // Price should be in 18 decimals (12e18 = $12)
        assertEq(movingAverage, 12e18, "Moving average should be in 18 decimals (12e18)");
    }

    // getMovingAverage
    //  given OHM does not have moving average configured
    //   [X] it reverts with PRICE_MovingAverageNotStored
    function test_getMovingAverage_givenOhmDoesNotHaveMovingAverageConfigured_reverts()
        public
        givenOhmIsConfigured
    {
        bytes memory err = abi.encodeWithSignature(
            "PRICE_MovingAverageNotStored(address)",
            address(ohm)
        );
        vm.expectRevert(err);

        price.getMovingAverage();
    }

    // getMovingAverage
    //  given OHM asset is not configured
    //   [X] it reverts with PRICE_AssetNotApproved
    function test_getMovingAverage_givenOhmAssetIsNotConfigured_reverts() public {
        bytes memory err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(ohm));
        vm.expectRevert(err);

        price.getMovingAverage();
    }

    // getTargetPrice
    //  given moving average is greater than minimumTargetPrice
    //   [X] it returns the moving average
    function test_getTargetPrice_givenMovingAverageIsGreaterThanMinimumTargetPrice()
        public
        givenOhmIsConfiguredWithMovingAverage
        givenObservationFrequencyHasElapsed
        givenOhmPrice(11e8) // $11
        givenOhmPriceIsStored
        givenObservationFrequencyHasElapsed
        givenOhmPrice(13e8) // $13
        givenOhmPriceIsStored
    {
        // Moving average is 12e18, minimum is 10e18, so should return moving average
        uint256 targetPrice = price.getTargetPrice();

        // Price should be in 18 decimals (12e18 = $12)
        assertEq(
            targetPrice,
            12e18,
            "Target price should return moving average when MA >= minimum"
        );
    }

    // getTargetPrice
    //  given moving average is less than minimumTargetPrice
    //   [X] it returns minimumTargetPrice
    function test_getTargetPrice_givenMovingAverageIsLessThanMinimumTargetPrice()
        public
        givenOhmIsConfiguredWithMovingAverage
        givenObservationFrequencyHasElapsed
        givenOhmPrice(7e8) // $7
        givenOhmPriceIsStored
        givenObservationFrequencyHasElapsed
        givenOhmPrice(9e8) // $9
        givenOhmPriceIsStored
    {
        // Moving average is 8e18, minimum is 10e18, so should return minimum
        uint256 targetPrice = price.getTargetPrice();

        // Price should be in 18 decimals (10e18 = $10)
        assertEq(targetPrice, 10e18, "Target price should return minimum when MA < minimum");
    }

    // getTargetPrice
    //  given moving average equals minimumTargetPrice
    //   [X] it returns minimumTargetPrice
    function test_getTargetPrice_givenMovingAverageEqualsMinimumTargetPrice()
        public
        givenOhmIsConfiguredWithMovingAverage
    {
        // Minimum is already 10e18, same as moving average
        uint256 targetPrice = price.getTargetPrice();

        assertEq(
            targetPrice,
            MINIMUM_TARGET_PRICE,
            "Target price should return minimum when MA equals minimum"
        );
    }

    // getTargetPrice
    //  given OHM does not have moving average configured
    //   [X] it reverts with PRICE_MovingAverageNotStored
    function test_getTargetPrice_givenOhmDoesNotHaveMovingAverageConfigured_reverts()
        public
        givenOhmIsConfigured
    {
        bytes memory err = abi.encodeWithSignature(
            "PRICE_MovingAverageNotStored(address)",
            address(ohm)
        );
        vm.expectRevert(err);

        price.getTargetPrice();
    }

    // lastObservationTime
    //  given OHM has had the price stored since being added
    //   [X] it returns the last observation timestamp
    function test_lastObservationTime_givenOhmHasObservations()
        public
        givenOhmIsConfiguredWithMovingAverage
        givenObservationFrequencyHasElapsed
        givenOhmPrice(11e8) // $11
        givenOhmPriceIsStored
        givenObservationFrequencyHasElapsed
        givenOhmPrice(13e8) // $13
        givenOhmPriceIsStored
    {
        uint48 lastObsTimeBefore = uint48(block.timestamp);

        // Warp
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY);

        uint48 lastObsTime = price.lastObservationTime();
        assertEq(
            lastObsTime,
            lastObsTimeBefore,
            "Last observation time should equal previous timestamp"
        );
    }

    // lastObservationTime
    //  given OHM has not had the price stored since being added
    //   [X] it returns the initial timestamp
    function test_lastObservationTime_givenOhmHasNoObservations() public givenOhmIsConfigured {
        // Grab the initial timestamp
        uint48 initialTimestamp = uint48(block.timestamp);

        // Warp
        vm.warp(initialTimestamp + OBSERVATION_FREQUENCY);

        uint48 lastObsTime = price.lastObservationTime();
        assertEq(
            lastObsTime,
            initialTimestamp,
            "Last observation time should be the initial timestamp"
        );
    }

    // decimals
    //  [X] it returns 18
    function test_decimals() public view {
        assertEq(price.decimals(), 18, "Decimals should return 18");
    }

    // observationFrequency
    //  [X] it returns the configured observation frequency
    function test_observationFrequency() public view {
        assertEq(
            price.observationFrequency(),
            OBSERVATION_FREQUENCY,
            "Observation frequency should return configured value"
        );
    }

    // minimumTargetPrice
    //  [X] it returns the configured minimum target price
    function test_minimumTargetPrice() public view {
        assertEq(
            price.minimumTargetPrice(),
            MINIMUM_TARGET_PRICE,
            "Minimum target price should return configured value"
        );
    }

    // ========== STATE-CHANGING FUNCTIONS ========== //

    // updateMovingAverage
    //  given caller is permissioned
    //   given observationFrequency has elapsed
    //    given multiple assets are configured (OHM with MA, reserveA without MA, reserveB with MA)
    //     [X] it calls storeObservations
    //     [X] it updates moving averages for OHM (has MA)
    //     [X] it updates moving averages for reserveB (has MA)
    //     [X] it does not update MA for reserveA (no MA configured)
    //     [X] it updates lastObservationTime for all assets with MA
    //     [X] getMovingAverage returns updated value for OHM
    //     [X] getTargetPrice reflects the new moving average for OHM
    //     [X] lastObservationTime is updated for OHM
    function test_updateMovingAverage_givenCallerIsPermissioned_givenObservationFrequencyHasElapsed_givenMultipleAssetsAreConfigured()
        public
        givenAllAssetsAreConfigured
        givenObservationFrequencyHasElapsed
        givenOhmPrice(20e8) // $20
        givenReserveBPrice(30e8) // $30
        givenOhmPriceIsStored
        givenReserveBPriceIsStored
        givenObservationFrequencyHasElapsed
        givenOhmPrice(22e8) // $22
        givenReserveBPrice(32e8) // $32
    // Not stored
    {
        // Get initial moving averages
        IPRICEv2.Asset memory ohmDataBefore = price.getAssetData(address(ohm));
        IPRICEv2.Asset memory reserveADataBefore = price.getAssetData(address(reserveA));
        IPRICEv2.Asset memory reserveBDataBefore = price.getAssetData(address(reserveB));

        uint48 snapshotTimestamp = uint48(block.timestamp);

        // Update moving average
        vm.prank(priceWriterV1_2);
        price.updateMovingAverage();

        // Warp
        vm.warp(block.timestamp + 1);

        // Verify OHM moving average was updated
        uint256 ohmMAAfter = price.getMovingAverage();
        assertEq(ohmMAAfter, 21e18, "OHM moving average should be greater than zero after update");
        // The moving average should have changed (new observation added)
        IPRICEv2.Asset memory ohmDataAfter = price.getAssetData(address(ohm));
        assertEq(
            ohmDataAfter.lastObservationTime,
            snapshotTimestamp,
            "OHM last observation time should equal snapshot timestamp"
        );
        assertGt(
            ohmDataAfter.lastObservationTime,
            ohmDataBefore.lastObservationTime,
            "OHM last observation time should be greater than before"
        );
        assertEq(
            ohmDataAfter.cumulativeObs,
            20e18 + 22e18,
            "OHM cumulative observations should be equal to sum of observations"
        );

        // Verify reserveB moving average was updated
        IPRICEv2.Asset memory reserveBDataAfter = price.getAssetData(address(reserveB));
        assertEq(
            reserveBDataAfter.lastObservationTime,
            snapshotTimestamp,
            "ReserveB last observation time should equal snapshot timestamp"
        );
        assertGt(
            reserveBDataAfter.lastObservationTime,
            reserveBDataBefore.lastObservationTime,
            "ReserveB last observation time should be greater than before"
        );
        assertEq(
            reserveBDataAfter.cumulativeObs,
            30e18 + 32e18,
            "ReserveB cumulative observations should be equal to sum of observations"
        );

        // Verify getTargetPrice reflects the new moving average
        uint256 targetPriceAfter = price.getTargetPrice();
        assertEq(targetPriceAfter, 21e18, "Target price should be equal to moving average");

        // Verify lastObservationTime is updated
        uint48 lastObsTimeAfter = price.lastObservationTime();
        assertEq(
            lastObsTimeAfter,
            snapshotTimestamp,
            "Last observation time should equal snapshot timestamp"
        );
        assertGt(
            lastObsTimeAfter,
            ohmDataBefore.lastObservationTime,
            "Last observation time should be greater than before"
        );

        // reserveA (no MA) should not be affected
        IPRICEv2.Asset memory reserveADataAfter = price.getAssetData(address(reserveA));
        assertEq(
            reserveADataAfter.lastObservationTime,
            reserveADataBefore.lastObservationTime,
            "ReserveA last observation time should not be affected"
        );
        assertEq(
            reserveADataAfter.cumulativeObs,
            reserveADataBefore.cumulativeObs,
            "ReserveA cumulative observations should not be affected"
        );
    }

    // updateMovingAverage
    //  given caller is permissioned
    //   given observationFrequency has not elapsed
    //    [X] it stores the price for the asset
    function test_updateMovingAverage_givenCallerIsPermissioned_givenObservationFrequencyHasNotElapsed()
        public
        givenAllAssetsAreConfigured
        givenOhmPrice(20e8) // $20
        givenReserveBPrice(30e8) // $30
    {
        IPRICEv2.Asset memory reserveADataBefore = price.getAssetData(address(reserveA));

        vm.prank(priceWriterV1_2);
        price.updateMovingAverage();

        // Verify OHM price was stored
        IPRICEv2.Asset memory ohmDataAfter = price.getAssetData(address(ohm));
        assertEq(ohmDataAfter.obs[0], 20e18, "OHM price should be equal to last price");
        assertEq(
            ohmDataAfter.lastObservationTime,
            uint48(block.timestamp),
            "OHM last observation time should be equal to current timestamp"
        );

        // Verify reserveB price was stored
        IPRICEv2.Asset memory reserveBDataAfter = price.getAssetData(address(reserveB));
        assertEq(reserveBDataAfter.obs[0], 30e18, "ReserveB price should be equal to last price");
        assertEq(
            reserveBDataAfter.lastObservationTime,
            uint48(block.timestamp),
            "ReserveB last observation time should be equal to current timestamp"
        );

        // Verify reserveA (no MA) should not be affected
        IPRICEv2.Asset memory reserveADataAfter = price.getAssetData(address(reserveA));
        assertEq(
            reserveADataAfter.obs[0],
            reserveADataBefore.obs[0],
            "ReserveA price should not be affected"
        );
        assertEq(
            reserveADataAfter.lastObservationTime,
            reserveADataBefore.lastObservationTime,
            "ReserveA last observation time should not be affected"
        );
    }

    // updateMovingAverage
    //  given caller is not permissioned
    //   [X] it reverts with Module_PolicyNotPermitted
    function test_updateMovingAverage_givenCallerIsNotPermissioned_reverts()
        public
        givenAllAssetsAreConfigured
        givenObservationFrequencyHasElapsed
    {
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);

        price.updateMovingAverage();
    }

    // changeMinimumTargetPrice
    //  given caller is permissioned
    //   [X] it updates minimumTargetPrice
    //   [X] it emits MinimumTargetPriceChanged event
    //   [X] getTargetPrice reflects new minimum if MA is below it
    //   [X] getTargetPrice still uses MA if MA is above new minimum
    function test_changeMinimumTargetPrice_givenCallerIsPermissioned()
        public
        givenOhmIsConfiguredWithMovingAverage
    {
        // Test updating minimum target price
        uint256 newMinimum = 15e18;
        vm.expectEmit(true, false, false, true);
        emit MinimumTargetPriceChanged(newMinimum);

        vm.prank(priceWriterV1_2);
        price.changeMinimumTargetPrice(newMinimum);

        assertEq(price.minimumTargetPrice(), newMinimum, "Minimum target price should be updated");

        // getTargetPrice should reflect the new minimum
        uint256 targetPrice = price.getTargetPrice();
        assertEq(targetPrice, newMinimum, "Target price should reflect the new minimum");

        // Test that getTargetPrice still uses MA if MA is above new minimum
        uint256 lowerMinimum = 5e18;

        vm.prank(priceWriterV1_2);
        price.changeMinimumTargetPrice(lowerMinimum);

        targetPrice = price.getTargetPrice();
        assertEq(
            targetPrice,
            OHM_PRICE,
            "Target price should use moving average when MA is above minimum"
        );
    }

    // changeMinimumTargetPrice
    //  given caller is not permissioned
    //   [X] it reverts with Module_PolicyNotPermitted
    function test_changeMinimumTargetPrice_givenCallerIsNotPermissioned_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);

        price.changeMinimumTargetPrice(15e18);
    }

    // ========== DEPRECATED FUNCTIONS ========== //

    // initialize
    //  [X] it reverts with PRICE_Deprecated
    function test_initialize_reverts() public {
        bytes memory err = abi.encodeWithSelector(OlympusPricev1_2.PRICE_Deprecated.selector);
        vm.expectRevert(err);

        uint256[] memory observations = new uint256[](0);
        price.initialize(observations, uint48(block.timestamp));
    }

    // changeUpdateThresholds
    //  [X] it reverts with PRICE_Deprecated
    function test_changeUpdateThresholds_reverts() public {
        bytes memory err = abi.encodeWithSelector(OlympusPricev1_2.PRICE_Deprecated.selector);
        vm.expectRevert(err);

        price.changeUpdateThresholds(uint48(24 hours), uint48(24 hours));
    }

    // changeMovingAverageDuration
    //  [X] it reverts with PRICE_Deprecated
    function test_changeMovingAverageDuration_reverts() public {
        bytes memory err = abi.encodeWithSelector(OlympusPricev1_2.PRICE_Deprecated.selector);
        vm.expectRevert(err);

        price.changeMovingAverageDuration(uint48(30 days));
    }

    // changeObservationFrequency
    //  [X] it reverts with PRICE_Deprecated
    function test_changeObservationFrequency_reverts() public {
        bytes memory err = abi.encodeWithSelector(OlympusPricev1_2.PRICE_Deprecated.selector);
        vm.expectRevert(err);

        price.changeObservationFrequency(uint48(8 hours));
    }

    function test_supportsInterface() public view {
        ERC165Helper.validateSupportsInterface(address(price));

        assertEq(price.supportsInterface(type(IERC165).interfaceId), true, "IERC165 mismatch");
        assertEq(price.supportsInterface(type(IPRICEv1).interfaceId), true, "IPRICEv1 mismatch");
        assertEq(price.supportsInterface(type(IPRICEv2).interfaceId), true, "IPRICEv2 mismatch");
    }
}
/// forge-lint: disable-end(mixed-case-variable,mixed-case-function,unwrapped-modifier-logic)
