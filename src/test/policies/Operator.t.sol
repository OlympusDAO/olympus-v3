// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {BondFixedTermSDA} from "test/lib/bonds/BondFixedTermSDA.sol";
import {BondAggregator} from "test/lib/bonds/BondAggregator.sol";
import {BondFixedTermTeller} from "test/lib/bonds/BondFixedTermTeller.sol";
import {RolesAuthority, Authority as SolmateAuthority} from "solmate/auth/authorities/RolesAuthority.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPrice} from "test/mocks/MockPrice.sol";
import {MockOhm} from "test/mocks/MockOhm.sol";

import {IBondSDA} from "interfaces/IBondSDA.sol";
import {IBondAggregator} from "interfaces/IBondAggregator.sol";

import {FullMath} from "libraries/FullMath.sol";

import "src/Kernel.sol";
import {OlympusRange} from "modules/RANGE/OlympusRange.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter, OHM} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {Operator} from "policies/Operator.sol";
import {BondCallback} from "policies/BondCallback.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

// solhint-disable-next-line max-states-count
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
    BondFixedTermSDA internal auctioneer;
    MockOhm internal ohm;
    MockERC20 internal reserve;

    Kernel internal kernel;
    MockPrice internal price;
    OlympusRange internal range;
    OlympusTreasury internal treasury;
    OlympusMinter internal minter;
    OlympusRoles internal roles;

    Operator internal operator;
    BondCallback internal callback;
    RolesAdmin internal rolesAdmin;

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
            teller = new BondFixedTermTeller(guardian, aggregator, guardian, auth);
            auctioneer = new BondFixedTermSDA(teller, aggregator, guardian, auth);

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
            price = new MockPrice(kernel, uint48(8 hours), 10 * 1e18);
            range = new OlympusRange(
                kernel,
                ERC20(ohm),
                ERC20(reserve),
                uint256(100),
                uint256(1000),
                uint256(2000)
            );
            treasury = new OlympusTreasury(kernel);
            minter = new OlympusMinter(kernel, address(ohm));
            roles = new OlympusRoles(kernel);

            /// Configure mocks
            price.setMovingAverage(100 * 1e18);
            price.setLastPrice(100 * 1e18);
            price.setDecimals(18);
            price.setLastTime(uint48(block.timestamp));
        }

        {
            /// Deploy bond callback
            callback = new BondCallback(kernel, IBondAggregator(address(aggregator)), ohm);

            /// Deploy operator
            operator = new Operator(
                kernel,
                IBondSDA(address(auctioneer)),
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
                    // uint32(8 hours) // observationFrequency
                ]
            );

            /// Deploy roles administrator
            rolesAdmin = new RolesAdmin(kernel);
            /// Registor operator to create bond markets with a callback
            vm.prank(guardian);
            auctioneer.setCallbackAuthStatus(address(operator), true);
        }

        {
            /// Initialize system and kernel

            /// Install modules
            kernel.executeAction(Actions.InstallModule, address(price));
            kernel.executeAction(Actions.InstallModule, address(range));
            kernel.executeAction(Actions.InstallModule, address(treasury));
            kernel.executeAction(Actions.InstallModule, address(minter));
            kernel.executeAction(Actions.InstallModule, address(roles));

            /// Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(operator));
            kernel.executeAction(Actions.ActivatePolicy, address(callback));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }
        {
            /// Configure access control

            /// Operator roles
            rolesAdmin.grantRole("operator_operate", address(heart));
            rolesAdmin.grantRole("operator_reporter", address(callback));
            rolesAdmin.grantRole("operator_policy", policy);
            rolesAdmin.grantRole("operator_admin", guardian);

            /// Bond callback roles
            rolesAdmin.grantRole("callback_whitelist", address(operator));
            rolesAdmin.grantRole("callback_whitelist", guardian);
            rolesAdmin.grantRole("callback_admin", guardian);
        }

        /// Set operator on the callback
        vm.prank(guardian);
        callback.setOperator(operator);

        // Mint tokens to users and treasury for testing
        uint256 testOhm = 1_000_000 * 1e9;
        uint256 testReserve = 1_000_000 * 1e18;

        ohm.mint(alice, testOhm * 20);
        reserve.mint(alice, testReserve * 20);

        reserve.mint(address(treasury), testReserve * 100);

        // Approve the operator and bond teller for the tokens to swap
        vm.prank(alice);
        ohm.approve(address(operator), testOhm * 20);
        vm.prank(alice);
        reserve.approve(address(operator), testReserve * 20);

        vm.prank(alice);
        ohm.approve(address(teller), testOhm * 20);
        vm.prank(alice);
        reserve.approve(address(teller), testReserve * 20);
    }

    // =========  HELPER FUNCTIONS ========= //
    function knockDownWall(bool high_) internal returns (uint256 amountIn, uint256 amountOut) {
        if (high_) {
            /// Get current capacity of the high wall
            /// Set amount in to put capacity 1 below the threshold for shutting down the wall
            uint256 startCapacity = range.capacity(true);
            uint256 highWallPrice = range.price(true, true);
            amountIn = startCapacity.mulDiv(highWallPrice, 1e9).mulDiv(9999, 10000) + 1;

            uint256 expAmountOut = operator.getAmountOut(reserve, amountIn);

            /// Swap at the high wall
            vm.prank(alice);
            amountOut = operator.swap(reserve, amountIn, expAmountOut);
        } else {
            /// Get current capacity of the low wall
            /// Set amount in to put capacity 1 below the threshold for shutting down the wall
            uint256 startCapacity = range.capacity(false);
            uint256 lowWallPrice = range.price(true, false);
            amountIn = startCapacity.mulDiv(1e9, lowWallPrice).mulDiv(9999, 10000) + 1;

            uint256 expAmountOut = operator.getAmountOut(ohm, amountIn);

            /// Swap at the low wall
            vm.prank(alice);
            amountOut = operator.swap(ohm, amountIn, expAmountOut);
        }
    }

    // =========  WALL TESTS ========= //

    /// DONE
    /// [X] Able to swap when walls are up
    /// [X] Splippage check when swapping
    /// [X] Wall breaks when capacity drops below the configured threshold
    /// [X] Not able to swap at the walls when they are down
    /// [X] Not able to swap at the walls when price is stale

    function testCorrectness_swapHighWall() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Get current capacity of the high wall and starting balance for user
        uint256 startCapacity = range.capacity(true);
        uint256 amountIn = 100 * 1e18;
        uint256 ohmBalance = ohm.balanceOf(alice);
        uint256 reserveBalance = reserve.balanceOf(alice);

        /// Calculate expected difference
        uint256 highWallPrice = range.price(true, true);
        uint256 expAmountOut = amountIn.mulDiv(1e9 * 1e18, 1e18 * highWallPrice);

        /// Swap at the high wall
        vm.prank(alice);
        uint256 amountOut = operator.swap(reserve, amountIn, expAmountOut);

        /// Get updated capacity of the high wall
        uint256 endCapacity = range.capacity(true);

        assertEq(amountOut, expAmountOut);
        assertEq(endCapacity, startCapacity - amountOut);
        assertEq(ohm.balanceOf(alice), ohmBalance + amountOut);
        assertEq(reserve.balanceOf(alice), reserveBalance - amountIn);
    }

    function testCorrectness_swapLowWall() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Get current capacity of the high wall and starting balance for user
        uint256 startCapacity = range.capacity(false);
        uint256 amountIn = 100 * 1e9;
        uint256 ohmBalance = ohm.balanceOf(alice);
        uint256 reserveBalance = reserve.balanceOf(alice);

        /// Calculate expected difference
        uint256 lowWallPrice = range.price(true, false);
        uint256 expAmountOut = amountIn.mulDiv(1e18 * lowWallPrice, 1e9 * 1e18);

        /// Swap at the high wall
        vm.prank(alice);
        uint256 amountOut = operator.swap(ohm, amountIn, expAmountOut);

        /// Get updated capacity of the high wall
        uint256 endCapacity = range.capacity(false);

        assertEq(amountOut, expAmountOut);
        assertEq(endCapacity, startCapacity - amountOut);
        assertEq(ohm.balanceOf(alice), ohmBalance - amountIn);
        assertEq(reserve.balanceOf(alice), reserveBalance + amountOut);
    }

    function testCorrectness_highWallBreaksAtThreshold() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        assertEq(endCapacity, startCapacity - amountOut);
        assertEq(ohm.balanceOf(alice), ohmBalance + amountOut);
        assertEq(reserve.balanceOf(alice), reserveBalance - amountIn);
    }

    function testCorrectness_lowWallBreaksAtThreshold() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm wall is up
        assertTrue(range.active(true));

        /// Take down wall with helper function
        knockDownWall(true);

        /// Try to swap, expect to fail
        uint256 amountIn = 100 * 1e18;
        uint256 expAmountOut = amountIn.mulDiv(1e9 * 1e18, 1e18 * range.price(true, true));

        bytes memory err = abi.encodeWithSignature("Operator_WallDown()");
        vm.expectRevert(err);
        vm.prank(alice);
        operator.swap(reserve, amountIn, expAmountOut);
    }

    function testCorrectness_cannotSwapLowWallWhenDown() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm wall is up
        assertTrue(range.active(false));

        /// Take down wall with helper function
        knockDownWall(false);

        /// Try to swap, expect to fail
        uint256 amountIn = 100 * 1e9;
        uint256 expAmountOut = amountIn.mulDiv(1e18 * range.price(true, false), 1e9 * 1e18);

        bytes memory err = abi.encodeWithSignature("Operator_WallDown()");
        vm.expectRevert(err);
        vm.prank(alice);
        operator.swap(ohm, amountIn, expAmountOut);
    }

    function testCorrectness_cannotSwapHighWallWithStalePrice() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm wall is up
        assertTrue(range.active(true));

        /// Set timestamp forward so price is stale
        vm.warp(block.timestamp + 3 * uint256(price.observationFrequency()) + 1);

        /// Try to swap, expect to fail
        uint256 amountIn = 100 * 1e18;
        uint256 expAmountOut = amountIn.mulDiv(1e9 * 1e18, 1e18 * range.price(true, true));

        bytes memory err = abi.encodeWithSignature("Operator_Inactive()");
        vm.expectRevert(err);
        vm.prank(alice);
        operator.swap(reserve, amountIn, expAmountOut);
    }

    function testCorrectness_cannotSwapLowWallWithStalePrice() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm wall is up
        assertTrue(range.active(false));

        /// Set timestamp forward so price is stale
        vm.warp(block.timestamp + 3 * uint256(price.observationFrequency()) + 1);

        /// Try to swap, expect to fail
        uint256 amountIn = 100 * 1e9;
        uint256 expAmountOut = amountIn.mulDiv(1e18 * range.price(true, false), 1e9 * 1e18);

        bytes memory err = abi.encodeWithSignature("Operator_Inactive()");
        vm.expectRevert(err);
        vm.prank(alice);
        operator.swap(ohm, amountIn, expAmountOut);
    }

    function testCorrectness_swapRevertsOnSlippage() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm walls are up
        assertTrue(range.active(true));
        assertTrue(range.active(false));

        /// Set amounts for high wall swap with minAmountOut greater than expAmountOut
        uint256 amountIn = 100 * 1e18;
        uint256 expAmountOut = amountIn.mulDiv(1e9 * 1e18, 1e18 * range.price(true, true));
        uint256 minAmountOut = expAmountOut + 1;

        /// Try to swap at low wall, expect to fail
        bytes memory err = abi.encodeWithSignature(
            "Operator_AmountLessThanMinimum(uint256,uint256)",
            expAmountOut,
            minAmountOut
        );
        vm.expectRevert(err);
        vm.prank(alice);
        operator.swap(reserve, amountIn, minAmountOut);

        /// Set amounts for low wall swap with minAmountOut greater than expAmountOut
        amountIn = 100 * 1e9;
        expAmountOut = amountIn.mulDiv(1e18 * range.price(true, false), 1e9 * 1e18);
        minAmountOut = expAmountOut + 1;

        /// Try to swap at low wall, expect to fail
        err = abi.encodeWithSignature(
            "Operator_AmountLessThanMinimum(uint256,uint256)",
            expAmountOut,
            minAmountOut
        );
        vm.expectRevert(err);
        vm.prank(alice);
        operator.swap(ohm, amountIn, minAmountOut);
    }

    function testCorrectness_swapRevertsWithInvalidToken() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm walls are up
        assertTrue(range.active(true));
        assertTrue(range.active(false));

        /// Try to swap with invalid token, expect to fail
        uint256 amountIn = 100 * 1e18;
        uint256 minAmountOut = 100 * 1e18;
        ERC20 token = ERC20(bob);

        bytes memory err = abi.encodeWithSignature("Operator_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(alice);
        operator.swap(token, amountIn, minAmountOut);
    }

    // =========  CUSHION TESTS ========= //

    /// DONE
    /// [X] Cushions deployed when price set in the range and operate triggered
    /// [X] Cushions deactivated when price out of range and operate triggered or when wall goes down
    /// [X] Cushion doesn't deploy when wall is down
    /// [X] Bond purchases update capacity

    function testCorrectness_highCushionDeployedInSpread() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(true)));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(111 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        uint256 marketId = range.market(true);
        assertTrue(auctioneer.isLive(marketId));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(marketId);
        // console2.log("capacity", marketCapacity);
        assertEq(marketCapacity, range.capacity(true).mulDiv(config.cushionFactor, 1e4));

        /// Check that the price is set correctly
        // (, , , , , , , , , , , uint256 scale) = auctioneer.markets(marketId);
        // uint256 price = auctioneer.marketPrice(marketId);
        // console2.log("price", price);
        // console2.log("scale", scale);
        uint256 payout = auctioneer.payoutFor(111 * 1e18, marketId, alice);
        assertEq(payout, 1e9);
    }

    function testCorrectness_highCushionClosedBelowSpread() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(true)));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(111 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        assertTrue(auctioneer.isLive(range.market(true)));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(range.market(true));
        assertEq(marketCapacity, range.capacity(true).mulDiv(config.cushionFactor, 1e4));

        /// Set price on mock oracle below the high cushion
        price.setLastPrice(105 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(range.market(true)));

        marketCapacity = auctioneer.currentCapacity(range.market(true));
        assertEq(marketCapacity, 0);
    }

    function testCorrectness_highCushionClosedAboveSpread() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(true)));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(111 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        assertTrue(auctioneer.isLive(range.market(true)));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(range.market(true));
        assertEq(marketCapacity, range.capacity(true).mulDiv(config.cushionFactor, 1e4));

        /// Set price on mock oracle below the high cushion
        price.setLastPrice(130 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(range.market(true)));

        marketCapacity = auctioneer.currentCapacity(range.market(true));
        assertEq(marketCapacity, 0);
    }

    function testCorrectness_highCushionClosedWhenWallDown() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(true)));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(111 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed
        assertTrue(auctioneer.isLive(range.market(true)));

        /// Take down the wall
        knockDownWall(true);

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(range.market(true)));
    }

    function testCorrectness_highCushionNotDeployedWhenWallDown() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(true)));

        /// Take down the wall
        knockDownWall(true);

        /// Set price on mock oracle into the low cushion
        price.setLastPrice(111 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(true)));
    }

    function testCorrectness_lowCushionDeployedInSpread() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(false)));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(89 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        uint256 marketId = range.market(false);
        assertTrue(auctioneer.isLive(marketId));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(marketId);
        assertEq(marketCapacity, range.capacity(false).mulDiv(config.cushionFactor, 1e4));

        /// Check that the price is set correctly
        // (, , , , , , , , , , , uint256 scale) = auctioneer.markets(marketId);
        // uint256 price = auctioneer.marketPrice(marketId);
        // console2.log("price", price);
        // console2.log("scale", scale);
        uint256 payout = auctioneer.payoutFor(1e9, marketId, alice);
        assertGe(payout, (89 * 1e18 * 99999) / 100000); // Compare to a range due to slight precision differences
        assertLe(payout, (89 * 1e18 * 100001) / 100000);
    }

    function testCorrectness_lowCushionClosedBelowSpread() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(false)));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(89 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        assertTrue(auctioneer.isLive(range.market(false)));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(range.market(false));
        assertEq(marketCapacity, range.capacity(false).mulDiv(config.cushionFactor, 1e4));

        /// Set price on mock oracle below the high cushion
        price.setLastPrice(79 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(range.market(false)));

        marketCapacity = auctioneer.currentCapacity(range.market(false));
        assertEq(marketCapacity, 0);
    }

    function testCorrectness_lowCushionClosedAboveSpread() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(false)));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(89 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        assertTrue(auctioneer.isLive(range.market(false)));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(range.market(false));
        assertEq(marketCapacity, range.capacity(false).mulDiv(config.cushionFactor, 1e4));

        /// Set price on mock oracle below the high cushion
        price.setLastPrice(91 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(range.market(false)));

        marketCapacity = auctioneer.currentCapacity(range.market(false));
        assertEq(marketCapacity, 0);
    }

    function testCorrectness_lowCushionClosedWhenWallDown() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(false)));

        /// Set price on mock oracle into the low cushion
        price.setLastPrice(89 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed
        assertTrue(auctioneer.isLive(range.market(false)));

        /// Take down the wall
        knockDownWall(false);

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(range.market(false)));
    }

    function testCorrectness_lowCushionNotDeployedWhenWallDown() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(false)));

        /// Take down the wall
        knockDownWall(false);

        /// Set price on mock oracle into the low cushion
        price.setLastPrice(89 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is not deployed
        assertTrue(!auctioneer.isLive(range.market(false)));
    }

    function test_marketClosesAsExpected1() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Assert high wall is up
        assertTrue(range.active(true));

        /// Set price below the moving average to almost regenerate high wall
        price.setLastPrice(99 * 1e18);

        /// Trigger the operator function enough times to almost regenerate the high wall
        for (uint256 i; i < 4; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Ensure market not live yet
        uint256 currentMarket = range.market(true);
        assertEq(type(uint256).max, currentMarket);

        /// Cause price to spike to trigger high cushion
        uint256 cushionPrice = range.price(false, true);
        price.setLastPrice(cushionPrice + 500);
        vm.prank(heart);
        operator.operate();

        /// Check market is live
        currentMarket = range.market(true);
        assertTrue(type(uint256).max != currentMarket);
        assertTrue(auctioneer.isLive(currentMarket));

        /// Cause price to go back down to moving average
        /// Move time forward past the regen period to trigger high wall regeneration
        vm.warp(block.timestamp + 1 hours);

        /// Will trigger regeneration of high wall
        /// Will set the operator market on high side to type(uint256).max
        /// However, the prior market will still be live when it's supposed to be deactivated
        price.setLastPrice(95 * 1e18);
        vm.prank(heart);
        operator.operate();
        /// Get latest market
        uint256 newMarket = range.market(true);

        /// Check market has been updated to non existent market
        assertTrue(type(uint256).max == newMarket);
        /// And, the previous market is closed
        assertTrue(!auctioneer.isLive(currentMarket));
    }

    function test_marketClosesAsExpected2() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Assert high wall is up
        assertTrue(range.active(true));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(111 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Get current market
        uint256 currentMarket = range.market(true);

        /// Check market has been updated and is live
        assertTrue(type(uint256).max != currentMarket);
        assertTrue(auctioneer.isLive(currentMarket));

        /// Take down wall
        knockDownWall(true);

        /// Get latest market
        uint256 newMarket = range.market(true);

        /// Check market has been updated to non existent market
        assertTrue(type(uint256).max == newMarket);
        /// And the previous market is closed
        assertTrue(!auctioneer.isLive(currentMarket));
    }

    function testCorrectness_highCushionPurchasesReduceCapacity() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Get the start capacity of the high side
        uint256 startCapacity = range.capacity(true);

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(111 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed
        uint256 id = range.market(true);
        assertTrue(auctioneer.isLive(id));

        /// Set amount to purchase from cushion (which will be at wall price initially)
        uint256 amountIn = auctioneer.maxAmountAccepted(id, guardian) / 2;
        uint256 minAmountOut = auctioneer.payoutFor(amountIn, id, guardian);

        /// Purchase from cushion
        vm.prank(alice);
        (uint256 payout, ) = teller.purchase(alice, guardian, id, amountIn, minAmountOut);

        /// Check that the side capacity has been reduced by the amount of the payout
        assertEq(range.capacity(true), startCapacity - payout);

        /// Set timestamp forward so that price is stale
        vm.warp(block.timestamp + uint256(price.observationFrequency()) * 3 + 1);

        /// Try to purchase another bond and expect to revert
        amountIn = auctioneer.maxAmountAccepted(id, guardian) / 2;
        minAmountOut = auctioneer.payoutFor(amountIn, id, guardian);

        vm.expectRevert(abi.encodeWithSignature("Operator_Inactive()"));
        vm.prank(alice);
        teller.purchase(alice, guardian, id, amountIn, minAmountOut);
    }

    function testCorrectness_lowCushionPurchasesReduceCapacity() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Get the start capacity of the low side
        uint256 startCapacity = range.capacity(false);

        /// Set price on mock oracle into the low cushion
        price.setLastPrice(89 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed
        uint256 id = range.market(false);
        assertTrue(auctioneer.isLive(id));

        /// Set amount to purchase from cushion (which will be at wall price initially)
        uint256 amountIn = auctioneer.maxAmountAccepted(id, guardian) / 2;
        uint256 minAmountOut = auctioneer.payoutFor(amountIn, id, guardian);

        /// Purchase from cushion
        vm.prank(alice);
        (uint256 payout, ) = teller.purchase(alice, guardian, id, amountIn, minAmountOut);

        /// Check that the side capacity has been reduced by the amount of the payout
        assertEq(range.capacity(false), startCapacity - payout);

        /// Set timestamp forward so that price is stale
        vm.warp(block.timestamp + uint256(price.observationFrequency()) * 3 + 1);

        /// Try to purchase another bond and expect to revert
        amountIn = auctioneer.maxAmountAccepted(id, guardian) / 2;
        minAmountOut = auctioneer.payoutFor(amountIn, id, guardian);

        vm.expectRevert(abi.encodeWithSignature("Operator_Inactive()"));
        vm.prank(alice);
        teller.purchase(alice, guardian, id, amountIn, minAmountOut);
    }

    // =========  REGENERATION TESTS ========= //

    /// DONE
    /// [X] Wall regenerates when price on other side of MA for enough observations
    /// [X] Wrap around logic works for counting observations
    /// [X] Regen period enforces a minimum time to wait for regeneration

    function testCorrectness_lowWallRegenA() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        assertLe(startCapacity, fullCapacity.mulDiv(range.thresholdFactor(), 1e4));

        /// Set price above the moving average to regenerate low wall
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 5; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is up
        assertTrue(range.active(false));

        /// Check that the capacity has regenerated
        uint256 endCapacity = range.capacity(false);
        assertEq(endCapacity, fullCapacity);
    }

    function testCorrectness_lowWallRegenB() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        assertLe(startCapacity, fullCapacity.mulDiv(range.thresholdFactor(), 1e4));

        /// Set price below the moving average so regeneration doesn't start
        price.setLastPrice(98 * 1e18);

        /// Trigger the operator function with negative
        for (uint256 i; i < 8; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(false));

        /// Set price above the moving average to regenerate low wall
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 5; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is up
        assertTrue(range.active(false));

        /// Check that the capacity has regenerated
        uint256 endCapacity = range.capacity(false);
        assertEq(endCapacity, fullCapacity);
    }

    function testCorrectness_lowWallRegenC() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        assertLe(startCapacity, fullCapacity.mulDiv(range.thresholdFactor(), 1e4));

        /// Set price above the moving average to regenerate low wall
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 4; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(false));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = range.capacity(false);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_lowWallRegenD() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        assertLe(startCapacity, fullCapacity.mulDiv(range.thresholdFactor(), 1e4));

        /// Set price above the moving average to regenerate low wall
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator once to get a positive check
        vm.prank(heart);
        operator.operate();

        /// Set price below the moving average to get negative checks
        price.setLastPrice(99 * 1e18);

        /// Trigger the operator function several times with negative checks
        for (uint256 i; i < 3; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Set price above the moving average to regenerate low wall
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator function several times with positive checks
        for (uint256 i; i < 4; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(false));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = range.capacity(false);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_lowWallRegenTime() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        assertLe(startCapacity, fullCapacity.mulDiv(range.thresholdFactor(), 1e4));

        /// Set price above the moving average to regenerate low wall
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 5; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(false));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = range.capacity(false);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_lowCushionClosedOnRegen() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Tests that a manually regenerated wall will close the cushion that is deployed currently

        /// Trigger a cushion
        price.setLastPrice(89 * 1e18);
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed
        assertTrue(auctioneer.isLive(range.market(false)));
        assertEq(range.market(false), 0);

        /// Regenerate the wall manually, expect market to close
        vm.prank(policy);
        operator.regenerate(false);

        /// Check that the market is closed
        assertTrue(!auctioneer.isLive(range.market(false)));
        assertEq(range.market(false), type(uint256).max);
    }

    function testCorrectness_highWallRegenA() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        assertLe(startCapacity, fullCapacity.mulDiv(range.thresholdFactor(), 1e4));

        /// Set price below the moving average to regenerate high wall
        price.setLastPrice(99 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 5; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is up
        assertTrue(range.active(true));

        /// Check that the capacity has regenerated
        uint256 endCapacity = range.capacity(true);
        assertEq(endCapacity, fullCapacity);
    }

    function testCorrectness_highWallRegenB() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        assertLe(startCapacity, fullCapacity.mulDiv(range.thresholdFactor(), 1e4));

        /// Set price above the moving average so regeneration doesn't start
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator function with negative
        for (uint256 i; i < 8; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(true));

        /// Set price below the moving average to regenerate high wall
        price.setLastPrice(98 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 5; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is up
        assertTrue(range.active(true));

        /// Check that the capacity has regenerated
        uint256 endCapacity = range.capacity(true);
        assertEq(endCapacity, fullCapacity);
    }

    function testCorrectness_highWallRegenC() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        assertLe(startCapacity, fullCapacity.mulDiv(range.thresholdFactor(), 1e4));

        /// Set price below the moving average to regenerate high wall
        price.setLastPrice(98 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 4; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(true));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = range.capacity(true);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_highWallRegenD() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        assertLe(startCapacity, fullCapacity.mulDiv(range.thresholdFactor(), 1e4));

        /// Set price below the moving average to regenerate low wall
        price.setLastPrice(98 * 1e18);

        /// Trigger the operator once to get a positive check
        vm.prank(heart);
        operator.operate();

        /// Set price above the moving average to get negative checks
        price.setLastPrice(101 * 1e18);

        /// Trigger the operator function several times with negative checks
        for (uint256 i; i < 3; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Set price below the moving average to regenerate high wall
        price.setLastPrice(98 * 1e18);

        /// Trigger the operator function several times with positive checks
        for (uint256 i; i < 4; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(true));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = range.capacity(true);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_highWallRegenTime() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        assertLe(startCapacity, fullCapacity.mulDiv(range.thresholdFactor(), 1e4));

        /// Set price below the moving average to regenerate high wall
        price.setLastPrice(99 * 1e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 5; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!range.active(true));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = range.capacity(true);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_highCushionClosedOnRegen() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Tests that a manually regenerated wall will close the cushion that is deployed currently

        /// Trigger a cushion
        price.setLastPrice(111 * 1e18);
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed
        assertTrue(auctioneer.isLive(range.market(true)));
        assertEq(range.market(true), 0);

        /// Regenerate the wall manually, expect market to close
        vm.prank(policy);
        operator.regenerate(true);

        /// Check that the market is closed
        assertTrue(!auctioneer.isLive(range.market(true)));
        assertEq(range.market(true), type(uint256).max);
    }

    // =========  ACCESS CONTROL TESTS ========= //

    /// DONE
    /// [X] operate only callable by heart
    /// [X] admin configuration functions only callable by policy or guardian (negative here, positive in ADMIN TESTS sections)

    function testCorrectness_onlyHeartCanOperate() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Call operate as heart contract
        vm.prank(heart);
        operator.operate();

        /// Try to call operate as anyone else
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("operator_operate")
        );
        vm.expectRevert(err);
        vm.prank(alice);
        operator.operate();
    }

    function testCorrectness_cannotOperatorIfNotInitialized() public {
        /// Toggle operator to active manually erroneously (so it will not revert with inactive)
        vm.prank(policy);
        operator.activate();

        /// Call operate as heart contract and expect to revert
        bytes memory err = abi.encodeWithSignature("Operator_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(heart);
        operator.operate();
    }

    function testCorrectness_nonPolicyCannotSetConfig() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Try to set spreads as random user, expect revert
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("operator_policy")
        );
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
        operator.setCushionParams(uint32(6 hours), uint32(50_000), uint32(4 hours));

        /// Try to set cushionFactor as random user, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        operator.setReserveFactor(1500);

        /// Try to set regenParams as a random user, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        operator.setRegenParams(uint32(1 days), uint32(8), uint32(11));

        /// Try to set bond contracts as random user, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        operator.setBondContracts(IBondSDA(alice), BondCallback(alice));

        /// Try to activate/deactivate the operator as random user, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        operator.activate();

        vm.expectRevert(err);
        vm.prank(alice);
        operator.deactivate();

        vm.expectRevert(err);
        vm.prank(alice);
        operator.deactivateCushion(true);

        /// Try to regenerate as a random user, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        operator.regenerate(true);

        vm.expectRevert(err);
        vm.prank(alice);
        operator.regenerate(false);
    }

    function testCorrectness_nonGuardianCannotCall() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("operator_admin")
        );

        /// Try to initialize as a random user, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        operator.initialize();
    }

    // =========  ADMIN TESTS ========= //

    /// DONE
    /// [X] setSpreads
    /// [X] setThresholdFactor
    /// [X] setCushionFactor
    /// [X] setCushionParams
    /// [X] setReserveFactor
    /// [X] setRegenParams
    /// [X] setBondContracts
    /// [X] initialize
    /// [X] regenerate
    /// [X] activate
    /// [X] deactivate
    /// [X] deactivateCushion

    function testCorrectness_setSpreads() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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

    function testCorrectness_setThresholdFactor() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Check that the threshold factor is the same as initialized
        assertEq(range.thresholdFactor(), 100);

        /// Set threshold factor larger as admin
        vm.prank(policy);
        operator.setThresholdFactor(150);

        /// Check that the threshold factor has been updated
        assertEq(range.thresholdFactor(), 150);
    }

    function testCorrectness_cannotSetSpreadWithInvalidParams() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Get starting cushion params
        Operator.Config memory startConfig = operator.config();

        /// Set cushion params as admin
        vm.prank(policy);
        operator.setCushionParams(uint32(24 hours), uint32(50_000), uint32(4 hours));

        /// Get new cushion params
        Operator.Config memory newConfig = operator.config();

        /// Check that the cushion params has been set
        assertEq(newConfig.cushionDuration, uint32(24 hours));
        assertLt(newConfig.cushionDuration, startConfig.cushionDuration);
        assertEq(newConfig.cushionDebtBuffer, uint32(50_000));
        assertLt(newConfig.cushionDebtBuffer, startConfig.cushionDebtBuffer);
        assertEq(newConfig.cushionDepositInterval, uint32(4 hours));
        assertGt(newConfig.cushionDepositInterval, startConfig.cushionDepositInterval);
    }

    function testCorrectness_cannotSetCushionParamsWithInvalidParams() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Set cushion params with invalid duration as admin (too low)
        bytes memory err = abi.encodeWithSignature("Operator_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setCushionParams(uint32(1 days) - 1, uint32(100_000), uint32(1 hours));

        /// Set cushion params with invalid duration as admin (too high)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setCushionParams(uint32(7 days) + 1, uint32(100_000), uint32(1 hours));

        /// Set cushion params with deposit interval greater than duration as admin
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setCushionParams(uint32(1 days), uint32(100_000), uint32(2 days));

        /// Set cushion params with invalid debt buffer as admin (too low)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setCushionParams(uint32(2 days), uint32(99), uint32(2 hours));
    }

    function testCorrectness_setReserveFactor() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

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
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Get starting regen params
        Operator.Config memory startConfig = operator.config();

        /// Confirm cannot set with invalid params
        bytes memory err = abi.encodeWithSignature("Operator_InvalidParams()");
        /// Case 1: wait < 1 hours
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setRegenParams(uint32(1 hours) - 1, uint32(11), uint32(15));

        /// Case 2: observe == 0
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setRegenParams(uint32(7 days), uint32(0), uint32(0));

        /// Case 3: threshold == 0
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setRegenParams(uint32(7 days), uint32(0), uint32(10));

        /// Case 4: observe < threshold
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setRegenParams(uint32(7 days), uint32(10), uint32(9));

        /// Case 5: wait / frequency < observe - threshold
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setRegenParams(uint32(1 days), uint32(10), uint32(15));

        /// Set regen params as admin with valid params
        vm.prank(policy);
        operator.setRegenParams(uint32(7 days), uint32(11), uint32(15));

        /// Get new regen params
        Operator.Config memory newConfig = operator.config();

        /// Check that the regen params have been set
        assertEq(newConfig.regenWait, uint256(7 days));
        assertEq(newConfig.regenThreshold, 11);
        assertEq(newConfig.regenObserve, 15);
        assertGt(newConfig.regenWait, startConfig.regenWait);
        assertGt(newConfig.regenThreshold, startConfig.regenThreshold);
        assertGt(newConfig.regenObserve, startConfig.regenObserve);

        /// Check that the regen structs have been re-initialized
        Operator.Status memory status = operator.status();
        assertEq(status.high.count, 0);
        assertEq(status.high.nextObservation, 0);
        assertEq(status.low.count, 0);
        assertEq(status.low.nextObservation, 0);
        for (uint256 i; i < 15; ++i) {
            assertTrue(!status.high.observations[i]);
            assertTrue(!status.low.observations[i]);
        }
    }

    function testCorrectness_setBondContracts() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Attempt to set bond contracts to zero address and expect revert
        bytes memory err = abi.encodeWithSignature("Operator_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setBondContracts(IBondSDA(address(0)), BondCallback(address(0)));

        /// Create new bond contracts
        BondFixedTermSDA newSDA = new BondFixedTermSDA(teller, aggregator, guardian, auth);
        BondCallback newCb = new BondCallback(kernel, IBondAggregator(address(aggregator)), ohm);

        /// Update the bond contracts as guardian
        vm.prank(policy);
        operator.setBondContracts(IBondSDA(address(newSDA)), newCb);

        /// Check that the bond contracts have been set
        assertEq(address(operator.auctioneer()), address(newSDA));
        assertEq(address(operator.callback()), address(newCb));
    }

    function testCorrectness_initialize() public {
        /// Confirm that the operator is not initialized yet and walls are down
        assertTrue(!operator.initialized());
        assertTrue(!operator.active());
        assertTrue(!range.active(true));
        assertTrue(!range.active(false));
        assertEq(treasury.withdrawApproval(address(operator), reserve), 0);
        assertEq(range.price(false, false), 0);
        assertEq(range.price(true, false), 0);
        assertEq(range.price(false, true), 0);
        assertEq(range.price(true, true), 0);
        assertEq(range.capacity(false), 0);
        assertEq(range.capacity(true), 0);

        /// Initialize the operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the operator is initialized and walls are up
        assertTrue(operator.initialized());
        assertTrue(operator.active());
        assertTrue(range.active(true));
        assertTrue(range.active(false));
        assertEq(treasury.withdrawApproval(address(operator), reserve), range.capacity(false));
        assertGt(range.price(false, false), 0);
        assertGt(range.price(true, false), 0);
        assertGt(range.price(false, true), 0);
        assertGt(range.price(true, true), 0);
        assertGt(range.capacity(false), 0);
        assertGt(range.capacity(true), 0);
    }

    function testCorrectness_cannotInitializeTwice() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Try to initialize the operator again as guardian
        bytes memory err = abi.encodeWithSignature("Operator_AlreadyInitialized()");
        vm.expectRevert(err);
        vm.prank(guardian);
        operator.initialize();
    }

    function testCorrectness_regenerate() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        uint48 startTime = uint48(block.timestamp);
        vm.warp(block.timestamp + 1 hours);
        uint48 newTime = uint48(block.timestamp);

        /// Confirm that both sides are currently up
        assertTrue(range.active(true));
        assertTrue(range.active(false));

        /// Confirm that the Regen structs are at the initial state
        Operator.Status memory status = operator.status();
        assertEq(status.high.count, uint32(0));
        assertEq(status.high.nextObservation, uint32(0));
        assertEq(status.high.lastRegen, startTime);
        assertEq(status.low.count, uint32(0));
        assertEq(status.low.nextObservation, uint32(0));
        assertEq(status.low.lastRegen, startTime);

        /// Call operate twice, at different price points, to make the regen counts higher than zero
        price.setLastPrice(105 * 1e18);
        vm.prank(heart);
        operator.operate();

        price.setLastPrice(95 * 1e18);
        vm.prank(heart);
        operator.operate();

        /// Confirm that the Regen structs are updated
        status = operator.status();
        assertEq(status.high.count, uint32(1));
        assertEq(status.high.nextObservation, uint32(2));
        assertEq(status.high.lastRegen, startTime);
        assertEq(status.low.count, uint32(1));
        assertEq(status.low.nextObservation, uint32(2));
        assertEq(status.low.lastRegen, startTime);

        /// Knock down both walls
        knockDownWall(true);
        knockDownWall(false);

        /// Confirm that both sides are now down
        assertTrue(!range.active(true));
        assertTrue(!range.active(false));

        /// Try to call regenerate without being guardian and expect revert
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("operator_policy")
        );

        vm.expectRevert(err);
        vm.prank(alice);
        operator.regenerate(true);

        vm.expectRevert(err);
        vm.prank(alice);
        operator.regenerate(false);

        /// Confirm that the Regen structs are the same as before and walls are still down
        status = operator.status();
        assertEq(status.high.count, uint32(1));
        assertEq(status.high.nextObservation, uint32(2));
        assertEq(status.low.count, uint32(1));
        assertEq(status.low.nextObservation, uint32(2));
        assertTrue(!range.active(true));
        assertTrue(!range.active(false));

        /// Call regenerate as policy and confirm each side is updated
        vm.prank(policy);
        operator.regenerate(true);

        vm.prank(policy);
        operator.regenerate(false);

        /// Confirm that the sides have regenerated and the Regen structs are reset
        status = operator.status();
        assertEq(status.high.count, uint32(0));
        assertEq(status.high.nextObservation, uint32(0));
        assertEq(status.high.lastRegen, newTime);
        assertEq(status.low.count, uint32(0));
        assertEq(status.low.nextObservation, uint32(0));
        assertEq(status.low.lastRegen, newTime);
        assertTrue(range.active(true));
        assertTrue(range.active(false));
    }

    function testCorrectness_cannotPerformMarketOpsWhileInactive() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Toggle the operator to inactive
        vm.prank(policy);
        operator.deactivate();

        /// Try to call operator, swap, and bondPurchase, expect reverts
        bytes memory err = abi.encodeWithSignature("Operator_Inactive()");
        vm.expectRevert(err);
        vm.prank(heart);
        operator.operate();

        vm.expectRevert(err);
        vm.prank(alice);
        operator.swap(ohm, 1e9, 1);

        vm.expectRevert(err);
        vm.prank(alice);
        operator.swap(reserve, 1e18, 1);

        vm.expectRevert(err);
        vm.prank(address(callback));
        operator.bondPurchase(0, 1e18);

        // Activate the operator again
        vm.prank(policy);
        operator.activate();

        /// Confirm that the operator is active
        vm.prank(heart);
        operator.operate();

        vm.prank(alice);
        operator.swap(ohm, 1e9, 1);

        vm.prank(alice);
        operator.swap(reserve, 1e18, 1);
    }

    function testCorrectness_deactivateShutsdownCushions() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Assert high wall is up
        assertTrue(range.active(true));

        /// Set price on mock oracle into the high cushion
        price.setLastPrice(111 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Get current market
        uint256 currentMarket = range.market(true);

        /// Check market has been updated and is live
        assertTrue(type(uint256).max != currentMarket);
        assertTrue(auctioneer.isLive(currentMarket));

        /// Deactivate the operator
        vm.prank(policy);
        operator.deactivate();

        /// Check market has been updated and is not live
        assertTrue(!auctioneer.isLive(currentMarket));
        assertEq(type(uint256).max, range.market(true));

        /// Reactivate the operator
        vm.prank(policy);
        operator.activate();

        /// Set price on mock oracle into the low cushion
        price.setLastPrice(89 * 1e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Get current market
        currentMarket = range.market(false);

        /// Check market has been updated and is live
        assertTrue(type(uint256).max != currentMarket);
        assertTrue(auctioneer.isLive(currentMarket));

        /// Deactivate the operator
        vm.prank(policy);
        operator.deactivate();

        /// Check market has been updated and is not live
        assertTrue(!auctioneer.isLive(currentMarket));
        assertEq(type(uint256).max, range.market(false));
    }

    // =========  VIEW TESTS ========= //

    /// DONE
    /// [X] fullCapacity
    /// [X] getAmountOut

    function testCorrectness_viewFullCapacity() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Load config
        Operator.Config memory config = operator.config();

        /// Check that fullCapacity returns the full capacity based on the reserveFactor
        uint256 resInTreasury = treasury.getReserveBalance(reserve);
        uint256 lowCapacity = resInTreasury.mulDiv(config.reserveFactor, 1e4);
        uint256 highCapacity = (lowCapacity.mulDiv(
            1e9 * 10**price.decimals(),
            1e18 * range.price(true, true)
        ) * (1e4 + range.spread(true) * 2)) / 1e4;

        assertEq(operator.fullCapacity(false), lowCapacity);
        assertEq(operator.fullCapacity(true), highCapacity);
    }

    function testCorrectness_viewGetAmountOut() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Check that getAmountOut returns the amount of token to receive for different combinations of inputs
        /// Case 1: OHM In, less than capacity
        uint256 amountIn = 100 * 1e9;
        uint256 expAmountOut = amountIn.mulDiv(1e18 * range.price(true, false), 1e9 * 1e18);

        assertEq(expAmountOut, operator.getAmountOut(ohm, amountIn));

        /// Case 2: OHM In, more than capacity
        amountIn = range.capacity(false).mulDiv(1e9 * 1e18, 1e18 * range.price(true, false)) + 1e9;

        bytes memory err = abi.encodeWithSignature("Operator_InsufficientCapacity()");
        vm.expectRevert(err);
        operator.getAmountOut(ohm, amountIn);

        /// Case 3: Reserve In, less than capacity
        amountIn = 10000 * 1e18;
        expAmountOut = amountIn.mulDiv(1e9 * 1e18, 1e18 * range.price(true, true));

        assertEq(expAmountOut, operator.getAmountOut(reserve, amountIn));

        /// Case 4: Reserve In, more than capacity
        amountIn = range.capacity(true).mulDiv(1e18 * range.price(true, true), 1e9 * 1e18) + 1e18;

        vm.expectRevert(err);
        operator.getAmountOut(reserve, amountIn);

        /// Case 5: Random, non-accepted token
        err = abi.encodeWithSignature("Operator_InvalidParams()");
        ERC20 token = ERC20(bob);
        amountIn = 100 * 1e18;
        vm.expectRevert(err);
        operator.getAmountOut(token, amountIn);
    }

    // =========  INTERNAL FUNCTION TESTS ========= //

    /// DONE
    /// [X] Range updates from new price data when operate is called (triggers _updateRange)

    function testCorrectness_updateRange() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Store the starting bands
        OlympusRange.Range memory startRange = range.range();

        /// Update moving average upwards and trigger the operator
        price.setMovingAverage(105 * 1e18);
        vm.prank(heart);
        operator.operate();

        /// Check that the bands have updated
        assertGt(range.price(false, false), startRange.cushion.low.price);
        assertGt(range.price(true, false), startRange.wall.low.price);
        assertGt(range.price(false, true), startRange.cushion.high.price);
        assertGt(range.price(true, true), startRange.wall.high.price);

        /// Update moving average downwards and trigger the operator
        price.setMovingAverage(95 * 1e18);
        vm.prank(heart);
        operator.operate();

        /// Check that the bands have updated
        assertLt(range.price(false, false), startRange.cushion.low.price);
        assertLt(range.price(true, false), startRange.wall.low.price);
        assertLt(range.price(false, true), startRange.cushion.high.price);
        assertLt(range.price(true, true), startRange.wall.high.price);

        /// Check that the bands do not get reduced further past the minimum target price
        price.setMovingAverage(10 * 1e18); // At minimum price to get initial values
        vm.prank(heart);
        operator.operate();

        /// Get the current bands
        OlympusRange.Range memory currentRange = range.range();

        /// Move moving average below minimum target
        price.setMovingAverage(5 * 1e18);
        vm.prank(heart);
        operator.operate();

        /// Check that the bands have not changed
        assertEq(currentRange.cushion.low.price, range.price(false, false));
        assertEq(currentRange.wall.low.price, range.price(true, false));
        assertEq(currentRange.cushion.high.price, range.price(false, true));
        assertEq(currentRange.wall.high.price, range.price(true, true));
    }
}
