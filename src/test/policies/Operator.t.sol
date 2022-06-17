// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test-utils/UserFactory.sol";

import {BondFixedTermCDA} from "../lib/bonds/BondFixedTermCDA.sol";
import {BondAggregator} from "../lib/bonds/BondAggregator.sol";
import {BondFixedTermTeller} from "../lib/bonds/BondFixedTermTeller.sol";
import {RolesAuthority, Authority as SolmateAuthority} from "solmate/auth/authorities/RolesAuthority.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockOhm} from "../mocks/MockOhm.sol";
import {MockPrice} from "../mocks/MockPrice.sol";
import {MockAuthGiver} from "../mocks/MockAuthGiver.sol";
import {MockModuleWriter} from "../mocks/MockModuleWriter.sol";

import {IBondAuctioneer} from "interfaces/IBondAuctioneer.sol";
import {IBondAggregator} from "interfaces/IBondAggregator.sol";

import {FullMath} from "libraries/FullMath.sol";

import {Kernel, Actions} from "../../Kernel.sol";
import {OlympusRange} from "../../modules/RANGE.sol";
import {OlympusTreasury} from "../../modules/TRSRY.sol";
import {OlympusMinter, OHM} from "../../modules/MINTR.sol";
import {OlympusAuthority} from "../../modules/AUTHR.sol";

import {Operator} from "../../policies/Operator.sol";
import {BondCallback} from "../../policies/BondCallback.sol";

contract OperatorTest is Test {
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address internal bob;
    address internal guardian;
    address internal policy;
    address internal heart;

    RolesAuthority internal auth;
    BondAggregator internal aggregator;
    BondFixedTermTeller internal teller;
    BondFixedTermCDA internal auctioneer;
    MockOhm internal ohm;
    MockERC20 internal reserve;

    Kernel internal kernel;
    MockPrice internal price;
    OlympusRange internal range;
    OlympusTreasury internal treasury;
    OlympusMinter internal minter;
    OlympusAuthority internal authr;

    Operator internal operator;
    BondCallback internal callback;
    MockAuthGiver internal authGiver;

    MockModuleWriter internal writer;
    OlympusTreasury internal treasuryWriter;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            /// Deploy bond system to test against
            address[] memory users = userCreator.create(5);
            alice = users[0];
            bob = users[1];
            guardian = users[2];
            policy = users[3];
            heart = users[4];
            auth = new RolesAuthority(guardian, SolmateAuthority(address(0)));

            /// Deploy the bond system
            aggregator = new BondAggregator(guardian, auth);
            teller = new BondFixedTermTeller(
                guardian,
                aggregator,
                guardian,
                auth
            );
            auctioneer = new BondFixedTermCDA(
                teller,
                aggregator,
                guardian,
                auth
            );

            /// Register auctioneer on the bond system
            vm.prank(guardian);
            aggregator.registerAuctioneer(auctioneer);
        }

        {
            /// Deploy mock tokens
            ohm = new MockOhm("Olympus", "OHM", 9);
            reserve = new MockERC20("Reserve", "RSV", 18);
        }

        {
            /// Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            /// Deploy modules (some mocks)
            price = new MockPrice(kernel);
            range = new OlympusRange(
                kernel,
                [ERC20(ohm), ERC20(reserve)],
                [uint256(100), uint256(1000), uint256(2000)]
            );
            treasury = new OlympusTreasury(kernel);
            minter = new OlympusMinter(kernel, address(ohm));
            authr = new OlympusAuthority(kernel);

            /// Deploy mock writer for treasury to give withdraw permissions
            writer = new MockModuleWriter(kernel, treasury);
            treasuryWriter = OlympusTreasury(address(writer));

            /// Configure mocks
            price.setMovingAverage(100 * 1e18);
            price.setLastPrice(100 * 1e18);
            price.setDecimals(18);
        }

        {
            /// Deploy bond callback
            callback = new BondCallback(
                kernel,
                IBondAggregator(address(aggregator)),
                ohm
            );

            /// Deploy operator
            operator = new Operator(
                kernel,
                IBondAuctioneer(address(auctioneer)),
                callback,
                [ERC20(ohm), ERC20(reserve)],
                [
                    uint32(2000), // cushionFactor
                    uint32(5 days), // duration
                    uint32(100_000), // debtBuffer
                    uint32(1 hours), // depositInterval
                    uint32(1000), // reserveFactor
                    uint32(1 hours), // regenWait
                    uint32(5), // regenThreshold
                    uint32(7) // regenObserve
                ]
            );

            /// Registor operator to create bond markets with a callback
            vm.prank(guardian);
            auctioneer.setCallbackAuthStatus(address(operator), true);

            /// Deploy mock auth giver
            authGiver = new MockAuthGiver(kernel);
        }

        {
            /// Initialize system and kernel

            /// Install modules
            kernel.executeAction(Actions.InstallModule, address(authr));
            kernel.executeAction(Actions.InstallModule, address(price));
            kernel.executeAction(Actions.InstallModule, address(range));
            kernel.executeAction(Actions.InstallModule, address(treasury));
            kernel.executeAction(Actions.InstallModule, address(minter));

            /// Approve policies
            kernel.executeAction(Actions.ApprovePolicy, address(operator));
            kernel.executeAction(Actions.ApprovePolicy, address(callback));
            kernel.executeAction(Actions.ApprovePolicy, address(authGiver));
            kernel.executeAction(Actions.ApprovePolicy, address(writer));

            /// Configure access control

            /// Set role permissions

            /// Role 0 = Heart
            authGiver.setRoleCapability(
                uint8(0),
                address(operator),
                operator.operate.selector
            );

            /// Role 1 = Guardian
            authGiver.setRoleCapability(
                uint8(1),
                address(operator),
                operator.operate.selector
            );
            authGiver.setRoleCapability(
                uint8(1),
                address(operator),
                operator.setBondContracts.selector
            );
            authGiver.setRoleCapability(
                uint8(1),
                address(operator),
                operator.initialize.selector
            );

            /// Role 2 = Policy
            authGiver.setRoleCapability(
                uint8(2),
                address(operator),
                operator.setSpreads.selector
            );

            authGiver.setRoleCapability(
                uint8(2),
                address(operator),
                operator.setThresholdFactor.selector
            );

            authGiver.setRoleCapability(
                uint8(2),
                address(operator),
                operator.setCushionFactor.selector
            );
            authGiver.setRoleCapability(
                uint8(2),
                address(operator),
                operator.setCushionParams.selector
            );
            authGiver.setRoleCapability(
                uint8(2),
                address(operator),
                operator.setReserveFactor.selector
            );
            authGiver.setRoleCapability(
                uint8(2),
                address(operator),
                operator.setRegenParams.selector
            );
            authGiver.setRoleCapability(
                uint8(2),
                address(callback),
                callback.batchToTreasury.selector
            );

            /// Role 3 = Operator
            authGiver.setRoleCapability(
                uint8(3),
                address(callback),
                callback.whitelist.selector
            );

            /// Give roles to users
            authGiver.setUserRole(heart, uint8(0));
            authGiver.setUserRole(guardian, uint8(1));
            authGiver.setUserRole(policy, uint8(2));
            authGiver.setUserRole(address(operator), uint8(3));
        }

        // Mint tokens to users and treasury for testing
        uint256 testOhm = 1_000_000 * 1e9;
        uint256 testReserve = 1_000_000 * 1e18;

        ohm.mint(alice, testOhm * 20);
        reserve.mint(alice, testReserve * 20);

        reserve.mint(address(treasury), testReserve * 100);

        // Approve the operator and callback for withdrawals on the treasury
        treasuryWriter.requestApprovalFor(
            address(operator),
            reserve,
            testReserve * 100
        );

        treasuryWriter.requestApprovalFor(
            address(callback),
            reserve,
            testReserve * 100
        );

        // Approve the operator for the tokens to swap
        vm.prank(alice);
        ohm.approve(address(operator), testOhm * 20);
        vm.prank(alice);
        reserve.approve(address(operator), testReserve * 20);

        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();
    }

    /* ========== HELPER FUNCTIONS ========== */
    function knockDownWall(bool high_)
        internal
        returns (uint256 amountIn, uint256 amountOut)
    {
        if (high_) {
            /// Get current capacity of the high wall
            /// Set amount in to put capacity 1 below the threshold for shutting down the wall
            uint256 startCapacity = range.capacity(true);
            amountIn = startCapacity.mulDiv(9999, 10000) + 1;

            /// Swap at the high wall
            vm.prank(alice);
            amountOut = operator.swap(reserve, amountIn);
        } else {
            /// Get current capacity of the low wall
            /// Set amount in to put capacity 1 below the threshold for shutting down the wall
            uint256 startCapacity = range.capacity(false);
            uint256 lowWallPrice = range.price(true, false);
            amountIn =
                startCapacity.mulDiv(1e9, lowWallPrice).mulDiv(9999, 10000) +
                1;

            /// Swap at the low wall
            vm.prank(alice);
            amountOut = operator.swap(ohm, amountIn);
        }
    }

    /* ========== WALL TESTS ========== */

    /// DONE
    /// [X] Able to swap when walls are up
    /// [X] Wall breaks when capacity drops below the configured threshold
    /// [X] Not able to swap at the walls when they are down

    function testCorrectness_swapHighWall() public {
        /// Get current capacity of the high wall and starting balance for user
        uint256 startCapacity = range.capacity(true);
        uint256 amountIn = 100 * 1e18;
        uint256 ohmBalance = ohm.balanceOf(alice);
        uint256 reserveBalance = reserve.balanceOf(alice);

        /// Calculate expected difference
        uint256 highWallPrice = range.price(true, true);
        uint256 expAmountOut = amountIn.mulDiv(1e9, 1e18).mulDiv(
            1e18,
            highWallPrice
        );

        /// Swap at the high wall
        vm.prank(alice);
        uint256 amountOut = operator.swap(reserve, amountIn);

        /// Get updated capacity of the high wall
        uint256 endCapacity = range.capacity(true);

        assertEq(amountOut, expAmountOut);
        assertEq(endCapacity, startCapacity - amountIn);
        assertEq(ohm.balanceOf(alice), ohmBalance + amountOut);
        assertEq(reserve.balanceOf(alice), reserveBalance - amountIn);
    }

    function testCorrectness_swapLowWall() public {
        /// Get current capacity of the high wall and starting balance for user
        uint256 startCapacity = range.capacity(false);
        uint256 amountIn = 100 * 1e9;
        uint256 ohmBalance = ohm.balanceOf(alice);
        uint256 reserveBalance = reserve.balanceOf(alice);

        /// Calculate expected difference
        uint256 lowWallPrice = range.price(true, false);
        uint256 expAmountOut = amountIn.mulDiv(1e18, 1e9).mulDiv(
            lowWallPrice,
            1e18
        );

        /// Swap at the high wall
        vm.prank(alice);
        uint256 amountOut = operator.swap(ohm, amountIn);

        /// Get updated capacity of the high wall
        uint256 endCapacity = range.capacity(false);

        assertEq(amountOut, expAmountOut);
        assertEq(endCapacity, startCapacity - amountOut);
        assertEq(ohm.balanceOf(alice), ohmBalance - amountIn);
        assertEq(reserve.balanceOf(alice), reserveBalance + amountOut);
    }

    function testCorrectness_highWallBreaksAtThreshold() public {
        /// Confirm wall is up
        assertTrue(range.active(true));

        /// Get initial balances and capacity
        uint256 ohmBalance = ohm.balanceOf(alice);
        uint256 reserveBalance = reserve.balanceOf(alice);
        uint256 startCapacity = range.capacity(true);

        /// Take down wall with helper function
        (uint256 amountIn, uint256 amountOut) = knockDownWall(true);

        /// Get updated capacity of the high wall
        uint256 endCapacity = range.capacity(true);

        /// Confirm the wall is down
        assertTrue(!range.active(true));

        /// Check that capacity and balances are correct
        assertEq(endCapacity, startCapacity - amountIn);
        assertEq(ohm.balanceOf(alice), ohmBalance + amountOut);
        assertEq(reserve.balanceOf(alice), reserveBalance - amountIn);
    }

    function testCorrectness_lowWallBreaksAtThreshold() public {
        /// Confirm wall is up
        assertTrue(range.active(false));

        /// Get initial balances and capacity
        uint256 ohmBalance = ohm.balanceOf(alice);
        uint256 reserveBalance = reserve.balanceOf(alice);
        uint256 startCapacity = range.capacity(false);

        /// Take down wall with helper function
        (uint256 amountIn, uint256 amountOut) = knockDownWall(false);

        /// Get updated capacity of the high wall
        uint256 endCapacity = range.capacity(false);

        /// Confirm the wall is down
        assertTrue(!range.active(false));

        /// Check that capacity and balances are correct
        assertEq(endCapacity, startCapacity - amountOut);
        assertEq(ohm.balanceOf(alice), ohmBalance - amountIn);
        assertEq(reserve.balanceOf(alice), reserveBalance + amountOut);
    }

    function testCorrectness_cannotSwapHighWallWhenDown() public {
        /// Confirm wall is up
        assertTrue(range.active(true));

        /// Take down wall with helper function
        knockDownWall(true);

        /// Try to swap, expect to fail
        bytes memory err = abi.encodeWithSignature("Operator_WallDown()");
        vm.expectRevert(err);
        vm.prank(alice);
        operator.swap(reserve, 100 * 1e18);
    }

    function testCorrectness_cannotSwapLowWallWhenDown() public {
        /// Confirm wall is up
        assertTrue(range.active(false));

        /// Take down wall with helper function
        knockDownWall(false);

        /// Try to swap, expect to fail
        bytes memory err = abi.encodeWithSignature("Operator_WallDown()");
        vm.expectRevert(err);
        vm.prank(alice);
        operator.swap(ohm, 100 * 1e18);
    }

    /* ========== CUSHION TESTS ========== */

    /// DONE
    /// [X] Cushions deployed when price set in the range and operate triggered
    /// [X] Cushions deactivated when price out of range and operate triggered or when wall goes down
    /// [X] Cushion doesn't deploy when wall is down

    function testCorrectness_highCushionDeployedInSpread() public {
        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(true)));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(111 * 1e18);

        /// Trigger the operate function manually
        vm.prank(guardian);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        assertTrue(auctioneer.isLive(range.market(true)));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(range.market(true));
        assertEq(
            marketCapacity,
            range.capacity(true).mulDiv(config.cushionFactor, 1e4)
        );
        assertEq(marketCapacity, range.lastMarketCapacity(true));
    }

    function testCorrectness_highCushionClosedBelowSpread() public {
        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(true)));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(111 * 1e18);

        /// Trigger the operate function manually
        vm.prank(guardian);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        assertTrue(auctioneer.isLive(range.market(true)));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(range.market(true));
        assertEq(
            marketCapacity,
            range.capacity(true).mulDiv(config.cushionFactor, 1e4)
        );
        assertEq(marketCapacity, range.lastMarketCapacity(true));

        /// Set price on mock oracle below the high cushion
        price.setLastPrice(105 * 1e18);

        /// Trigger the operate function manually
        vm.prank(guardian);
        operator.operate();

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(range.market(true)));

        marketCapacity = auctioneer.currentCapacity(range.market(true));
        assertEq(marketCapacity, 0);
        assertEq(range.lastMarketCapacity(true), 0);
    }

    function testCorrectness_highCushionClosedAboveSpread() public {
        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(true)));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(111 * 1e18);

        /// Trigger the operate function manually
        vm.prank(guardian);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        assertTrue(auctioneer.isLive(range.market(true)));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(range.market(true));
        assertEq(
            marketCapacity,
            range.capacity(true).mulDiv(config.cushionFactor, 1e4)
        );
        assertEq(marketCapacity, range.lastMarketCapacity(true));

        /// Set price on mock oracle below the high cushion
        price.setLastPrice(130 * 1e18);

        /// Trigger the operate function manually
        vm.prank(guardian);
        operator.operate();

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(range.market(true)));

        marketCapacity = auctioneer.currentCapacity(range.market(true));
        assertEq(marketCapacity, 0);
        assertEq(range.lastMarketCapacity(true), 0);
    }

    function testCorrectness_highCushionClosedWhenWallDown() public {
        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(true)));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(111 * 1e18);

        /// Trigger the operate function manually
        vm.prank(guardian);
        operator.operate();

        /// Check that the cushion is deployed
        assertTrue(auctioneer.isLive(range.market(true)));

        /// Take down the wall
        knockDownWall(true);

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(range.market(true)));
    }

    function testCorrectness_highCushionNotDeployedWhenWallDown() public {
        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(true)));

        /// Take down the wall
        knockDownWall(true);

        /// Set price on mock oracle into the low cushion
        price.setLastPrice(111 * 1e18);

        /// Trigger the operate function manually
        vm.prank(guardian);
        operator.operate();

        /// Check that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(true)));
    }

    function testCorrectness_lowCushionDeployedInSpread() public {
        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(false)));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(89 * 1e18);

        /// Trigger the operate function manually
        vm.prank(guardian);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        assertTrue(auctioneer.isLive(range.market(false)));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(
            range.market(false)
        );
        assertEq(
            marketCapacity,
            range.capacity(false).mulDiv(config.cushionFactor, 1e4)
        );
        assertEq(marketCapacity, range.lastMarketCapacity(false));
    }

    function testCorrectness_lowCushionClosedBelowSpread() public {
        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(false)));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(89 * 1e18);

        /// Trigger the operate function manually
        vm.prank(guardian);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        assertTrue(auctioneer.isLive(range.market(false)));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(
            range.market(false)
        );
        assertEq(
            marketCapacity,
            range.capacity(false).mulDiv(config.cushionFactor, 1e4)
        );
        assertEq(marketCapacity, range.lastMarketCapacity(false));

        /// Set price on mock oracle below the high cushion
        price.setLastPrice(79 * 1e18);

        /// Trigger the operate function manually
        vm.prank(guardian);
        operator.operate();

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(range.market(false)));

        marketCapacity = auctioneer.currentCapacity(range.market(false));
        assertEq(marketCapacity, 0);
        assertEq(range.lastMarketCapacity(false), 0);
    }

    function testCorrectness_lowCushionClosedAboveSpread() public {
        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(false)));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(89 * 1e18);

        /// Trigger the operate function manually
        vm.prank(guardian);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        assertTrue(auctioneer.isLive(range.market(false)));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(
            range.market(false)
        );
        assertEq(
            marketCapacity,
            range.capacity(false).mulDiv(config.cushionFactor, 1e4)
        );
        assertEq(marketCapacity, range.lastMarketCapacity(false));

        /// Set price on mock oracle below the high cushion
        price.setLastPrice(91 * 1e18);

        /// Trigger the operate function manually
        vm.prank(guardian);
        operator.operate();

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(range.market(false)));

        marketCapacity = auctioneer.currentCapacity(range.market(false));
        assertEq(marketCapacity, 0);
        assertEq(range.lastMarketCapacity(false), 0);
    }

    function testCorrectness_lowCushionClosedWhenWallDown() public {
        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(false)));

        /// Set price on mock oracle into the low cushion
        price.setLastPrice(89 * 1e18);

        /// Trigger the operate function manually
        vm.prank(guardian);
        operator.operate();

        /// Check that the cushion is deployed
        assertTrue(auctioneer.isLive(range.market(false)));

        /// Take down the wall
        knockDownWall(false);

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(range.market(false)));
    }

    function testCorrectness_lowCushionNotDeployedWhenWallDown() public {
        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(false)));

        /// Take down the wall
        knockDownWall(false);

        /// Set price on mock oracle into the low cushion
        price.setLastPrice(89 * 1e18);

        /// Trigger the operate function manually
        vm.prank(guardian);
        operator.operate();

        /// Check that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(false)));
    }

    /* ========== REGENERATION TESTS ========== */

    /// DONE
    /// [X] Wall regenerates when price on other side of MA for enough observations
    /// [X] Wrap around logic works for counting observations
    /// [X] Regen period enforces a minimum time to wait for regeneration

    function testCorrectness_lowWallRegenA() public {
        /// Tests the simplest case of regen
        /// Takes down wall, moves price in regen range,
        /// and hits regen count required with consequtive calls

        /// Confirm wall is up
        assertTrue(range.active(false));

        /// Take down the wall
        knockDownWall(false);

        /// Check that the wall is down
        assertTrue(!range.active(false));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the low wall and verify under threshold
        uint256 startCapacity = range.capacity(false);
        uint256 fullCapacity = operator.fullCapacity(false);
        assertLe(startCapacity, fullCapacity.mulDiv(10, 1e4));

        /// Set price above the moving average to regenerate low wall
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(guardian);
            operator.operate();
        }

        /// Check that the wall is up
        assertTrue(range.active(false));

        /// Check that the capacity has regenerated
        uint256 endCapacity = range.capacity(false);
        assertEq(endCapacity, fullCapacity);
    }

    function testCorrectness_lowWallRegenB() public {
        /// Tests wrap around logic of regen
        /// Takes down wall, calls operate a few times with price not in regen range,
        /// moves price into regen range, and hits regen count required with consequtive calls
        /// that wrap around the count array

        /// Confirm wall is up
        assertTrue(range.active(false));

        /// Take down the wall
        knockDownWall(false);

        /// Check that the wall is down
        assertTrue(!range.active(false));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the low wall and verify under threshold
        uint256 startCapacity = range.capacity(false);
        uint256 fullCapacity = operator.fullCapacity(false);
        assertLe(startCapacity, fullCapacity.mulDiv(10, 1e4));

        /// Set price below the moving average so regeneration doesn't start
        price.setLastPrice(98 * 1e18);

        /// Trigger the operator function with negative
        for (uint256 i = 0; i < 8; i++) {
            vm.prank(guardian);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(false));

        /// Set price above the moving average to regenerate low wall
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(guardian);
            operator.operate();
        }

        /// Check that the wall is up
        assertTrue(range.active(false));

        /// Check that the capacity has regenerated
        uint256 endCapacity = range.capacity(false);
        assertEq(endCapacity, fullCapacity);
    }

    function testCorrectness_lowWallRegenC() public {
        /// Tests that wall does not regenerate before the required count is reached

        /// Confirm wall is up
        assertTrue(range.active(false));

        /// Take down the wall
        knockDownWall(false);

        /// Check that the wall is down
        assertTrue(!range.active(false));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the low wall and verify under threshold
        uint256 startCapacity = range.capacity(false);
        uint256 fullCapacity = operator.fullCapacity(false);
        assertLe(startCapacity, fullCapacity.mulDiv(10, 1e4));

        /// Set price above the moving average to regenerate low wall
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(guardian);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(false));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = range.capacity(false);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_lowWallRegenD() public {
        /// Tests that wall does not regenerate before the required count is reached
        /// Use more complex logic to ensure wrap around logic is working and
        /// that positive checks outside the moving window aren't counted
        /// observations should be: +, -, -, -, +, +, +, +
        /// last observation wraps around to first and therefore only 4/7 of the observations are counted

        /// Confirm wall is up
        assertTrue(range.active(false));

        /// Take down the wall
        knockDownWall(false);

        /// Check that the wall is down
        assertTrue(!range.active(false));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the low wall and verify under threshold
        uint256 startCapacity = range.capacity(false);
        uint256 fullCapacity = operator.fullCapacity(false);
        assertLe(startCapacity, fullCapacity.mulDiv(10, 1e4));

        /// Set price above the moving average to regenerate low wall
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator once to get a positive check
        vm.prank(guardian);
        operator.operate();

        /// Set price below the moving average to get negative checks
        price.setLastPrice(99 * 1e18);

        /// Trigger the operator function several times with negative checks
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(guardian);
            operator.operate();
        }

        /// Set price above the moving average to regenerate low wall
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator function several times with positive checks
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(guardian);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(false));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = range.capacity(false);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_lowWallRegenTime() public {
        /// Tests that the wall won't regenerate before the required time has passed,
        /// even with enough observations
        /// Takes down wall, moves price in regen range,
        /// and hits regen count required with consequtive calls

        /// Confirm wall is up
        assertTrue(range.active(false));

        /// Take down the wall
        knockDownWall(false);

        /// Check that the wall is down
        assertTrue(!range.active(false));

        /// Don't move time forward past the regen period so it won't regen

        /// Get capacity of the low wall and verify under threshold
        uint256 startCapacity = range.capacity(false);
        uint256 fullCapacity = operator.fullCapacity(false);
        assertLe(startCapacity, fullCapacity.mulDiv(10, 1e4));

        /// Set price above the moving average to regenerate low wall
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(guardian);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(false));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = range.capacity(false);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_highWallRegenA() public {
        /// Tests the simplest case of regen
        /// Takes down wall, moves price in regen range,
        /// and hits regen count required with consequtive calls

        /// Confirm wall is up
        assertTrue(range.active(true));

        /// Take down the wall
        knockDownWall(true);

        /// Check that the wall is down
        assertTrue(!range.active(true));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the high wall and verify under threshold
        uint256 startCapacity = range.capacity(true);
        uint256 fullCapacity = operator.fullCapacity(true);
        assertLe(startCapacity, fullCapacity.mulDiv(10, 1e4));

        /// Set price below the moving average to regenerate high wall
        price.setLastPrice(99 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(guardian);
            operator.operate();
        }

        /// Check that the wall is up
        assertTrue(range.active(true));

        /// Check that the capacity has regenerated
        uint256 endCapacity = range.capacity(true);
        assertEq(endCapacity, fullCapacity);
    }

    function testCorrectness_highWallRegenB() public {
        /// Tests wrap around logic of regen
        /// Takes down wall, calls operate a few times with price not in regen range,
        /// moves price into regen range, and hits regen count required with consequtive calls
        /// that wrap around the count array

        /// Confirm wall is up
        assertTrue(range.active(true));

        /// Take down the wall
        knockDownWall(true);

        /// Check that the wall is down
        assertTrue(!range.active(true));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the high wall and verify under threshold
        uint256 startCapacity = range.capacity(true);
        uint256 fullCapacity = operator.fullCapacity(true);
        assertLe(startCapacity, fullCapacity.mulDiv(10, 1e4));

        /// Set price above the moving average so regeneration doesn't start
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator function with negative
        for (uint256 i = 0; i < 8; i++) {
            vm.prank(guardian);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(true));

        /// Set price below the moving average to regenerate high wall
        price.setLastPrice(98 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(guardian);
            operator.operate();
        }

        /// Check that the wall is up
        assertTrue(range.active(true));

        /// Check that the capacity has regenerated
        uint256 endCapacity = range.capacity(true);
        assertEq(endCapacity, fullCapacity);
    }

    function testCorrectness_highWallRegenC() public {
        /// Tests that wall does not regenerate before the required count is reached

        /// Confirm wall is up
        assertTrue(range.active(true));

        /// Take down the wall
        knockDownWall(true);

        /// Check that the wall is down
        assertTrue(!range.active(true));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the high wall and verify under threshold
        uint256 startCapacity = range.capacity(true);
        uint256 fullCapacity = operator.fullCapacity(true);
        assertLe(startCapacity, fullCapacity.mulDiv(10, 1e4));

        /// Set price below the moving average to regenerate high wall
        price.setLastPrice(98 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(guardian);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(true));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = range.capacity(true);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_highWallRegenD() public {
        /// Tests that wall does not regenerate before the required count is reached
        /// Use more complex logic to ensure wrap around logic is working and
        /// that positive checks outside the moving window aren't counted
        /// observations should be: +, -, -, -, +, +, +, +
        /// last observation wraps around to first and therefore only 4/7 of the observations are counted

        /// Confirm wall is up
        assertTrue(range.active(true));

        /// Take down the wall
        knockDownWall(true);

        /// Check that the wall is down
        assertTrue(!range.active(true));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the high wall and verify under threshold
        uint256 startCapacity = range.capacity(true);
        uint256 fullCapacity = operator.fullCapacity(true);
        assertLe(startCapacity, fullCapacity.mulDiv(10, 1e4));

        /// Set price below the moving average to regenerate low wall
        price.setLastPrice(98 * 1e18);

        /// Trigger the operator once to get a positive check
        vm.prank(guardian);
        operator.operate();

        /// Set price above the moving average to get negative checks
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator function several times with negative checks
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(guardian);
            operator.operate();
        }

        /// Set price below the moving average to regenerate high wall
        price.setLastPrice(98 * 1e18);

        /// Trigger the operator function several times with positive checks
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(guardian);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(true));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = range.capacity(true);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_highWallRegenTime() public {
        /// Tests that the wall won't regenerate before the required time has passed,
        /// even with enough observations
        /// Takes down wall, moves price in regen range,
        /// and hits regen count required with consequtive calls

        /// Confirm wall is up
        assertTrue(range.active(true));

        /// Take down the wall
        knockDownWall(true);

        /// Check that the wall is down
        assertTrue(!range.active(true));

        /// Don't move time forward past the regen period so it won't regen

        /// Get capacity of the high wall and verify under threshold
        uint256 startCapacity = range.capacity(true);
        uint256 fullCapacity = operator.fullCapacity(true);
        assertLe(startCapacity, fullCapacity.mulDiv(10, 1e4));

        /// Set price below the moving average to regenerate high wall
        price.setLastPrice(99 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(guardian);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(true));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = range.capacity(true);
        assertEq(endCapacity, startCapacity);
    }

    /* ========== ACCESS CONTROL TESTS ========== */

    /// DONE
    /// [X] operate only callable by heart or guardian
    /// [X] admin configuration functions only callable by policy or guardian (negative here, positive in ADMIN TESTS sections)

    function testCorrectness_onlyHeartOrGovernanceCanOperate() public {
        /// Call operate as heart contract
        vm.prank(heart);
        operator.operate();

        /// Call operate as governance
        vm.prank(guardian);
        operator.operate();

        /// Try to call operate as anyone else
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(alice);
        operator.operate();
    }

    function testCorrectness_nonPolicyCannotSetConfig() public {
        /// Try to set spreads as random user, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(alice);
        operator.setSpreads(1500, 3000);

        /// Try to set cushionFactor as random user, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        operator.setCushionFactor(1500);

        /// Try to set cushionDuration as random user, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        operator.setCushionParams(
            uint32(6 hours),
            uint32(50_000),
            uint32(4 hours)
        );

        /// Try to set cushionFactor as random user, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        operator.setReserveFactor(1500);

        /// Try to set regenParams as a random user, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        operator.setRegenParams(uint32(1 days), uint32(8), uint32(11));
    }

    function testCorrectness_nonGuardianCannotCall() public {
        /// Try to set spreads as random user, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(alice);
        operator.setBondContracts(IBondAuctioneer(alice), BondCallback(alice));

        /// Try to initialize as a random user, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        operator.initialize();
    }

    /* ========== ADMIN TESTS ========== */

    /// DONE
    /// [X] setSpreads
    /// [X] setThresholdFactor (in Range.t.sol)
    /// [X] setCushionFactor
    /// [X] setCushionParams
    /// [X] setReserveFactor
    /// [X] setRegenParams
    /// [X] setBondContracts
    /// [X] initialize

    function testCorrectness_setSpreads() public {
        /// Get starting bands
        OlympusRange.Range memory startRange = range.range();

        /// Set spreads larger as admin
        vm.prank(policy);
        operator.setSpreads(1500, 3000);

        /// Get new bands
        OlympusRange.Range memory newRange = range.range();

        /// Check that the spreads have been set and prices are updated
        assertEq(newRange.cushion.spread, 1500);
        assertEq(newRange.wall.spread, 3000);
        assertLt(newRange.cushion.low.price, startRange.cushion.low.price);
        assertLt(newRange.wall.low.price, startRange.wall.low.price);
        assertGt(newRange.cushion.high.price, startRange.cushion.high.price);
        assertGt(newRange.wall.high.price, startRange.wall.high.price);

        /// Set spreads smaller as admin
        vm.prank(policy);
        operator.setSpreads(500, 1000);

        /// Get new bands
        newRange = range.range();

        /// Check that the spreads have been set and prices are updated
        assertEq(newRange.cushion.spread, 500);
        assertEq(newRange.wall.spread, 1000);
        assertGt(newRange.cushion.low.price, startRange.cushion.low.price);
        assertGt(newRange.wall.low.price, startRange.wall.low.price);
        assertLt(newRange.cushion.high.price, startRange.cushion.high.price);
        assertLt(newRange.wall.high.price, startRange.wall.high.price);
    }

    function testCorrectness_cannotSetSpreadWithInvalidParams() public {
        /// Set spreads with invalid params as admin (both too low)
        bytes memory err = abi.encodeWithSignature("RANGE_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setSpreads(99, 99);

        /// Set spreads with invalid params as admin (both too high)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setSpreads(10001, 10001);

        /// Set spreads with invalid params as admin (one high, one low)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setSpreads(99, 10001);

        /// Set spreads with invalid params as admin (one high, one low)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setSpreads(10001, 99);

        /// Set spreads with invalid params as admin (cushion > wall)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setSpreads(2000, 1000);

        /// Set spreads with invalid params as admin (one in, one high)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setSpreads(1000, 10001);

        /// Set spreads with invalid params as admin (one in, one low)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setSpreads(99, 2000);
    }

    function testCorrectness_setCushionFactor() public {
        /// Get starting cushion factor
        Operator.Config memory startConfig = operator.config();

        /// Set cushion factor as admin
        vm.prank(policy);
        operator.setCushionFactor(uint32(1000));

        /// Get new cushion factor
        Operator.Config memory newConfig = operator.config();

        /// Check that the cushion factor has been set
        assertEq(newConfig.cushionFactor, uint32(1000));
        assertLt(newConfig.cushionFactor, startConfig.cushionFactor);
    }

    function testCorrectness_cannotSetCushionFactorWithInvalidParams() public {
        /// Set cushion factor with invalid params as admin (too low)
        bytes memory err = abi.encodeWithSignature("Operator_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setCushionFactor(uint32(99));

        /// Set cushion factor with invalid params as admin (too high)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setCushionFactor(uint32(10001));
    }

    function testCorrectness_setCushionParams() public {
        /// Get starting cushion params
        Operator.Config memory startConfig = operator.config();

        /// Set cushion params as admin
        vm.prank(policy);
        operator.setCushionParams(
            uint32(24 hours),
            uint32(50_000),
            uint32(4 hours)
        );

        /// Get new cushion params
        Operator.Config memory newConfig = operator.config();

        /// Check that the cushion params has been set
        assertEq(newConfig.cushionDuration, uint32(24 hours));
        assertLt(newConfig.cushionDuration, startConfig.cushionDuration);
        assertEq(newConfig.cushionDebtBuffer, uint32(50_000));
        assertLt(newConfig.cushionDebtBuffer, startConfig.cushionDebtBuffer);
        assertEq(newConfig.cushionDepositInterval, uint32(4 hours));
        assertGt(
            newConfig.cushionDepositInterval,
            startConfig.cushionDepositInterval
        );
    }

    function testCorrectness_cannotSetCushionParamsWithInvalidParams() public {
        /// Set cushion params with invalid duration as admin (too low)
        bytes memory err = abi.encodeWithSignature("Operator_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setCushionParams(
            uint32(1 hours) - 1,
            uint32(100_000),
            uint32(1 hours)
        );

        /// Set cushion params with invalid duration as admin (too high)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setCushionParams(
            uint32(7 days) + 1,
            uint32(100_000),
            uint32(1 hours)
        );

        /// Set cushion params with deposit interval greater than duration as admin
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setCushionParams(
            uint32(4 hours),
            uint32(100_000),
            uint32(6 hours)
        );
    }

    function testCorrectness_setReserveFactor() public {
        /// Get starting reserve factor
        Operator.Config memory startConfig = operator.config();

        /// Set reserve factor as admin
        vm.prank(policy);
        operator.setReserveFactor(uint32(500));

        /// Get new reserve factor
        Operator.Config memory newConfig = operator.config();

        /// Check that the reserve factor has been set
        assertEq(newConfig.reserveFactor, uint32(500));
        assertLt(newConfig.reserveFactor, startConfig.reserveFactor);
    }

    function testCorrectness_cannotSetReserveFactorWithInvalidParams() public {
        /// Set reserve factor with invalid params as admin (too low)
        bytes memory err = abi.encodeWithSignature("Operator_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setReserveFactor(uint32(99));

        /// Set reserve factor with invalid params as admin (too high)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setReserveFactor(uint32(10001));
    }

    function testCorrectness_setRegenParams() public {
        /// Get starting regen params
        Operator.Config memory startConfig = operator.config();

        /// Set regen params as admin
        vm.prank(policy);
        operator.setRegenParams(uint32(1 days), uint32(11), uint32(15));

        /// Get new regen params
        Operator.Config memory newConfig = operator.config();

        /// Check that the regen params have been set
        assertEq(newConfig.regenWait, uint256(1 days));
        assertEq(newConfig.regenThreshold, 11);
        assertEq(newConfig.regenObserve, 15);
        assertGt(newConfig.regenWait, startConfig.regenWait);
        assertGt(newConfig.regenThreshold, startConfig.regenThreshold);
        assertGt(newConfig.regenObserve, startConfig.regenObserve);
    }

    function testCorrectness_setBondContracts() public {
        /// Create new bond contracts
        BondFixedTermCDA newCDA = new BondFixedTermCDA(
            teller,
            aggregator,
            guardian,
            auth
        );
        BondCallback newCb = new BondCallback(
            kernel,
            IBondAggregator(address(aggregator)),
            ohm
        );

        /// Update the bond contracts as guardian
        vm.prank(guardian);
        operator.setBondContracts(IBondAuctioneer(address(newCDA)), newCb);

        /// Check that the bond contracts have been set
        assertEq(address(operator.auctioneer()), address(newCDA));
        assertEq(address(operator.callback()), address(newCb));
    }

    function testCorrectness_cannotInitializeTwice() public {
        /// Try to initialize the operator again as guardian
        bytes memory err = abi.encodeWithSignature(
            "Operator_AlreadyInitialized()"
        );
        vm.expectRevert(err);
        vm.prank(guardian);
        operator.initialize();
    }

    /* ========== VIEW TESTS ========== */

    /// DONE
    /// [X] fullCapacity
    /// [X] getAmountOut

    function testCorrectness_viewFullCapacity() public {
        /// Load config
        Operator.Config memory config = operator.config();

        /// Check that fullCapacity returns the full capacity based on the reserveFactor
        uint256 resInTreasury = treasury.getReserveBalance(reserve);
        uint256 lowCapacity = resInTreasury.mulDiv(config.reserveFactor, 1e4);
        uint256 highCapacity = lowCapacity
            .mulDiv(10**price.decimals(), range.price(true, true))
            .mulDiv(1e4 + range.spread(true) * 2, 1e4);

        assertEq(operator.fullCapacity(false), lowCapacity);
        assertEq(operator.fullCapacity(true), highCapacity);
    }

    function testCorrectness_viewGetAmountOut() public {
        /// Check that getAmountOut returns the amount of token to receive for different combinations of inputs
        /// Case 1: OHM In, less than capacity
        uint256 amountIn = 100 * 1e9;
        uint256 expAmountOut = amountIn.mulDiv(1e18, 1e9).mulDiv(
            range.price(true, false),
            1e18
        );

        assertEq(expAmountOut, operator.getAmountOut(ohm, amountIn));

        /// Case 2: OHM In, more than capacity
        amountIn =
            range.capacity(true).mulDiv(1e18, 1e9).mulDiv(
                range.price(true, false),
                1e18
            ) +
            1;

        bytes memory err = abi.encodeWithSignature(
            "Operator_InsufficientCapacity()"
        );
        vm.expectRevert(err);
        operator.getAmountOut(ohm, amountIn);

        /// Case 3: Reserve In, less than capacity
        amountIn = 10000 * 1e18;
        expAmountOut = amountIn.mulDiv(1e9, 1e18).mulDiv(
            1e18,
            range.price(true, true)
        );

        assertEq(expAmountOut, operator.getAmountOut(reserve, amountIn));

        /// Case 4: Reserve In, more than capacity
        amountIn = range.capacity(false) + 1;

        vm.expectRevert(err);
        operator.getAmountOut(reserve, amountIn);
    }

    /* ========== INTERNAL FUNCTION TESTS ========== */

    /// DONE
    /// [X] Range updates from new price data when operate is called (triggers _updateRange)

    function testCorrectness_updateRange() public {
        /// Store the starting bands
        OlympusRange.Range memory startRange = range.range();

        /// Update moving average upwards and trigger the operator
        price.setMovingAverage(105 * 1e18);
        vm.prank(guardian);
        operator.operate();

        /// Check that the bands have updated
        assertGt(range.price(false, false), startRange.cushion.low.price);
        assertGt(range.price(true, false), startRange.wall.low.price);
        assertGt(range.price(false, true), startRange.cushion.high.price);
        assertGt(range.price(true, true), startRange.wall.high.price);

        /// Update moving average downwards and trigger the operator
        price.setMovingAverage(95 * 1e18);
        vm.prank(guardian);
        operator.operate();

        /// Check that the bands have updated
        assertLt(range.price(false, false), startRange.cushion.low.price);
        assertLt(range.price(true, false), startRange.wall.low.price);
        assertLt(range.price(false, true), startRange.cushion.high.price);
        assertLt(range.price(true, true), startRange.wall.high.price);
    }
}
