// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {DSTest} from "ds-test/test.sol";
import {UserFactory} from "test-utils/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FullMath} from "libraries/FullMath.sol";

import {MockPriceFeed} from "../mocks/MockPriceFeed.sol";
import {MockModuleWriter} from "../mocks/MockModuleWriter.sol";

import {OlympusPrice} from "modules/PRICE.sol";
import "src/Kernel.sol";

contract PriceTest is DSTest {
    using FullMath for uint256;

    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal reserveEthPriceFeed;
    MockERC20 internal ohm;
    MockERC20 internal reserve;

    Kernel internal kernel;
    OlympusPrice internal price;

    MockModuleWriter internal writer;
    OlympusPrice internal priceWriter;

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
                reserveEthPriceFeed, // AggregatorInterface reserveEthPriceFeed_,
                uint48(8 hours), // uint32 observationFrequency_,
                uint48(7 days) // uint32 movingAverageDuration_,
            );

            /// Deploy mock module writer
            writer = new MockModuleWriter(kernel, price);
            priceWriter = OlympusPrice(address(writer));
        }

        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(price));
            kernel.executeAction(Actions.ApprovePolicy, address(writer));
        }
    }

    /* ========== HELPER FUNCTIONS ========== */
    function initializePrice(uint8 nonce) internal {
        /// Assume that the reserveEth price feed is fixed at 0.0005 ETH = 1 Reserve
        reserveEthPriceFeed.setLatestAnswer(int256(5e14));
        uint256 reserveEthPrice = uint256(reserveEthPriceFeed.latestAnswer());

        /// Set ohmEth price to 0.01 ETH = 1 OHM initially
        int256 ohmEthPrice = int256(1e16);

        /// Set scaling value for calculations
        uint256 scale = 10 **
            (price.decimals() +
                reserveEthPriceFeed.decimals() -
                ohmEthPriceFeed.decimals());

        /// Calculate the number of observations and initialize the observation array
        uint48 observationFrequency = price.observationFrequency();
        uint48 movingAverageDuration = price.movingAverageDuration();
        uint256 numObservations = movingAverageDuration / observationFrequency;
        uint256[] memory observations = new uint256[](numObservations);

        /// Perform a random walk to initialize the observations
        int256 change; // percentage with two decimals
        for (uint256 i; i < numObservations; ++i) {
            /// Calculate a random percentage change from -10% to + 10% using the nonce and observation number
            change =
                int256(uint256(keccak256(abi.encodePacked(nonce, i)))) %
                int256(1000);

            /// Calculate the new ohmEth price
            ohmEthPrice =
                (ohmEthPrice * (CHANGE_DECIMALS + change)) /
                CHANGE_DECIMALS;

            /// Update price feed
            ohmEthPriceFeed.setLatestAnswer(ohmEthPrice);

            /// Get the current price from the price module and store in the observations array
            observations[i] = uint256(ohmEthPrice).mulDiv(
                scale,
                reserveEthPrice
            );
        }

        /// Initialize the price module with the observations
        priceWriter.initialize(observations, uint48(block.timestamp));
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
            change =
                int256(uint256(keccak256(abi.encodePacked(nonce, i)))) %
                int256(1000);

            /// Calculate the new ohmEth price
            ohmEthPrice =
                (ohmEthPrice * (CHANGE_DECIMALS + change)) /
                CHANGE_DECIMALS;

            /// Update price feed
            ohmEthPriceFeed.setLatestAnswer(ohmEthPrice);

            /// Call update moving average on the price module
            priceWriter.updateMovingAverage();

            /// Shift time forward by the observation frequency
            timeIncrease += observationFrequency;
            vm.warp(block.timestamp + timeIncrease);
        }
    }

    /* ========== UPDATE TESTS ========== */

    /// DONE
    /// [X] update moving average cannot be called before price initialization
    /// [X] update moving average
    /// [X] update moving average several times and expand observations

    function testCorrectness_cannotUpdateMovingAverageBeforeInitialization()
        public
    {
        bytes memory err = abi.encodeWithSignature("Price_NotInitialized()");

        vm.expectRevert(err);
        priceWriter.updateMovingAverage();
    }

    function testCorrectness_onlyPermittedPoliciesCanCallUpdateMovingAverage(
        uint8 nonce
    ) public {
        bytes memory err = abi.encodeWithSelector(
            Module_NotAuthorized.selector
        );

        /// Initialize price module
        initializePrice(nonce);

        /// Call updateMovingAverage with a non-approved address
        vm.expectRevert(err);
        vm.prank(address(0x0));
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

        /// Get the current moving average from the price module
        uint256 movingAverage = price.getMovingAverage();

        /// Calculate the expected moving average
        uint256 expMovingAverage;
        if (currentPrice > earliestPrice) {
            expMovingAverage =
                movingAverage +
                ((currentPrice - earliestPrice) / numObservations);
        } else {
            expMovingAverage =
                movingAverage -
                ((earliestPrice - currentPrice) / numObservations);
        }

        /// Update the moving average on the price module
        priceWriter.updateMovingAverage();

        /// Check that the moving average was updated correctly
        console.log(expMovingAverage);
        console.log(price.getMovingAverage());
        assertEq(expMovingAverage, price.getMovingAverage());
    }

    function testCorrectness_updateMovingAverageMultipleTimes(uint8 nonce)
        public
    {
        /// Initialize price module
        initializePrice(nonce);

        /// Add several random observations
        makeRandomObservations(nonce, uint256(15));

        /// Expect the observations array to have 15 more observations
        /// Confirm by ensuring the last observation is at that index and is the current price
        uint256 numObservations = uint256(price.numObservations());
        uint256 length = numObservations + 15;
        assertEq(price.observations(length - 1), price.getCurrentPrice());

        /// Manually calculate the expected moving average
        uint256 expMovingAverage;
        for (uint256 i = length - numObservations; i < length; ++i) {
            expMovingAverage += price.observations(i);
        }
        expMovingAverage /= numObservations;

        /// Check that the moving average was updated correctly (use a range to account for rounding between two methods)
        assertGt(expMovingAverage, price.getMovingAverage().mulDiv(999, 1000));
        assertLt(expMovingAverage, price.getMovingAverage().mulDiv(1001, 1000));
    }

    /* ========== VIEW TESTS ========== */

    /// DONE
    /// [X] KEYCODE
    /// [X] ROLES
    /// [X] getCurrentPrice
    /// [X] getLastPrice
    /// [X] getMovingAverage
    /// [X] cannot get prices before initialization

    function testCorrectness_KEYCODE() public {
        assertEq("PRICE", Kernel.Keycode.unwrap(price.KEYCODE()));
    }

    function testCorrectness_ROLES() public {
        assertEq("PRICE_Keeper", Kernel.Role.unwrap(price.ROLES()[0]));
        assertEq("PRICE_Guardian", Kernel.Role.unwrap(price.ROLES()[1]));
    }

    function testCorrectness_getCurrentPrice(uint8 nonce) public {
        /// Initialize price module
        initializePrice(nonce);

        /// Get the current price from the price module
        uint256 currentPrice = price.getCurrentPrice();

        /// Get the current price from the price module
        uint256 ohmEthPrice = uint256(ohmEthPriceFeed.latestAnswer());
        uint256 reserveEthPrice = uint256(reserveEthPriceFeed.latestAnswer());

        /// Check that the current price is correct
        assertEq(
            currentPrice,
            ohmEthPrice.mulDiv(
                10**(reserveEthPriceFeed.decimals() + price.decimals()),
                reserveEthPrice * 10**ohmEthPriceFeed.decimals()
            )
        );
    }

    function testCorrectness_getLastPrice(uint8 nonce) public {
        /// Initialize price module
        initializePrice(nonce);

        /// Get the last price from the price module
        uint256 lastPrice = price.getLastPrice();

        /// Check that it returns the last observation in the observations array
        assertEq(lastPrice, price.observations(price.numObservations() - 1));
    }

    function testCorrectness_getMovingAverage(uint8 nonce) public {
        /// Initialize price module
        initializePrice(nonce);

        /// Get the moving average from the price module
        uint256 movingAverage = price.getMovingAverage();

        /// Calculate the expected moving average
        uint256 expMovingAverage;
        for (uint256 i = 0; i < price.numObservations(); ++i) {
            expMovingAverage += price.observations(i);
        }
        expMovingAverage /= price.numObservations();

        /// Check that the moving average is correct (use a range since the simpler method missing a little on rounding)
        assertGt(expMovingAverage, movingAverage.mulDiv(999, 1000));
        assertLt(expMovingAverage, movingAverage.mulDiv(1001, 1000));
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
    }

    /* ========== ADMIN TESTS ========== */

    /// DONE
    /// [X] initialize the moving average with a set of observations and last observation time
    /// [X] no observations exist before initialization
    /// [X] cannot initialize with invalid params
    /// [X] change moving average duration (shorter than current)
    /// [X] change moving average duration (longer than current)
    /// [X] cannot change moving average duration with invalid params
    /// [X] change observation frequency
    /// [X] cannot change observation frequency with invalid params

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
        assertEq(
            price.observations(numObservations - 1),
            price.getCurrentPrice()
        );

        /// Check that the last observation time is set to the current time
        assertEq(price.lastObservationTime(), block.timestamp);
    }

    /// For some reason vm.expectRevert would not work here
    /// TODO: convert to vm.expectRevert
    function testFail_cannotReinitialize(uint8 nonce) public {
        /// Check that the module is not initialized
        assertTrue(!price.initialized());

        /// Initialize price module
        initializePrice(nonce);

        /// Check the the module is initialized
        assertTrue(price.initialized());

        initializePrice(nonce);
    }

    function testCorrectness_noObservationsBeforeInitialized() public {
        /// Check that the oberservations array is empty (all values initialized to 0)
        uint256 numObservations = uint256(price.numObservations());
        uint256 zero = uint256(0);
        for (uint256 i = 0; i < numObservations; ++i) {
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
        vm.expectRevert(err);
        priceWriter.initialize(observations, uint48(block.timestamp));

        /// Case 2: array has more observations than numObservations
        observations = new uint256[](30);
        vm.expectRevert(err);
        priceWriter.initialize(observations, uint48(block.timestamp));

        /// Case 3: last observation time is in the future
        observations = new uint256[](21);
        vm.expectRevert(err);
        priceWriter.initialize(observations, uint48(block.timestamp + 1));
    }

    function testCorrectness_changeMovingAverageDurationShorter(uint8 nonce)
        public
    {
        /// Initialize price module
        initializePrice(nonce);

        /// Calculate expected moving average based on existing observations
        uint256 expMovingAverage;
        uint256 length = uint256(price.numObservations());
        for (uint256 i = length - 15; i < length; ++i) {
            expMovingAverage += price.observations(i);
        }
        expMovingAverage /= 15;

        /// Change from a seven day window to a five day window
        priceWriter.changeMovingAverageDuration(uint48(5 days));

        /// Check the the module is still initialized
        assertTrue(price.initialized());

        /// Check that the window variables and moving average are updated correctly
        assertEq(price.numObservations(), uint48(15));
        assertEq(price.movingAverageDuration(), uint48(5 days));
        assertEq(price.getMovingAverage(), expMovingAverage);
    }

    function testCorrectness_changeMovingAverageDurationLonger(uint8 nonce)
        public
    {
        /// Initialize price module
        initializePrice(nonce);

        /// Change from a seven day window to a ten day window and same frequency window
        priceWriter.changeMovingAverageDuration(uint48(10 days));

        /// Check the the module is not still initialized
        assertTrue(!price.initialized());

        /// Re-initialize price module
        initializePrice(nonce);

        /// Check that the window variables and moving average are updated correctly
        assertEq(price.numObservations(), uint48(30));
        assertEq(price.movingAverageDuration(), uint48(10 days));
    }

    function testCorrectness_cannotChangeMovingAverageDurationWithInvalidParams()
        public
    {
        /// Try to change moving average duration with invalid params
        bytes memory err = abi.encodeWithSignature("Price_InvalidParams()");

        /// Case 1: moving average duration is set to zero
        vm.expectRevert(err);
        priceWriter.changeMovingAverageDuration(uint48(0));

        /// Case 2: moving average duration not a multiple of observation frequency
        vm.expectRevert(err);
        priceWriter.changeMovingAverageDuration(uint48(20 hours));
    }

    function testCorrectness_changeObservationFrequency(uint8 nonce) public {
        /// Initialize price module
        initializePrice(nonce);

        /// Change observation frequency to a different value (smaller than current)
        priceWriter.changeObservationFrequency(uint48(4 hours));

        /// Check the the module is not still initialized
        assertTrue(!price.initialized());

        /// Re-initialize price module
        initializePrice(nonce);

        /// Check that the window variables and moving average are updated correctly
        assertEq(price.numObservations(), uint48(42));
        assertEq(price.observationFrequency(), uint48(4 hours));

        /// Change observation frequency to a different value (larger than current)
        priceWriter.changeObservationFrequency(uint48(12 hours));

        /// Check the the module is not still initialized
        assertTrue(!price.initialized());

        /// Re-initialize price module
        initializePrice(nonce);

        /// Check that the window variables and moving average are updated correctly
        assertEq(price.numObservations(), uint48(14));
        assertEq(price.observationFrequency(), uint48(12 hours));
    }

    function testCorrectness_cannotChangeObservationFrequencyWithInvalidParams()
        public
    {
        /// Try to change moving average duration with invalid params
        bytes memory err = abi.encodeWithSignature("Price_InvalidParams()");

        /// Case 1: observation frequency is set to zero
        vm.expectRevert(err);
        priceWriter.changeObservationFrequency(uint48(0));

        /// Case 2: moving average duration not a multiple of observation frequency
        vm.expectRevert(err);
        priceWriter.changeObservationFrequency(uint48(23 hours));
    }

    function testCorrectness_onlyPermittedPoliciesCanCallAdminFunctions()
        public
    {
        /// Try to call functions as a non-permitted policy with correct params and expect reverts
        bytes memory err = abi.encodeWithSelector(
            Module_NotAuthorized.selector
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
    }
}
