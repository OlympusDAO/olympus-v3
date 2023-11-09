// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FullMath} from "libraries/FullMath.sol";

import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";

import {OlympusPriceConfig} from "policies/RBS/PriceConfig.sol";
import {OlympusPrice} from "modules/PRICE/OlympusPrice.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import "src/Kernel.sol";

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
    OlympusPrice internal PRICE;
    OlympusRoles internal ROLES;
    OlympusPriceConfig internal priceConfig;
    RolesAdmin internal rolesAdmin;

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

            /// Deploy PRICE module
            PRICE = new OlympusPrice(
                kernel,
                ohmEthPriceFeed, // AggregatorInterface ohmEthPriceFeed_,
                uint48(24 hours), // uint32 ohmEthUpdateThreshold_,
                reserveEthPriceFeed, // AggregatorInterface reserveEthPriceFeed_,
                uint48(24 hours), // uint32 reserveEthUpdateThreshold_,
                uint48(8 hours), // uint32 observationFrequency_,
                uint48(7 days), // uint32 movingAverageDuration_,
                10 * 1e18 // uint256 minimumTargetPrice_
            );

            ROLES = new OlympusRoles(kernel);

            /// Deploy PRICE config policy
            priceConfig = new OlympusPriceConfig(kernel);

            /// Deploy rolesAdmin
            rolesAdmin = new RolesAdmin(kernel);
        }

        {
            /// Initialize system and kernel

            /// Install modules
            kernel.executeAction(Actions.InstallModule, address(PRICE));
            kernel.executeAction(Actions.InstallModule, address(ROLES));

            /// Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(priceConfig));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }

        {
            /// Configure access control

            /// PriceConfig ROLES
            rolesAdmin.grantRole("price_admin", guardian);
        }

        {
            /// Initialize timestamps on the mock PRICE feeds
            ohmEthPriceFeed.setTimestamp(block.timestamp);
            reserveEthPriceFeed.setTimestamp(block.timestamp);
        }
    }

    // ======== SETUP DEPENDENCIES ======= //

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](2);
        expectedDeps[0] = toKeycode("PRICE");
        expectedDeps[1] = toKeycode("ROLES");

        Keycode[] memory deps = priceConfig.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](5);
        Keycode PRICE_KEYCODE = toKeycode("PRICE");
        expectedPerms[0] = Permissions(PRICE_KEYCODE, PRICE.initialize.selector);
        expectedPerms[1] = Permissions(PRICE_KEYCODE, PRICE.changeMovingAverageDuration.selector);
        expectedPerms[2] = Permissions(PRICE_KEYCODE, PRICE.changeObservationFrequency.selector);
        expectedPerms[3] = Permissions(PRICE_KEYCODE, PRICE.changeUpdateThresholds.selector);
        expectedPerms[4] = Permissions(PRICE_KEYCODE, PRICE.changeMinimumTargetPrice.selector);
        Permissions[] memory perms = priceConfig.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    // =========  HELPER FUNCTIONS ========= //

    function getObs(uint8 nonce) internal returns (uint256[] memory) {
        /// Assume that the reserveEth PRICE feed is fixed at 0.0005 ETH = 1 Reserve
        reserveEthPriceFeed.setLatestAnswer(int256(5e14));
        uint256 reserveEthPrice = uint256(reserveEthPriceFeed.latestAnswer());

        /// Set ohmEth PRICE to 0.01 ETH = 1 OHM initially
        int256 ohmEthPrice = int256(1e16);

        /// Set scaling value for calculations
        uint256 scale = 10 **
            (PRICE.decimals() + reserveEthPriceFeed.decimals() - ohmEthPriceFeed.decimals());

        /// Calculate the number of observations and initialize the observation array
        uint48 observationFrequency = PRICE.observationFrequency();
        uint48 movingAverageDuration = PRICE.movingAverageDuration();
        uint256 numObservations = movingAverageDuration / observationFrequency;
        uint256[] memory observations = new uint256[](numObservations);

        /// Perform a random walk to initialize the observations
        int256 change; // percentage with two decimals
        for (uint256 i; i < numObservations; ++i) {
            /// Calculate a random percentage change from -10% to + 10% using the nonce and observation number
            change = int256(uint256(keccak256(abi.encodePacked(nonce, i)))) % int256(1000);

            /// Calculate the new ohmEth PRICE
            ohmEthPrice = (ohmEthPrice * (CHANGE_DECIMALS + change)) / CHANGE_DECIMALS;

            /// Update PRICE feed
            ohmEthPriceFeed.setLatestAnswer(ohmEthPrice);

            /// Get the current PRICE from the PRICE module and store in the observations array
            observations[i] = uint256(ohmEthPrice).mulDiv(scale, reserveEthPrice);
        }

        return observations;
    }

    // =========  ADMIN TESTS ========= //

    /// DONE
    /// [X] initialize
    /// [X] change moving average duration
    /// [X] change observation frequency
    /// [X] change PRICE feed update thresholds
    /// [X] only authorized addresses can call admin functions

    function testCorrectness_initialize(uint8 nonce) public {
        /// Check that the module is not initialized
        assertTrue(!PRICE.initialized());

        /// Initialize PRICE module as the guardian using the PRICE config policy
        uint256[] memory obs = getObs(nonce);
        vm.prank(guardian);
        priceConfig.initialize(obs, uint48(block.timestamp));

        /// Check the the module is initialized
        assertTrue(PRICE.initialized());

        /// Check that the observations array is filled with the correct number of observations
        /// Do so by ensuring the last observation is at the right index and is the current PRICE
        uint256 numObservations = uint256(PRICE.numObservations());
        assertEq(PRICE.observations(numObservations - 1), PRICE.getCurrentPrice());

        /// Check that the last observation time is set to the current time
        assertEq(PRICE.lastObservationTime(), block.timestamp);
    }

    function testCorrectness_noObservationsBeforeInitialized() public {
        /// Check that the oberservations array is empty (all values initialized to 0)
        uint256 numObservations = uint256(PRICE.numObservations());
        uint256 zero = uint256(0);
        for (uint256 i; i < numObservations; ++i) {
            assertEq(PRICE.observations(i), zero);
        }
    }

    function testCorrectness_changeMovingAverageDuration(uint8 nonce) public {
        /// Initialize PRICE module
        uint256[] memory obs = getObs(nonce);
        vm.prank(guardian);
        priceConfig.initialize(obs, uint48(block.timestamp));

        /// Change from a seven day window to a ten day window and same frequency window
        vm.prank(guardian);
        priceConfig.changeMovingAverageDuration(uint48(10 days));

        /// Check the the module is not still initialized
        assertTrue(!PRICE.initialized());
        assertEq(PRICE.lastObservationTime(), uint48(0));

        /// Re-initialize PRICE module
        obs = getObs(nonce);
        vm.prank(guardian);
        priceConfig.initialize(obs, uint48(block.timestamp));

        /// Check that the window variables and moving average are updated correctly
        assertEq(PRICE.numObservations(), uint48(30));
        assertEq(PRICE.movingAverageDuration(), uint48(10 days));
    }

    function testCorrectness_changeObservationFrequency(uint8 nonce) public {
        /// Initialize PRICE module
        uint256[] memory obs = getObs(nonce);
        vm.prank(guardian);
        priceConfig.initialize(obs, uint48(block.timestamp));

        /// Change observation frequency to a different value (smaller than current)
        vm.prank(guardian);
        priceConfig.changeObservationFrequency(uint48(4 hours));

        /// Check the the module is not still initialized
        assertTrue(!PRICE.initialized());

        /// Re-initialize PRICE module
        obs = getObs(nonce);
        vm.prank(guardian);
        priceConfig.initialize(obs, uint48(block.timestamp));

        /// Check that the window variables and moving average are updated correctly
        assertEq(PRICE.numObservations(), uint48(42));
        assertEq(PRICE.observationFrequency(), uint48(4 hours));

        /// Change observation frequency to a different value (larger than current)
        vm.prank(guardian);
        priceConfig.changeObservationFrequency(uint48(12 hours));

        /// Check the the module is not still initialized
        assertTrue(!PRICE.initialized());

        /// Re-initialize PRICE module
        obs = getObs(nonce);
        vm.prank(guardian);
        priceConfig.initialize(obs, uint48(block.timestamp));

        /// Check that the window variables and moving average are updated correctly
        assertEq(PRICE.numObservations(), uint48(14));
        assertEq(PRICE.observationFrequency(), uint48(12 hours));
    }

    function testCorrectness_changeUpdateThresholds(uint8 nonce) public {
        /// Initialize PRICE module
        uint256[] memory obs = getObs(nonce);
        vm.prank(guardian);
        priceConfig.initialize(obs, uint48(block.timestamp));

        /// Check that the PRICE feed errors after the existing update threshold is exceeded
        uint48 startOhmEthThreshold = PRICE.ohmEthUpdateThreshold();
        vm.warp(block.timestamp + startOhmEthThreshold + 1);
        vm.expectRevert(
            abi.encodeWithSignature("Price_BadFeed(address)", address(ohmEthPriceFeed))
        );
        PRICE.getCurrentPrice();

        /// Roll back time
        vm.warp(block.timestamp - startOhmEthThreshold - 1);

        /// Change update thresholds to a different value (larger than current)
        vm.prank(guardian);
        priceConfig.changeUpdateThresholds(uint48(36 hours), uint48(36 hours));

        /// Check that the update thresholds are updated correctly
        assertEq(PRICE.ohmEthUpdateThreshold(), uint48(36 hours));
        assertEq(PRICE.reserveEthUpdateThreshold(), uint48(36 hours));

        /// Check that the PRICE feed doesn't error at the old threshold
        vm.warp(block.timestamp + startOhmEthThreshold + 1);
        PRICE.getCurrentPrice();

        /// Roll time past new threshold
        vm.warp(block.timestamp - startOhmEthThreshold + PRICE.ohmEthUpdateThreshold());
        vm.expectRevert(
            abi.encodeWithSignature("Price_BadFeed(address)", address(ohmEthPriceFeed))
        );
        PRICE.getCurrentPrice();
    }

    function testCorrectness_changeMinimumTargetPrice(uint8 nonce, uint256 newValue) public {
        /// Initialize PRICE module
        uint256[] memory obs = getObs(nonce);
        vm.prank(guardian);
        priceConfig.initialize(obs, uint48(block.timestamp));

        /// Change minimum target PRICE to a different value (larger than current)
        vm.prank(guardian);
        priceConfig.changeMinimumTargetPrice(newValue);

        /// Check that the minimum target PRICE is updated correctly
        assertEq(PRICE.minimumTargetPrice(), newValue);
    }

    function testCorrectness_onlyAuthorizedCanCallAdminFunctions() public {
        /// Try to call functions as a non-permitted policy with correct params and expect reverts
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("price_admin")
        );

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

        /// changeUpdateThresholds
        vm.expectRevert(err);
        priceConfig.changeUpdateThresholds(uint48(12 hours), uint48(12 hours));
    }
}
