// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FullMath} from "libraries/FullMath.sol";

import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";

import {OlympusPrice} from "modules/PRICE/OlympusPrice.sol";
import "src/Kernel.sol";

contract PriceTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusPrice;

    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal reserveEthPriceFeed;
    MockERC20 internal ohm;
    MockERC20 internal reserve;

    Kernel internal kernel;
    OlympusPrice internal price;

    address internal writer;

    int256 internal constant CHANGE_DECIMALS = 1e4;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        {
            /// Deploy protocol mocks external to guidance
            ohm = new MockERC20("Olympus", "OHM", 9);
            reserve = new MockERC20("Reserve", "RSV", 18);

            ohmEthPriceFeed = new MockPriceFeed();
            ohmEthPriceFeed.setDecimals(18);

            reserveEthPriceFeed = new MockPriceFeed();
            reserveEthPriceFeed.setDecimals(18);
        }

        {
            /// Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            /// Deploy price module
            price = new OlympusPrice(
                kernel,
                ohmEthPriceFeed, // AggregatorInterface ohmEthPriceFeed_,
                uint48(24 hours), // uint32 ohmEthUpdateThreshold_,
                reserveEthPriceFeed, // AggregatorInterface reserveEthPriceFeed_,
                uint48(24 hours), // uint32 reserveEthUpdateThreshold_,
                uint48(8 hours), // uint32 observationFrequency_,
                uint48(7 days), // uint32 movingAverageDuration_,
                10 * 1e18 // uint256 minimumTargetPrice_
            );

            /// Deploy mock module writer
            writer = price.generateGodmodeFixture(type(OlympusPrice).name);
        }

        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(price));
            kernel.executeAction(Actions.ActivatePolicy, address(writer));
        }

        {
            /// Initialize timestamps on mock price feeds
            ohmEthPriceFeed.setTimestamp(block.timestamp);
            reserveEthPriceFeed.setTimestamp(block.timestamp);
        }
    }

    // =========  HELPER FUNCTIONS ========= //
    function initializePrice(uint8 nonce) internal {
        /// Assume that the reserveEth price feed is fixed at 0.001 ETH = 1 Reserve
        reserveEthPriceFeed.setLatestAnswer(int256(1e15));
        uint256 reserveEthPrice = uint256(reserveEthPriceFeed.latestAnswer());

        /// Set ohmEth price to 0.01 ETH = 1 OHM initially
        /// This makes the price 10 reserves per OHM, which is the same as our minimum value.
        /// Random moves up and down will be above or below this.
        int256 ohmEthPrice = int256(1e16);

        /// Set scaling value for calculations
        uint256 scale = 10 **
            (price.decimals() + reserveEthPriceFeed.decimals() - ohmEthPriceFeed.decimals());

        /// Calculate the number of observations and initialize the observation array
        uint48 observationFrequency = price.observationFrequency();
        uint48 movingAverageDuration = price.movingAverageDuration();
        uint256 numObservations = movingAverageDuration / observationFrequency;
        uint256[] memory observations = new uint256[](numObservations);

        /// Perform a random walk to initialize the observations
        int256 change; // percentage with two decimals
        for (uint256 i; i < numObservations; ++i) {
            /// Calculate a random percentage change from -10% to + 10% using the nonce and observation number
            change = int256(uint256(keccak256(abi.encodePacked(nonce, i)))) % int256(1000);

            /// Calculate the new ohmEth price
            ohmEthPrice = (ohmEthPrice * (CHANGE_DECIMALS + change)) / CHANGE_DECIMALS;

            /// Update price feed
            ohmEthPriceFeed.setLatestAnswer(ohmEthPrice);

            /// Get the current price from the price module and store in the observations array
            observations[i] = uint256(ohmEthPrice).mulDiv(scale, reserveEthPrice);
        }

        /// Initialize the price module with the observations
        vm.prank(writer);
        price.initialize(observations, uint48(block.timestamp));
    }

    function makeRandomObservations(uint8 nonce, uint256 observations)
        internal
        returns (uint48 timeIncrease)
    {
        /// Perform a random walk and update the moving average with the supplied number of observations
        int256 change; // percentage with two decimals
        int256 ohmEthPrice = ohmEthPriceFeed.latestAnswer();
        uint48 observationFrequency = price.observationFrequency();
        for (uint256 i; i < observations; ++i) {
            /// Calculate a random percentage change from -10% to + 10% using the nonce and observation number
            change = int256(uint256(keccak256(abi.encodePacked(nonce, i)))) % int256(1000);

            /// Calculate the new ohmEth price
            ohmEthPrice = (ohmEthPrice * (CHANGE_DECIMALS + change)) / CHANGE_DECIMALS;

            /// Update price feed
            ohmEthPriceFeed.setLatestAnswer(ohmEthPrice);
            ohmEthPriceFeed.setTimestamp(block.timestamp);
            reserveEthPriceFeed.setTimestamp(block.timestamp);

            /// Call update moving average on the price module
            vm.prank(writer);
            price.updateMovingAverage();

            /// Shift time forward by the observation frequency
            timeIncrease += observationFrequency;
            vm.warp(block.timestamp + observationFrequency);
        }
    }

    // =========  UPDATE TESTS ========= //

    /// DONE
    /// [X] update moving average cannot be called before price initialization
    /// [X] update moving average
    /// [X] update moving average several times and expand observations

    function testCorrectness_cannotUpdateMovingAverageBeforeInitialization() public {
        bytes memory err = abi.encodeWithSignature("Price_NotInitialized()");

        vm.expectRevert(err);
        vm.prank(writer);
        price.updateMovingAverage();
    }

    function testCorrectness_onlyPermittedPoliciesCanCallUpdateMovingAverage(uint8 nonce) public {
        bytes memory err = abi.encodeWithSelector(
            Module.Module_PolicyNotPermitted.selector,
            address(this)
        );

        /// Initialize price module
        initializePrice(nonce);

        /// Call updateMovingAverage with a non-approved address
        vm.expectRevert(err);
        price.updateMovingAverage();
    }

    function testCorrectness_updateMovingAverage(uint8 nonce) public {
        /// Initialize price module
        initializePrice(nonce);

        /// Get the earliest observation on the price module
        uint256 earliestPrice = price.observations(0);
        uint256 numObservations = uint256(price.numObservations());

        /// Get the current price from the price module
        uint256 currentPrice = price.getCurrentPrice();

        /// Get the current cumulativeObs from the price module
        uint256 cumulativeObs = price.cumulativeObs();

        /// Calculate the expected moving average
        uint256 expCumulativeObs = cumulativeObs + currentPrice - earliestPrice;
        uint256 expMovingAverage = expCumulativeObs / numObservations;

        /// Update the moving average on the price module
        vm.prank(writer);
        price.updateMovingAverage();

        /// Check that the moving average was updated correctly
        assertEq(expCumulativeObs, price.cumulativeObs());
        assertEq(expMovingAverage, price.getMovingAverage());
    }

    function testCorrectness_updateMovingAverageMultipleTimes(uint8 nonce) public {
        /// Initialize price module
        initializePrice(nonce);

        /// Add several random observations
        makeRandomObservations(nonce, uint256(15));

        /// Expect the nextObsIndex to be 15 places away from the beginning
        /// Confirm by ensuring the last observation is at that index minus 1 and is the current price
        assertEq(price.nextObsIndex(), uint32(15));
        assertEq(price.observations(14), price.getCurrentPrice());

        /// Manually calculate the expected moving average
        uint256 expMovingAverage;
        uint256 numObs = uint256(price.numObservations());
        for (uint256 i; i < numObs; ++i) {
            expMovingAverage += price.observations(i);
        }
        expMovingAverage /= numObs;

        /// Check that the moving average was updated correctly
        assertEq(expMovingAverage, price.getMovingAverage());
    }

    // =========  VIEW TESTS ========= //

    /// DONE
    /// [X] KEYCODE
    /// [X] ROLES
    /// [X] getCurrentPrice
    /// [X] getLastPrice
    /// [X] getMovingAverage
    /// [X] getTargetPrice
    /// [X] cannot get prices before initialization

    function testCorrectness_KEYCODE() public {
        assertEq("PRICE", Keycode.unwrap(price.KEYCODE()));
    }

    function testCorrectness_getCurrentPrice(uint8 nonce) public {
        // Initialize price module
        initializePrice(nonce);

        // Get the current price from the price module
        uint256 currentPrice = price.getCurrentPrice();

        // Get the current price from the price module
        uint256 ohmEthPrice = uint256(ohmEthPriceFeed.latestAnswer());
        uint256 reserveEthPrice = uint256(reserveEthPriceFeed.latestAnswer());

        // Check that the current price is correct
        assertEq(
            currentPrice,
            ohmEthPrice.mulDiv(
                10**(reserveEthPriceFeed.decimals() + price.decimals()),
                reserveEthPrice * 10**ohmEthPriceFeed.decimals()
            )
        );

        // Set the price on the feeds to be 0 and expect the call to revert
        ohmEthPriceFeed.setLatestAnswer(0);

        bytes memory err = abi.encodeWithSignature(
            "Price_BadFeed(address)",
            address(ohmEthPriceFeed)
        );
        vm.expectRevert(err);
        price.getCurrentPrice();

        ohmEthPriceFeed.setLatestAnswer(1e18);
        reserveEthPriceFeed.setLatestAnswer(0);

        err = abi.encodeWithSignature("Price_BadFeed(address)", address(reserveEthPriceFeed));
        vm.expectRevert(err);
        price.getCurrentPrice();

        reserveEthPriceFeed.setLatestAnswer(1e18);

        // Set the timestamp on each feed to before the acceptable window and expect the call to revert
        ohmEthPriceFeed.setTimestamp(block.timestamp - uint256(price.ohmEthUpdateThreshold()) - 1);

        err = abi.encodeWithSignature("Price_BadFeed(address)", address(ohmEthPriceFeed));
        vm.expectRevert(err);
        price.getCurrentPrice();

        ohmEthPriceFeed.setTimestamp(block.timestamp);

        reserveEthPriceFeed.setTimestamp(
            block.timestamp - uint256(price.reserveEthUpdateThreshold()) - 1
        );

        err = abi.encodeWithSignature("Price_BadFeed(address)", address(reserveEthPriceFeed));
        vm.expectRevert(err);
        price.getCurrentPrice();

        reserveEthPriceFeed.setTimestamp(block.timestamp);

        // Set the round Id on each feed ahead of the answered in round id and expect the call to revert
        ohmEthPriceFeed.setRoundId(1);
        err = abi.encodeWithSignature("Price_BadFeed(address)", address(ohmEthPriceFeed));
        vm.expectRevert(err);
        price.getCurrentPrice();

        ohmEthPriceFeed.setRoundId(0);

        reserveEthPriceFeed.setRoundId(1);
        err = abi.encodeWithSignature("Price_BadFeed(address)", address(reserveEthPriceFeed));
        vm.expectRevert(err);
        price.getCurrentPrice();

        reserveEthPriceFeed.setRoundId(0);
    }

    function testCorrectness_getLastPrice(uint8 nonce) public {
        /// Initialize price module
        initializePrice(nonce);

        /// Get the last price from the price module
        uint256 lastPrice = price.getLastPrice();

        /// Check that it returns the last observation in the observations array
        uint32 numObservations = price.numObservations();
        uint32 nextObsIndex = price.nextObsIndex();
        uint32 lastIndex = nextObsIndex == 0 ? numObservations - 1 : nextObsIndex - 1;
        assertEq(lastPrice, price.observations(lastIndex));
    }

    function testCorrectness_getMovingAverage(uint8 nonce) public {
        /// Initialize price module
        initializePrice(nonce);

        /// Get the moving average from the price module
        uint256 movingAverage = price.getMovingAverage();

        /// Calculate the expected moving average
        uint256 expMovingAverage;
        for (uint256 i; i < price.numObservations(); ++i) {
            expMovingAverage += price.observations(i);
        }
        expMovingAverage /= price.numObservations();

        /// Check that the moving average is correct (use a range since the simpler method missing a little on rounding)
        assertGt(expMovingAverage, movingAverage.mulDiv(999, 1000));
        assertLt(expMovingAverage, movingAverage.mulDiv(1001, 1000));
    }

    function testCorrectness_getTargetPrice(uint8 nonce) public {
        /// Initialize price module
        initializePrice(nonce);

        /// Get the target price from the price module
        uint256 targetPrice = price.getTargetPrice();

        /// Calculate the expected target price
        uint256 movingAverage = price.getMovingAverage();
        uint256 minimumPrice = price.minimumTargetPrice();
        uint256 expTargetPrice = movingAverage > minimumPrice ? movingAverage : minimumPrice;

        /// Check that the target price is correct (use a range since the simpler method missing a little on rounding)
        assertGt(expTargetPrice, targetPrice.mulDiv(999, 1000));
        assertLt(expTargetPrice, targetPrice.mulDiv(1001, 1000));
    }

    function testCorrectness_viewsRevertBeforeInitialization() public {
        /// Check that the views revert before initialization
        bytes memory err = abi.encodeWithSignature("Price_NotInitialized()");
        vm.expectRevert(err);
        price.getCurrentPrice();

        vm.expectRevert(err);
        price.getLastPrice();

        vm.expectRevert(err);
        price.getMovingAverage();

        vm.expectRevert(err);
        price.getTargetPrice();
    }

    // =========  ADMIN TESTS ========= //

    /// DONE
    /// [X] initialize the moving average with a set of observations and last observation time
    /// [X] no observations exist before initialization
    /// [X] cannot initialize with invalid params
    /// [X] change moving average duration (shorter than current)
    /// [X] change moving average duration (longer than current)
    /// [X] cannot change moving average duration with invalid params
    /// [X] change observation frequency
    /// [X] cannot change observation frequency with invalid params
    /// [X] change price feed update thresholds
    /// [X] change minimum target price

    function testCorrectness_initialize(uint8 nonce) public {
        /// Check that the module is not initialized
        assertTrue(!price.initialized());

        /// Initialize price module
        initializePrice(nonce);

        /// Check the the module is initialized
        assertTrue(price.initialized());

        /// Check that the observations array is filled with the correct number of observations
        /// Do so by ensuring the last observation is at the right index and is the current price
        uint256 numObservations = uint256(price.numObservations());
        assertEq(price.observations(numObservations - 1), price.getCurrentPrice());

        /// Check that the last observation time is set to the current time
        assertEq(price.lastObservationTime(), block.timestamp);
    }

    function testCorrectness_cannotReinitialize(uint8 nonce) public {
        /// Check that the module is not initialized
        assertTrue(!price.initialized());

        /// Initialize price module
        initializePrice(nonce);

        /// Check the the module is initialized
        assertTrue(price.initialized());

        uint256[] memory observations = new uint256[](price.numObservations());
        vm.expectRevert(abi.encodeWithSignature("Price_AlreadyInitialized()"));
        vm.prank(writer);
        price.initialize(observations, uint48(block.timestamp));
    }

    function testCorrectness_noObservationsBeforeInitialized() public {
        /// Check that the oberservations array is empty (all values initialized to 0)
        uint256 numObservations = uint256(price.numObservations());
        uint256 zero = uint256(0);
        for (uint256 i; i < numObservations; ++i) {
            assertEq(price.observations(i), zero);
        }
    }

    function testCorrectness_cannotInitializeWithInvalidParams() public {
        /// Check that the module is not initialized
        assertTrue(!price.initialized());

        /// Try to initialize price module with invalid params
        bytes memory err = abi.encodeWithSignature("Price_InvalidParams()");

        /// Case 1: array has fewer observations than numObservations
        uint256[] memory observations = new uint256[](10);
        vm.startPrank(writer);
        vm.expectRevert(err);
        price.initialize(observations, uint48(block.timestamp));

        /// Case 2: array has more observations than numObservations
        observations = new uint256[](30);
        vm.expectRevert(err);
        price.initialize(observations, uint48(block.timestamp));

        /// Case 3: last observation time is in the future
        observations = new uint256[](21);
        vm.expectRevert(err);
        price.initialize(observations, uint48(block.timestamp + 1));
        vm.stopPrank();
    }

    function testCorrectness_changeMovingAverageDuration(uint8 nonce) public {
        /// Initialize price module
        initializePrice(nonce);

        /// Change from a seven day window to a ten day window and same frequency window
        vm.prank(writer);
        price.changeMovingAverageDuration(uint48(10 days));

        /// Check the the module is not still initialized
        assertTrue(!price.initialized());
        assertEq(price.lastObservationTime(), uint48(0));

        /// Re-initialize price module
        initializePrice(nonce);

        /// Check that the window variables and moving average are updated correctly
        assertEq(price.numObservations(), uint48(30));
        assertEq(price.movingAverageDuration(), uint48(10 days));
    }

    function testCorrectness_cannotChangeMovingAverageDurationWithInvalidParams() public {
        /// Try to change moving average duration with invalid params
        bytes memory err = abi.encodeWithSignature("Price_InvalidParams()");

        vm.startPrank(writer);
        /// Case 1: moving average duration is set to zero
        vm.expectRevert(err);
        price.changeMovingAverageDuration(uint48(0));

        /// Case 2: moving average duration not a multiple of observation frequency
        vm.expectRevert(err);
        price.changeMovingAverageDuration(uint48(20 hours));
        vm.stopPrank();
    }

    function testCorrectness_changeObservationFrequency(uint8 nonce) public {
        /// Initialize price module
        initializePrice(nonce);

        /// Change observation frequency to a different value (smaller than current)
        vm.prank(writer);
        price.changeObservationFrequency(uint48(4 hours));

        /// Check the the module is not still initialized
        assertTrue(!price.initialized());

        /// Re-initialize price module
        initializePrice(nonce);

        /// Check that the window variables and moving average are updated correctly
        assertEq(price.numObservations(), uint48(42));
        assertEq(price.observationFrequency(), uint48(4 hours));

        /// Change observation frequency to a different value (larger than current)
        vm.prank(writer);
        price.changeObservationFrequency(uint48(12 hours));

        /// Check the the module is not still initialized
        assertTrue(!price.initialized());

        /// Re-initialize price module
        initializePrice(nonce);

        /// Check that the window variables and moving average are updated correctly
        assertEq(price.numObservations(), uint48(14));
        assertEq(price.observationFrequency(), uint48(12 hours));
    }

    function testCorrectness_cannotChangeObservationFrequencyWithInvalidParams() public {
        /// Try to change moving average duration with invalid params
        bytes memory err = abi.encodeWithSignature("Price_InvalidParams()");

        vm.startPrank(writer);
        /// Case 1: observation frequency is set to zero
        vm.expectRevert(err);
        price.changeObservationFrequency(uint48(0));

        /// Case 2: moving average duration not a multiple of observation frequency
        vm.expectRevert(err);
        price.changeObservationFrequency(uint48(23 hours));
        vm.stopPrank();
    }

    function testCorrectness_changeUpdateThresholds(uint8 nonce) public {
        /// Initialize price module
        initializePrice(nonce);

        /// Check that the price feed errors after the existing update threshold is exceeded
        uint48 startOhmEthThreshold = price.ohmEthUpdateThreshold();
        vm.warp(block.timestamp + startOhmEthThreshold + 1);
        vm.expectRevert(
            abi.encodeWithSignature("Price_BadFeed(address)", address(ohmEthPriceFeed))
        );
        price.getCurrentPrice();

        /// Roll back time
        vm.warp(block.timestamp - startOhmEthThreshold - 1);

        /// Change update thresholds to a different value (larger than current)
        vm.prank(writer);
        price.changeUpdateThresholds(uint48(36 hours), uint48(36 hours));

        /// Check that the update thresholds are updated correctly
        assertEq(price.ohmEthUpdateThreshold(), uint48(36 hours));
        assertEq(price.reserveEthUpdateThreshold(), uint48(36 hours));

        /// Check that the price feed doesn't error at the old threshold
        vm.warp(block.timestamp + startOhmEthThreshold + 1);
        price.getCurrentPrice();

        /// Roll time past new threshold
        vm.warp(block.timestamp - startOhmEthThreshold + price.ohmEthUpdateThreshold());
        vm.expectRevert(
            abi.encodeWithSignature("Price_BadFeed(address)", address(ohmEthPriceFeed))
        );
        price.getCurrentPrice();
    }

    function testCorrectness_changeMinimumTargetPrice(uint8 nonce, uint256 newValue) public {
        /// Initialize price module
        initializePrice(nonce);

        /// Change minimum target price to a different value
        vm.prank(writer);
        price.changeMinimumTargetPrice(newValue);

        /// Check that the minimum target price is updated correctly
        assertEq(price.minimumTargetPrice(), newValue);
    }

    function testCorrectness_onlyPermittedPoliciesCanCallAdminFunctions() public {
        /// Try to call functions as a non-permitted policy with correct params and expect reverts
        bytes memory err = abi.encodeWithSelector(
            Module.Module_PolicyNotPermitted.selector,
            address(this)
        );

        /// initialize
        uint256[] memory obs = new uint256[](21);
        uint48 lastObTime = uint48(block.timestamp - 1);
        vm.expectRevert(err);
        price.initialize(obs, lastObTime);

        /// changeMovingAverageDuration
        vm.expectRevert(err);
        price.changeMovingAverageDuration(uint48(5 days));

        /// changeObservationFrequency
        vm.expectRevert(err);
        price.changeObservationFrequency(uint48(4 hours));

        /// changeUpdateThresholds
        vm.expectRevert(err);
        price.changeUpdateThresholds(uint48(36 hours), uint48(36 hours));

        /// changeMinimumTargetPrice
        vm.expectRevert(err);
        price.changeMinimumTargetPrice(1e18);
    }
}
