// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {FullMath} from "libraries/FullMath.sol";

import "src/Kernel.sol";
import {OlympusRange} from "modules/RANGE.sol";

contract RangeTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusRange;

    UserFactory public userCreator;
    address internal alice;
    address internal bob;
    address internal guardian;
    address internal policy;
    address internal heart;

    MockERC20 internal ohm;
    MockERC20 internal reserve;

    Kernel internal kernel;
    OlympusRange internal range;

    address internal writer;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            address[] memory users = userCreator.create(5);
            alice = users[0];
            bob = users[1];
            guardian = users[2];
            policy = users[3];
            heart = users[4];
        }

        {
            /// Deploy protocol mocks external to guidance
            ohm = new MockERC20("Olympus", "OHM", 9);
            reserve = new MockERC20("Reserve", "RSV", 18);
        }

        {
            /// Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            /// Deploy module
            range = new OlympusRange(
                kernel,
                [ERC20(ohm), ERC20(reserve)],
                [uint256(100), uint256(1000), uint256(2000)]
            );

            // Deploy mock module writer
            writer = range.generateGodmodeFixture(type(OlympusRange).name);
        }

        {
            /// Initialize system and kernel

            /// Install modules
            kernel.executeAction(Actions.InstallModule, address(range));

            /// Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(writer));
        }

        {
            /// Initialize variables on module
            vm.startPrank(writer);
            range.updatePrices(100 * 1e18);
            range.regenerate(true, 10_000_000 * 1e18);
            range.regenerate(false, 10_000_000 * 1e18);
            vm.stopPrank();
        }
    }

    /* ========== POLICY FUNCTION TESTS ========== */

    /// DONE
    /// [X] updateCapacity
    ///     [X] updating capacity above the threshold
    ///     [X] updating capacity below the threshold
    /// [X] updatePrices
    /// [X] regenerate
    /// [X] updateMarket
    ///     [X] updating with non-max market ID and positive capacity creates a cushion
    ///     [X] updating with max-market ID takes down a cushion and sets last market capacity to zero
    /// [X] setSpreads
    /// [X] setThresholdFactor
    /// [X] cannot set parameters with invalid params
    /// [X] only permitted policies can call these functions

    event WallUp(bool high, uint256 timestamp, uint256 capacity);
    event WallDown(bool high, uint256 timestamp, uint256 capacity);

    function testCorrectness_updateCapacity() public {
        /// Confirm that the capacities are initialiized
        assertEq(range.capacity(true), 10_000_000 * 1e18);
        assertEq(range.capacity(false), 10_000_000 * 1e18);

        /// Update the capacities without breaking the thresholds
        vm.startPrank(writer);
        range.updateCapacity(true, 9_000_000 * 1e18);
        range.updateCapacity(false, 8_000_000 * 1e18);
        vm.stopPrank();

        /// Check that the capacities are updated
        assertEq(range.capacity(true), 9_000_000 * 1e18);
        assertEq(range.capacity(false), 8_000_000 * 1e18);

        /// Confirm the range sides are active
        assertTrue(range.active(true));
        assertTrue(range.active(false));

        /// Update the capacities to below the threshold, expect events to emit, and the wall to be inactive
        vm.expectEmit(false, false, false, true);
        emit WallDown(true, block.timestamp, 10_000 * 1e18);
        vm.prank(writer);
        range.updateCapacity(true, 10_000 * 1e18);

        vm.expectEmit(false, false, false, true);
        emit WallDown(false, block.timestamp, 10_000 * 1e18);
        vm.prank(writer);
        range.updateCapacity(false, 10_000 * 1e18);

        /// Check that the sides are inactive and capacity is updated
        assertTrue(!range.active(true));
        assertTrue(!range.active(false));
        assertEq(range.capacity(true), 10_000 * 1e18);
        assertEq(range.capacity(false), 10_000 * 1e18);
    }

    function testCorrectness_updatePrices() public {
        /// Store the starting bands
        OlympusRange.Range memory startRange = range.range();

        /// Update the prices with a new moving average above the initial one
        vm.prank(writer);
        range.updatePrices(110 * 1e18);

        /// Check that the bands have updated
        assertGt(range.price(false, false), startRange.cushion.low.price);
        assertGt(range.price(true, false), startRange.wall.low.price);
        assertGt(range.price(false, true), startRange.cushion.high.price);
        assertGt(range.price(true, true), startRange.wall.high.price);

        /// Update prices with a new moving average below the initial one
        vm.prank(writer);
        range.updatePrices(90 * 1e18);

        /// Check that the bands have updated
        assertLt(range.price(false, false), startRange.cushion.low.price);
        assertLt(range.price(true, false), startRange.wall.low.price);
        assertLt(range.price(false, true), startRange.cushion.high.price);
        assertLt(range.price(true, true), startRange.wall.high.price);
    }

    function testCorrectness_regenerate() public {
        /// Confirm that the capacities and thresholds are set to initial values
        OlympusRange.Range memory startRange = range.range();
        assertEq(startRange.low.capacity, 10_000_000 * 1e18);
        assertEq(startRange.high.capacity, 10_000_000 * 1e18);
        assertEq(startRange.low.threshold, 100_000 * 1e18);
        assertEq(startRange.high.threshold, 100_000 * 1e18);

        /// Update capacities on both sides with lower values
        vm.startPrank(writer);
        range.updateCapacity(true, 9_000_000 * 1e18);
        range.updateCapacity(false, 8_000_000 * 1e18);
        vm.stopPrank();

        /// Regenerate each side of the range and confirm values are set to the regenerated values
        vm.expectEmit(false, false, false, true);
        emit WallUp(true, block.timestamp, 20_000_000 * 1e18);
        vm.prank(writer);
        range.regenerate(true, 20_000_000 * 1e18);

        vm.expectEmit(false, false, false, true);
        emit WallUp(false, block.timestamp, 20_000_000 * 1e18);
        vm.prank(writer);
        range.regenerate(false, 20_000_000 * 1e18);

        /// Check that the capacities and thresholds are set to the regenerated values
        OlympusRange.Range memory endRange = range.range();
        assertEq(endRange.low.capacity, 20_000_000 * 1e18);
        assertEq(endRange.high.capacity, 20_000_000 * 1e18);
        assertEq(endRange.low.threshold, 200_000 * 1e18);
        assertEq(endRange.high.threshold, 200_000 * 1e18);
    }

    event CushionUp(bool high, uint256 timestamp, uint256 capacity);
    event CushionDown(bool high, uint256 timestamp);

    function testCorrectness_updateMarket() public {
        /// Confirm that there is no market set for each side (max value) to start
        assertEq(range.market(false), type(uint256).max);
        assertEq(range.market(true), type(uint256).max);

        /// Update the low side of the range with a new market deployed
        vm.expectEmit(false, false, false, true);
        emit CushionUp(false, block.timestamp, 2_000_000 * 1e18);
        vm.prank(writer);
        range.updateMarket(false, 2, 2_000_000 * 1e18);

        /// Check that the market is updated
        assertEq(range.market(false), 2);

        /// Take down the market that was deployed
        vm.expectEmit(false, false, false, true);
        emit CushionDown(false, block.timestamp);
        vm.prank(writer);
        range.updateMarket(false, type(uint256).max, 0);

        /// Check that the market is updated
        assertEq(range.market(false), type(uint256).max);

        /// Update the high side of the range with a new market deployed
        vm.expectEmit(false, false, false, true);
        emit CushionUp(true, block.timestamp, 1_000_000 * 1e18);
        vm.prank(writer);
        range.updateMarket(true, 1, 1_000_000 * 1e18);

        /// Check that the market is updated
        assertEq(range.market(true), 1);

        /// Take down the market that was deployed
        vm.expectEmit(false, false, false, true);
        emit CushionDown(true, block.timestamp);
        vm.prank(writer);
        range.updateMarket(true, type(uint256).max, 0);

        /// Check that the market is updated
        assertEq(range.market(true), type(uint256).max);
    }

    function testCorrectness_cannotUpdateMarketWithInvalidParams() public {
        /// Try to update market with a max ID and non-zero capacity
        bytes memory err = abi.encodeWithSignature("RANGE_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(writer);
        range.updateMarket(false, type(uint256).max, 1_000_000 * 1e18);

        vm.expectRevert(err);
        vm.prank(writer);
        range.updateMarket(true, type(uint256).max, 1_000_000 * 1e18);
    }

    function testCorrectness_setSpreads() public {
        /// Confirm that the spreads are set with the initial values
        assertEq(range.spread(false), 1000);
        assertEq(range.spread(true), 2000);

        /// Store initial prices. These should not update immediately when the spreads are updated because they require update prices to be called first.
        OlympusRange.Range memory startRange = range.range();

        /// Update the spreads with valid parameters from an approved address
        vm.prank(writer);
        range.setSpreads(500, 1000);

        /// Expect the spreads to be updated and the prices to be the same
        assertEq(range.spread(false), 500);
        assertEq(range.spread(true), 1000);
        assertEq(range.price(false, false), startRange.cushion.low.price);
        assertEq(range.price(true, false), startRange.wall.low.price);
        assertEq(range.price(false, true), startRange.cushion.high.price);
        assertEq(range.price(true, true), startRange.wall.high.price);

        /// Call updatePrices and check that the new spreads are applied
        vm.prank(writer);
        range.updatePrices(100 * 1e18);

        /// Expect the prices to be updated now (range is tighter so they should be inside the new spreads)
        assertGt(range.price(false, false), startRange.cushion.low.price);
        assertGt(range.price(true, false), startRange.wall.low.price);
        assertLt(range.price(false, true), startRange.cushion.high.price);
        assertLt(range.price(true, true), startRange.wall.high.price);
    }

    function testCorrectness_setThresholdFactor() public {
        /// Confirm that the threshold factor is set with the initial value
        assertEq(range.thresholdFactor(), uint256(100));

        /// Store current threshold for each side
        OlympusRange.Range memory startRange = range.range();

        /// Update the threshold factor with valid parameters from an approved address
        vm.prank(writer);
        range.setThresholdFactor(uint256(200));

        /// Expect the threshold factor to be updated and the thresholds to be the same
        assertEq(range.thresholdFactor(), uint256(200));
        OlympusRange.Range memory newRange = range.range();
        assertEq(newRange.low.threshold, startRange.low.threshold);
        assertEq(newRange.high.threshold, startRange.high.threshold);

        /// Call regenerate on each side with the same capacity as initialized and expect the threshold to be updated
        vm.startPrank(writer);
        range.regenerate(false, 10_000_000 * 1e18);
        range.regenerate(true, 10_000_000 * 1e18);
        vm.stopPrank();

        /// Expect the thresholds to be updated
        newRange = range.range();
        assertGt(newRange.low.threshold, startRange.low.threshold);
        assertGt(newRange.high.threshold, startRange.high.threshold);
    }

    function testCorrectness_cannotSetParametersWithInvalidParams() public {
        bytes memory err = abi.encodeWithSignature("RANGE_InvalidParams()");

        /// Try to call setSpreads with invalid parameters from an approved address
        /// Case 1: wallSpread > 10000
        vm.startPrank(writer);
        vm.expectRevert(err);
        range.setSpreads(1000, 20000);

        /// Case 2: wallSpread < 100
        vm.expectRevert(err);
        range.setSpreads(1000, 50);

        /// Case 3: cushionSpread > 10000
        vm.expectRevert(err);
        range.setSpreads(20000, 1000);

        /// Case 4: cushionSpread < 100
        vm.expectRevert(err);
        range.setSpreads(50, 1000);

        /// Case 5: cushionSpread > wallSpread (with in bounds values)
        vm.expectRevert(err);
        range.setSpreads(2000, 1000);

        /// Try to call setThresholdFactor with invalid parameters from an approved address
        /// Case 1: thresholdFactor > 10000
        vm.expectRevert(err);
        range.setThresholdFactor(uint256(20000));

        /// Case 2: thresholdFactor < 100
        vm.expectRevert(err);
        range.setThresholdFactor(uint256(50));

        vm.stopPrank();
    }

    function testCorrectness_onlyPermittedPoliciesCanCallGatedFunctions() public {
        /// Try to call functions as a non-permitted policy with correct params and expect reverts
        bytes memory err = abi.encodeWithSelector(
            Module_PolicyNotPermitted.selector,
            address(this)
        );

        /// updatePrices
        vm.expectRevert(err);
        range.updatePrices(110 * 1e18);

        /// updateCapacity
        vm.expectRevert(err);
        range.updateCapacity(true, 9_000_000 * 1e18);

        /// updateMarket
        vm.expectRevert(err);
        range.updateMarket(false, 2, 2_000_000 * 1e18);

        /// regenerate
        vm.expectRevert(err);
        range.regenerate(false, 10_000_000 * 1e18);

        /// setSpreads
        vm.expectRevert(err);
        range.setSpreads(500, 1000);

        /// setThresholdFactor
        vm.expectRevert(err);
        range.setThresholdFactor(uint256(200));
    }

    /* ========== VIEW TESTS ========== */

    /// DONE
    /// [X] range
    /// [X] capacity
    /// [X] active
    /// [X] price
    /// [X] spread
    /// [X] market

    function testCorrectness_viewRange() public {
        /// Get range data
        OlympusRange.Range memory _range = range.range();

        /// Confirm it matches initialized variables
        assertTrue(_range.low.active);
        assertEq(_range.low.lastActive, block.timestamp);
        assertEq(_range.low.capacity, 10_000_000 * 1e18);
        assertEq(_range.low.threshold, 100_000 * 1e18);
        assertEq(_range.low.market, type(uint256).max);

        assertTrue(_range.high.active);
        assertEq(_range.high.lastActive, block.timestamp);
        assertEq(_range.high.capacity, 10_000_000 * 1e18);
        assertEq(_range.high.threshold, 100_000 * 1e18);
        assertEq(_range.high.market, type(uint256).max);

        assertEq(_range.cushion.low.price, (100 * 1e18 * (1e4 - 1000)) / 1e4);
        assertEq(_range.cushion.high.price, (100 * 1e18 * (1e4 + 1000)) / 1e4);
        assertEq(_range.cushion.spread, 1000);

        assertEq(_range.wall.low.price, (100 * 1e18 * (1e4 - 2000)) / 1e4);
        assertEq(_range.wall.high.price, (100 * 1e18 * (1e4 + 2000)) / 1e4);
        assertEq(_range.wall.spread, 2000);
    }

    function testCorrectness_viewCapacity() public {
        /// Load the sides directly from the range
        OlympusRange.Range memory _range = range.range();

        /// Check that capacity returns the capacity value in the range
        assertEq(range.capacity(false), _range.low.capacity);
        assertEq(range.capacity(true), _range.high.capacity);
    }

    function testCorrectness_viewActive() public {
        /// Load the sides directly from the range
        OlympusRange.Range memory _range = range.range();

        /// Check that wallUp returns the same result as the struct
        assertTrue(range.active(false) == _range.low.active);
        assertTrue(range.active(true) == _range.high.active);
    }

    function testCorrectness_viewPrice() public {
        /// Load the bands directly from the range
        OlympusRange.Range memory _range = range.range();

        /// Check that cushion and walls prices match the value returned from price
        assertEq(range.price(false, false), _range.cushion.low.price);
        assertEq(range.price(true, false), _range.wall.low.price);
        assertEq(range.price(false, true), _range.cushion.high.price);
        assertEq(range.price(true, true), _range.wall.high.price);
    }

    function testCorrectness_viewSpread() public {
        /// Load the bands directly from the range
        OlympusRange.Range memory _range = range.range();

        /// Check that cushion and walls prices match the value returned from price
        assertEq(range.spread(false), _range.cushion.spread);
        assertEq(range.spread(true), _range.wall.spread);
    }

    function testCorrectness_viewMarket() public {
        /// Load the sides directly from the range
        OlympusRange.Range memory _range = range.range();

        /// Check that wallUp returns the same result as the struct
        assertEq(range.market(false), _range.low.market);
        assertEq(range.market(true), _range.high.market);
    }

    function testCorrectness_viewLastActive() public {
        /// Load the sides directly from the range
        OlympusRange.Range memory _range = range.range();

        /// Check that lastActive returns the same result as the struct
        assertEq(range.lastActive(false), _range.low.lastActive);
        assertEq(range.lastActive(true), _range.high.lastActive);
    }
}
