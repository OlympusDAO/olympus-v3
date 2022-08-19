// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FullMath} from "libraries/FullMath.sol";

import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";

import "src/Kernel.sol";
import {OlympusPrice} from "modules/PRICE.sol";
import {OlympusPriceConfig} from "policies/PriceConfig.sol";

contract PriceConfigTest is Test {
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address internal bob;
    address internal carol;
    address internal guardian;

    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal reserveEthPriceFeed;
    MockERC20 internal ohm;
    MockERC20 internal reserve;

    Kernel internal kernel;
    OlympusPrice internal price;
    OlympusPriceConfig internal priceConfig;

    int256 internal constant CHANGE_DECIMALS = 1e4;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            address[] memory users = userCreator.create(4);
            alice = users[0];
            bob = users[1];
            carol = users[2];
            guardian = users[3];
        }

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

            /// Deploy price config policy
            priceConfig = new OlympusPriceConfig(kernel);
        }

        {
            /// Initialize system and kernel

            /// Install modules
            kernel.executeAction(Actions.InstallModule, address(price));

            /// Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(priceConfig));
        }

        {
            /// Configure access control

            /// PriceConfig roles
            kernel.grantRole(toRole("price_admin"), guardian);
        }

        {
            /// Initialize timestamps on the mock price feeds
            ohmEthPriceFeed.setTimestamp(block.timestamp);
            reserveEthPriceFeed.setTimestamp(block.timestamp);
        }
    }

    /* ========== HELPER FUNCTIONS ========== */
    function getObs(uint8 nonce) internal returns (uint256[] memory) {
        /// Assume that the reserveEth price feed is fixed at 0.0005 ETH = 1 Reserve
        reserveEthPriceFeed.setLatestAnswer(int256(5e14));
        uint256 reserveEthPrice = uint256(reserveEthPriceFeed.latestAnswer());

        /// Set ohmEth price to 0.01 ETH = 1 OHM initially
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

        return observations;
    }

    /* ========== ADMIN TESTS ========== */

    /// DONE
    /// [X] initialize
    /// [X] change moving average duration
    /// [X] change observation frequency
    /// [X] only authorized addresses can call admin functions

    function testCorrectness_initialize(uint8 nonce) public {
        /// Check that the module is not initialized
        assertTrue(!price.initialized());

        /// Initialize price module as the guardian using the price config policy
        uint256[] memory obs = getObs(nonce);
        vm.prank(guardian);
        priceConfig.initialize(obs, uint48(block.timestamp));

        /// Check the the module is initialized
        assertTrue(price.initialized());

        /// Check that the observations array is filled with the correct number of observations
        /// Do so by ensuring the last observation is at the right index and is the current price
        uint256 numObservations = uint256(price.numObservations());
        assertEq(price.observations(numObservations - 1), price.getCurrentPrice());

        /// Check that the last observation time is set to the current time
        assertEq(price.lastObservationTime(), block.timestamp);
    }

    function testCorrectness_noObservationsBeforeInitialized() public {
        /// Check that the oberservations array is empty (all values initialized to 0)
        uint256 numObservations = uint256(price.numObservations());
        uint256 zero = uint256(0);
        for (uint256 i; i < numObservations; ++i) {
            assertEq(price.observations(i), zero);
        }
    }

    function testCorrectness_changeMovingAverageDuration(uint8 nonce) public {
        /// Initialize price module
        uint256[] memory obs = getObs(nonce);
        vm.prank(guardian);
        priceConfig.initialize(obs, uint48(block.timestamp));

        /// Change from a seven day window to a ten day window and same frequency window
        vm.prank(guardian);
        priceConfig.changeMovingAverageDuration(uint48(10 days));

        /// Check the the module is not still initialized
        assertTrue(!price.initialized());
        assertEq(price.lastObservationTime(), uint48(0));

        /// Re-initialize price module
        obs = getObs(nonce);
        vm.prank(guardian);
        priceConfig.initialize(obs, uint48(block.timestamp));

        /// Check that the window variables and moving average are updated correctly
        assertEq(price.numObservations(), uint48(30));
        assertEq(price.movingAverageDuration(), uint48(10 days));
    }

    function testCorrectness_changeObservationFrequency(uint8 nonce) public {
        /// Initialize price module
        uint256[] memory obs = getObs(nonce);
        vm.prank(guardian);
        priceConfig.initialize(obs, uint48(block.timestamp));

        /// Change observation frequency to a different value (smaller than current)
        vm.prank(guardian);
        priceConfig.changeObservationFrequency(uint48(4 hours));

        /// Check the the module is not still initialized
        assertTrue(!price.initialized());

        /// Re-initialize price module
        obs = getObs(nonce);
        vm.prank(guardian);
        priceConfig.initialize(obs, uint48(block.timestamp));

        /// Check that the window variables and moving average are updated correctly
        assertEq(price.numObservations(), uint48(42));
        assertEq(price.observationFrequency(), uint48(4 hours));

        /// Change observation frequency to a different value (larger than current)
        vm.prank(guardian);
        priceConfig.changeObservationFrequency(uint48(12 hours));

        /// Check the the module is not still initialized
        assertTrue(!price.initialized());

        /// Re-initialize price module
        obs = getObs(nonce);
        vm.prank(guardian);
        priceConfig.initialize(obs, uint48(block.timestamp));

        /// Check that the window variables and moving average are updated correctly
        assertEq(price.numObservations(), uint48(14));
        assertEq(price.observationFrequency(), uint48(12 hours));
    }

    function testCorrectness_onlyAuthorizedCanCallAdminFunctions() public {
        /// Try to call functions as a non-permitted policy with correct params and expect reverts
        bytes memory err = abi.encodeWithSelector(Policy_OnlyRole.selector, toRole("price_admin"));

        /// initialize
        uint256[] memory obs = new uint256[](21);
        uint48 lastObTime = uint48(block.timestamp - 1);
        vm.expectRevert(err);
        priceConfig.initialize(obs, lastObTime);

        /// changeMovingAverageDuration
        vm.expectRevert(err);
        priceConfig.changeMovingAverageDuration(uint48(5 days));

        /// changeObservationFrequency
        vm.expectRevert(err);
        priceConfig.changeObservationFrequency(uint48(4 hours));
    }
}
