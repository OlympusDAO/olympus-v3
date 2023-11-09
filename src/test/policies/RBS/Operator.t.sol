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
import {MockERC4626, ERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {MockOhm} from "test/mocks/MockOhm.sol";

import {IBondSDA} from "interfaces/IBondSDA.sol";
import {IBondAggregator} from "interfaces/IBondAggregator.sol";
import {IAppraiser} from "policies/OCA/interfaces/IAppraiser.sol";

import {FullMath} from "libraries/FullMath.sol";

import "src/Kernel.sol";
import {OlympusRange} from "modules/RANGE/OlympusRange.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusSupply} from "modules/SPPLY/OlympusSupply.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {Operator} from "policies/RBS/Operator.sol";
import {Bookkeeper, AssetCategory} from "policies/OCA/Bookkeeper.sol";
import {Appraiser, IAppraiser as IAppraiserMetric} from "policies/OCA/Appraiser.sol";
import {BondCallback} from "policies/Bonds/BondCallback.sol";
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
    address internal clearinghouse;

    RolesAuthority internal auth;
    BondAggregator internal aggregator;
    BondFixedTermTeller internal teller;
    BondFixedTermSDA internal auctioneer;
    MockOhm internal ohm;
    MockGohm internal gohm;
    MockERC20 internal reserve;
    MockERC4626 internal wrappedReserve;

    Kernel internal kernel;
    OlympusRange internal RANGE;
    OlympusTreasury internal TRSRY;
    OlympusMinter internal MINTR;
    OlympusSupply internal SPPLY;
    OlympusRoles internal ROLES;
    MockPrice internal PRICE;

    Operator internal operator;
    BondCallback internal callback;
    RolesAdmin internal rolesAdmin;
    Bookkeeper internal bookkeeper;
    Appraiser internal appraiser;

    int256 internal constant CHANGE_DECIMALS = 1e4;
    uint32 internal constant OBSERVATION_FREQUENCY = 8 hours;
    uint256 internal constant GOHM_INDEX = 300000000000;
    uint8 internal constant DECIMALS = 18;

    event Swap(
        ERC20 indexed tokenIn_,
        ERC20 indexed tokenOut_,
        uint256 amountIn_,
        uint256 amountOut_
    );

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            /// Deploy bond system to test against
            address[] memory users = userCreator.create(6);
            alice = users[0];
            bob = users[1];
            guardian = users[2];
            policy = users[3];
            heart = users[4];
            clearinghouse = users[5];
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
            gohm = new MockGohm(GOHM_INDEX);
            ohm = new MockOhm("Olympus", "OHM", 9);
            reserve = new MockERC20("Reserve", "RSV", 18);
            wrappedReserve = new MockERC4626(reserve, "wrappedReserve", "sRSV");
            address[2] memory olympusTokens = [address(ohm), address(gohm)];

            /// Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            /// Deploy modules (some mocks)
            ROLES = new OlympusRoles(kernel);
            TRSRY = new OlympusTreasury(kernel);
            MINTR = new OlympusMinter(kernel, address(ohm));
            SPPLY = new OlympusSupply(kernel, olympusTokens, 0);
            PRICE = new MockPrice(kernel, DECIMALS, OBSERVATION_FREQUENCY);
            RANGE = new OlympusRange(
                kernel,
                ERC20(ohm),
                ERC20(reserve),
                uint256(100),
                [uint256(1000), uint256(2000)],
                [uint256(1000), uint256(2000)]
            );

            /// Configure Price mock
            PRICE.setPrice(address(ohm), 100e18);
            PRICE.setPrice(address(reserve), 1e18);
            PRICE.setPrice(address(wrappedReserve), 1e18);
            PRICE.setMovingAverage(address(ohm), 100e18);
            PRICE.setMovingAverage(address(reserve), 1e18);
            PRICE.setMovingAverage(address(wrappedReserve), 1e18);
        }
        {
            /// Deploy roles administrator
            rolesAdmin = new RolesAdmin(kernel);
            /// Deploy bond callback
            callback = new BondCallback(kernel, IBondAggregator(address(aggregator)), ohm);
            // Deploy new bookkeeper
            bookkeeper = new Bookkeeper(kernel);
            // Deploy new appraiser
            appraiser = new Appraiser(kernel);
            /// Deploy operator
            operator = new Operator(
                kernel,
                IAppraiser(address(appraiser)),
                IBondSDA(address(auctioneer)),
                callback,
                [address(ohm), address(reserve), address(wrappedReserve)],
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
        }

        {
            /// Initialize system and kernel

            /// Install modules
            kernel.executeAction(Actions.InstallModule, address(PRICE));
            kernel.executeAction(Actions.InstallModule, address(RANGE));
            kernel.executeAction(Actions.InstallModule, address(TRSRY));
            kernel.executeAction(Actions.InstallModule, address(SPPLY));
            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(ROLES));

            /// Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(operator));
            kernel.executeAction(Actions.ActivatePolicy, address(callback));
            kernel.executeAction(Actions.ActivatePolicy, address(appraiser));
            kernel.executeAction(Actions.ActivatePolicy, address(bookkeeper));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }
        {
            /// Configure access control

            /// Bookkeeper roles
            rolesAdmin.grantRole("bookkeeper_policy", policy);
            rolesAdmin.grantRole("bookkeeper_admin", guardian);

            /// Operator roles
            rolesAdmin.grantRole("operator_operate", address(heart));
            rolesAdmin.grantRole("operator_reporter", address(callback));
            rolesAdmin.grantRole("operator_policy", policy);
            rolesAdmin.grantRole("operator_admin", guardian);

            /// Bond callback ROLES
            rolesAdmin.grantRole("callback_whitelist", address(operator));
            rolesAdmin.grantRole("callback_whitelist", guardian);
            rolesAdmin.grantRole("callback_admin", guardian);
        }

        /// Configure treasury assets
        address[] memory locations = new address[](1);
        locations[0] = address(clearinghouse);
        vm.startPrank(policy);
        bookkeeper.addAsset(address(reserve), locations);
        bookkeeper.addAsset(address(wrappedReserve), locations);
        bookkeeper.categorizeAsset(address(reserve), AssetCategory.wrap("liquid"));
        bookkeeper.categorizeAsset(address(reserve), AssetCategory.wrap("stable"));
        bookkeeper.categorizeAsset(address(reserve), AssetCategory.wrap("reserves"));
        vm.stopPrank();

        /// Set operator on the callback
        vm.prank(guardian);
        callback.setOperator(operator);
        // Signal that reserve is held as wrappedReserve in TRSRY
        vm.prank(guardian);
        callback.useWrappedVersion(address(reserve), address(wrappedReserve));

        // Mint tokens to users and TRSRY for testing
        uint256 testOhm = 1_000_000 * 1e9;
        uint256 testReserve = 2_000_000 * 1e18;

        ohm.mint(alice, testOhm * 20);
        reserve.mint(alice, testReserve * 20);

        reserve.mint(address(TRSRY), testReserve * 100);
        // Deposit TRSRY reserves into wrappedReserve
        vm.startPrank(address(TRSRY));
        reserve.approve(address(wrappedReserve), testReserve * 100);
        wrappedReserve.deposit(testReserve * 100, address(TRSRY));
        vm.stopPrank();

        // Approve the operator and bond teller for the tokens to swap
        vm.startPrank(alice);
        ohm.approve(address(operator), testOhm * 20);
        reserve.approve(address(operator), testReserve * 20);

        ohm.approve(address(teller), testOhm * 20);
        reserve.approve(address(teller), testReserve * 20);
        vm.stopPrank();

        // Initialize appraiser liquid backing calculation
        appraiser.storeMetric(IAppraiserMetric.Metric.LIQUID_BACKING_PER_BACKED_OHM);
    }

    // ======== SETUP DEPENDENCIES ======= //

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](5);
        expectedDeps[0] = toKeycode("PRICE");
        expectedDeps[1] = toKeycode("RANGE");
        expectedDeps[2] = toKeycode("TRSRY");
        expectedDeps[3] = toKeycode("MINTR");
        expectedDeps[4] = toKeycode("ROLES");

        Keycode[] memory deps = operator.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
        assertEq(fromKeycode(deps[2]), fromKeycode(expectedDeps[2]));
        assertEq(fromKeycode(deps[3]), fromKeycode(expectedDeps[3]));
        assertEq(fromKeycode(deps[4]), fromKeycode(expectedDeps[4]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](13);
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");
        Keycode RANGE_KEYCODE = toKeycode("RANGE");
        expectedPerms[0] = Permissions(RANGE_KEYCODE, RANGE.updateCapacity.selector);
        expectedPerms[1] = Permissions(RANGE_KEYCODE, RANGE.updateMarket.selector);
        expectedPerms[2] = Permissions(RANGE_KEYCODE, RANGE.updatePrices.selector);
        expectedPerms[3] = Permissions(RANGE_KEYCODE, RANGE.regenerate.selector);
        expectedPerms[4] = Permissions(RANGE_KEYCODE, RANGE.setSpreads.selector);
        expectedPerms[5] = Permissions(RANGE_KEYCODE, RANGE.setThresholdFactor.selector);
        expectedPerms[6] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        expectedPerms[7] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        expectedPerms[8] = Permissions(TRSRY_KEYCODE, TRSRY.decreaseWithdrawApproval.selector);
        expectedPerms[9] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        expectedPerms[10] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        expectedPerms[11] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
        expectedPerms[12] = Permissions(MINTR_KEYCODE, MINTR.decreaseMintApproval.selector);
        Permissions[] memory perms = operator.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    // =========  HELPER FUNCTIONS ========= //

    function knockDownWall(bool high_) internal returns (uint256 amountIn, uint256 amountOut) {
        if (high_) {
            /// Get current capacity of the high wall
            /// Set amount in to put capacity 1 below the threshold for shutting down the wall
            uint256 startCapacity = RANGE.capacity(true);
            uint256 highWallPrice = RANGE.price(true, true);
            amountIn = startCapacity.mulDiv(highWallPrice, 1e9).mulDiv(9999, 10000) + 1;

            uint256 expAmountOut = operator.getAmountOut(reserve, amountIn);

            /// Swap at the high wall
            vm.prank(alice);
            amountOut = operator.swap(reserve, amountIn, expAmountOut);
        } else {
            /// Get current capacity of the low wall
            /// Set amount in to put capacity 1 below the threshold for shutting down the wall
            uint256 startCapacity = RANGE.capacity(false);
            uint256 lowWallPrice = RANGE.price(false, true);
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
    /// [X] Not able to swap at the walls when PRICE is stale

    function testCorrectness_swapHighWall() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Get current capacity of the high wall and starting balance for user
        uint256 startCapacity = RANGE.capacity(true);
        uint256 amountIn = 100 * 1e18;
        uint256 ohmBalance = ohm.balanceOf(alice);
        uint256 reserveBalance = reserve.balanceOf(alice);

        /// Calculate expected difference
        uint256 highWallPrice = RANGE.price(true, true);
        uint256 expAmountOut = amountIn.mulDiv(1e9 * 1e18, 1e18 * highWallPrice);
        uint256 wrappedReserveBalanceBefore = wrappedReserve.balanceOf(address(TRSRY));

        vm.expectEmit(false, false, false, true);
        emit Swap(reserve, ohm, amountIn, expAmountOut);

        /// Swap at the high wall
        vm.prank(alice);
        uint256 amountOut = operator.swap(reserve, amountIn, expAmountOut);

        /// Get updated capacity of the high wall
        uint256 endCapacity = RANGE.capacity(true);

        assertEq(amountOut, expAmountOut);
        assertEq(endCapacity, startCapacity - amountOut);
        assertEq(ohm.balanceOf(alice), ohmBalance + amountOut);
        assertEq(reserve.balanceOf(alice), reserveBalance - amountIn);
        assertEq(wrappedReserve.balanceOf(address(TRSRY)), wrappedReserveBalanceBefore + amountIn);
    }

    function testCorrectness_swapLowWall() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Get current capacity of the high wall and starting balance for user
        uint256 startCapacity = RANGE.capacity(false);
        uint256 amountIn = 100 * 1e9;
        uint256 ohmBalance = ohm.balanceOf(alice);
        uint256 reserveBalance = reserve.balanceOf(alice);

        /// Calculate expected difference
        uint256 lowWallPrice = RANGE.price(false, true);
        uint256 expAmountOut = amountIn.mulDiv(1e18 * lowWallPrice, 1e9 * 1e18);
        uint256 wrappedReserveBalanceBefore = wrappedReserve.balanceOf(address(TRSRY));

        vm.expectEmit(false, false, false, true);
        emit Swap(ohm, reserve, amountIn, expAmountOut);

        /// Swap at the high wall
        vm.prank(alice);
        uint256 amountOut = operator.swap(ohm, amountIn, expAmountOut);

        /// Get updated capacity of the high wall
        uint256 endCapacity = RANGE.capacity(false);

        assertEq(amountOut, expAmountOut);
        assertEq(endCapacity, startCapacity - amountOut);
        assertEq(ohm.balanceOf(alice), ohmBalance - amountIn);
        assertEq(reserve.balanceOf(alice), reserveBalance + amountOut);
        assertEq(
            wrappedReserve.balanceOf(address(TRSRY)),
            wrappedReserveBalanceBefore - expAmountOut
        );
    }

    function testCorrectness_highWallBreaksAtThreshold() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm wall is up
        assertTrue(RANGE.active(true));

        /// Get initial balances and capacity
        uint256 ohmBalance = ohm.balanceOf(alice);
        uint256 reserveBalance = reserve.balanceOf(alice);
        uint256 startCapacity = RANGE.capacity(true);

        /// Take down wall with helper function
        (uint256 amountIn, uint256 amountOut) = knockDownWall(true);

        /// Get updated capacity of the high wall
        uint256 endCapacity = RANGE.capacity(true);

        /// Confirm the wall is down
        assertTrue(!RANGE.active(true));

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
        assertTrue(RANGE.active(false));

        /// Get initial balances and capacity
        uint256 ohmBalance = ohm.balanceOf(alice);
        uint256 reserveBalance = reserve.balanceOf(alice);
        uint256 startCapacity = RANGE.capacity(false);

        /// Take down wall with helper function
        (uint256 amountIn, uint256 amountOut) = knockDownWall(false);

        /// Get updated capacity of the high wall
        uint256 endCapacity = RANGE.capacity(false);

        /// Confirm the wall is down
        assertTrue(!RANGE.active(false));

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
        assertTrue(RANGE.active(true));

        /// Take down wall with helper function
        knockDownWall(true);

        /// Try to swap, expect to fail
        uint256 amountIn = 100 * 1e18;
        uint256 expAmountOut = amountIn.mulDiv(1e9 * 1e18, 1e18 * RANGE.price(true, true));

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
        assertTrue(RANGE.active(false));

        /// Take down wall with helper function
        knockDownWall(false);

        /// Try to swap, expect to fail
        uint256 amountIn = 100 * 1e9;
        uint256 expAmountOut = amountIn.mulDiv(1e18 * RANGE.price(false, true), 1e9 * 1e18);

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
        assertTrue(RANGE.active(true));

        /// Set timestamp forward so price is stale
        vm.warp(block.timestamp + 3 * uint256(PRICE.observationFrequency()) + 1);

        /// Try to swap, expect to fail
        uint256 amountIn = 100 * 1e18;
        uint256 expAmountOut = amountIn.mulDiv(1e9 * 1e18, 1e18 * RANGE.price(true, true));

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
        assertTrue(RANGE.active(false));

        /// Set timestamp forward so price is stale
        vm.warp(block.timestamp + 3 * uint256(PRICE.observationFrequency()) + 1);

        /// Try to swap, expect to fail
        uint256 amountIn = 100 * 1e9;
        uint256 expAmountOut = amountIn.mulDiv(1e18 * RANGE.price(false, true), 1e9 * 1e18);

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
        assertTrue(RANGE.active(true));
        assertTrue(RANGE.active(false));

        /// Set amounts for high wall swap with minAmountOut greater than expAmountOut
        uint256 amountIn = 100 * 1e18;
        uint256 expAmountOut = amountIn.mulDiv(1e9 * 1e18, 1e18 * RANGE.price(true, true));
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
        expAmountOut = amountIn.mulDiv(1e18 * RANGE.price(false, true), 1e9 * 1e18);
        minAmountOut = expAmountOut + 1;

        /// Try to swap at high wall, expect to fail
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
        assertTrue(RANGE.active(true));
        assertTrue(RANGE.active(false));

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
    /// [X] Cushions deployed when PRICE set in the RANGE and operate triggered
    /// [X] Cushions deactivated when PRICE out of RANGE and operate triggered or when wall goes down
    /// [X] Cushion doesn't deploy when wall is down
    /// [X] Bond purchases update capacity

    function testCorrectness_highCushionDeployedInSpread() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(RANGE.market(true)));

        /// Set price on mock oracle into the high cushion
        PRICE.setPrice(address(ohm), 111e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        uint256 marketId = RANGE.market(true);
        assertTrue(auctioneer.isLive(marketId));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(marketId);
        // console2.log("capacity", marketCapacity);
        assertEq(marketCapacity, RANGE.capacity(true).mulDiv(config.cushionFactor, 1e4));

        /// Check that the PRICE is set correctly
        // (, , , , , , , , , , , uint256 scale) = auctioneer.markets(marketId);
        // uint256 PRICE = auctioneer.marketPrice(marketId);
        // console2.log("PRICE", PRICE);
        // console2.log("scale", scale);
        uint256 payout = auctioneer.payoutFor(111 * 1e18, marketId, alice);
        assertEq(payout, 1e9);
    }

    function testCorrectness_highCushionClosedBelowSpread() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(RANGE.market(true)));

        /// Set price on mock oracle into the high cushion
        PRICE.setPrice(address(ohm), 111e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        assertTrue(auctioneer.isLive(RANGE.market(true)));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(RANGE.market(true));
        assertEq(marketCapacity, RANGE.capacity(true).mulDiv(config.cushionFactor, 1e4));

        /// Set price on mock oracle below the high cushion
        PRICE.setPrice(address(ohm), 105e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(RANGE.market(true)));

        marketCapacity = auctioneer.currentCapacity(RANGE.market(true));
        assertEq(marketCapacity, 0);
    }

    function testCorrectness_highCushionClosedAboveSpread() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(RANGE.market(true)));

        /// Set price on mock oracle into the high cushion
        PRICE.setPrice(address(ohm), 111e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        assertTrue(auctioneer.isLive(RANGE.market(true)));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(RANGE.market(true));
        assertEq(marketCapacity, RANGE.capacity(true).mulDiv(config.cushionFactor, 1e4));

        /// Set price on mock oracle below the high cushion
        PRICE.setPrice(address(ohm), 130e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(RANGE.market(true)));

        marketCapacity = auctioneer.currentCapacity(RANGE.market(true));
        assertEq(marketCapacity, 0);
    }

    function testCorrectness_highCushionClosedWhenWallDown() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(RANGE.market(true)));

        /// Set price on mock oracle into the high cushion
        PRICE.setPrice(address(ohm), 111e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed
        assertTrue(auctioneer.isLive(RANGE.market(true)));

        /// Take down the wall
        knockDownWall(true);

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(RANGE.market(true)));
    }

    function testCorrectness_highCushionNotDeployedWhenWallDown() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(RANGE.market(true)));

        /// Take down the wall
        knockDownWall(true);

        /// Set price on mock oracle into the low cushion
        PRICE.setPrice(address(ohm), 111e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is not deployed
        assertTrue(!auctioneer.isLive(RANGE.market(true)));
    }

    function testCorrectness_lowCushionDeployedInSpread() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(RANGE.market(false)));

        /// Set price on mock oracle into the high cushion
        PRICE.setPrice(address(ohm), 89e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        uint256 marketId = RANGE.market(false);
        assertTrue(auctioneer.isLive(marketId));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(marketId);
        assertEq(marketCapacity, RANGE.capacity(false).mulDiv(config.cushionFactor, 1e4));

        /// Check that the PRICE is set correctly
        // (, , , , , , , , , , , uint256 scale) = auctioneer.markets(marketId);
        // uint256 PRICE = auctioneer.marketPrice(marketId);
        // console2.log("PRICE", PRICE);
        // console2.log("scale", scale);
        uint256 payout = auctioneer.payoutFor(1e9, marketId, alice);
        assertGe(payout, (89 * 1e18 * 99999) / 100000); // Compare to a RANGE due to slight precision differences
        assertLe(payout, (89 * 1e18 * 100001) / 100000);
    }

    function testCorrectness_lowCushionClosedBelowSpread() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(RANGE.market(false)));

        /// Set price on mock oracle into the high cushion
        PRICE.setPrice(address(ohm), 89e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        assertTrue(auctioneer.isLive(RANGE.market(false)));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(RANGE.market(false));
        assertEq(marketCapacity, RANGE.capacity(false).mulDiv(config.cushionFactor, 1e4));

        /// Set price on mock oracle below the high cushion
        PRICE.setPrice(address(ohm), 79e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(RANGE.market(false)));

        marketCapacity = auctioneer.currentCapacity(RANGE.market(false));
        assertEq(marketCapacity, 0);
    }

    function testCorrectness_lowCushionClosedAboveSpread() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(RANGE.market(false)));

        /// Set price on mock oracle into the high cushion
        PRICE.setPrice(address(ohm), 89e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed and capacity is set to the correct amount
        assertTrue(auctioneer.isLive(RANGE.market(false)));

        Operator.Config memory config = operator.config();
        uint256 marketCapacity = auctioneer.currentCapacity(RANGE.market(false));
        assertEq(marketCapacity, RANGE.capacity(false).mulDiv(config.cushionFactor, 1e4));

        /// Set price on mock oracle below the high cushion
        PRICE.setPrice(address(ohm), 91e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(RANGE.market(false)));

        marketCapacity = auctioneer.currentCapacity(RANGE.market(false));
        assertEq(marketCapacity, 0);
    }

    function testCorrectness_lowCushionClosedWhenWallDown() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(RANGE.market(false)));

        /// Set price on mock oracle into the low cushion
        PRICE.setPrice(address(ohm), 89e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed
        assertTrue(auctioneer.isLive(RANGE.market(false)));

        /// Take down the wall
        knockDownWall(false);

        /// Check that the cushion is closed
        assertTrue(!auctioneer.isLive(RANGE.market(false)));
    }

    function testCorrectness_lowCushionNotDeployedWhenWallDown() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the cushion is not deployed
        assertTrue(!auctioneer.isLive(RANGE.market(false)));

        /// Take down the wall
        knockDownWall(false);

        /// Set price on mock oracle into the low cushion
        PRICE.setPrice(address(ohm), 89e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is not deployed
        assertTrue(!auctioneer.isLive(RANGE.market(false)));
    }

    function test_marketClosesAsExpected1() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Assert high wall is up
        assertTrue(RANGE.active(true));

        /// Set price below the moving average to almost regenerate high wall
        PRICE.setPrice(address(ohm), 99e18);

        /// Trigger the operator function enough times to almost regenerate the high wall
        for (uint256 i; i < 4; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Ensure market not live yet
        uint256 currentMarket = RANGE.market(true);
        assertEq(type(uint256).max, currentMarket);

        /// Cause price to spike to trigger high cushion
        uint256 cushionPrice = RANGE.price(true, false);
        PRICE.setPrice(address(ohm), cushionPrice + 500);
        vm.prank(heart);
        operator.operate();

        /// Check market is live
        currentMarket = RANGE.market(true);
        assertTrue(type(uint256).max != currentMarket);
        assertTrue(auctioneer.isLive(currentMarket));

        /// Cause PRICE to go back down to moving average
        /// Move time forward past the regen period to trigger high wall regeneration
        vm.warp(block.timestamp + 1 hours);

        /// Will trigger regeneration of high wall
        /// Will set the operator market on high side to type(uint256).max
        /// However, the prior market will still be live when it's supposed to be deactivated
        PRICE.setPrice(address(ohm), 95e18);
        vm.prank(heart);
        operator.operate();
        /// Get latest market
        uint256 newMarket = RANGE.market(true);

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
        assertTrue(RANGE.active(true));

        /// Set price on mock oracle into the high cushion
        PRICE.setPrice(address(ohm), 111e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Get current market
        uint256 currentMarket = RANGE.market(true);

        /// Check market has been updated and is live
        assertTrue(type(uint256).max != currentMarket);
        assertTrue(auctioneer.isLive(currentMarket));

        /// Take down wall
        knockDownWall(true);

        /// Get latest market
        uint256 newMarket = RANGE.market(true);

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
        uint256 startCapacity = RANGE.capacity(true);

        /// Set price on mock oracle into the high cushion
        PRICE.setPrice(address(ohm), 111e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed
        uint256 id = RANGE.market(true);
        assertTrue(auctioneer.isLive(id));

        /// Set amount to purchase from cushion (which will be at wall PRICE initially)
        uint256 amountIn = auctioneer.maxAmountAccepted(id, guardian) / 2;
        uint256 minAmountOut = auctioneer.payoutFor(amountIn, id, guardian);

        /// Purchase from cushion
        vm.prank(alice);
        (uint256 payout, ) = teller.purchase(alice, guardian, id, amountIn, minAmountOut);

        /// Check that the side capacity has been reduced by the amount of the payout
        assertEq(RANGE.capacity(true), startCapacity - payout);

        /// Set timestamp forward so that price is stale
        vm.warp(block.timestamp + uint256(PRICE.observationFrequency()) * 3 + 1);

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
        uint256 startCapacity = RANGE.capacity(false);

        /// Set price on mock oracle into the low cushion
        PRICE.setPrice(address(ohm), 89e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed
        uint256 id = RANGE.market(false);
        assertTrue(auctioneer.isLive(id));

        /// Set amount to purchase from cushion (which will be at wall PRICE initially)
        uint256 amountIn = auctioneer.maxAmountAccepted(id, guardian) / 2;
        uint256 minAmountOut = auctioneer.payoutFor(amountIn, id, guardian);

        /// Purchase from cushion
        vm.prank(alice);
        (uint256 payout, ) = teller.purchase(alice, guardian, id, amountIn, minAmountOut);

        /// Check that the side capacity has been reduced by the amount of the payout
        assertEq(RANGE.capacity(false), startCapacity - payout);

        /// Set timestamp forward so that price is stale
        vm.warp(block.timestamp + uint256(PRICE.observationFrequency()) * 3 + 1);

        /// Try to purchase another bond and expect to revert
        amountIn = auctioneer.maxAmountAccepted(id, guardian) / 2;
        minAmountOut = auctioneer.payoutFor(amountIn, id, guardian);

        vm.expectRevert(abi.encodeWithSignature("Operator_Inactive()"));
        vm.prank(alice);
        teller.purchase(alice, guardian, id, amountIn, minAmountOut);
    }

    // =========  REGENERATION TESTS ========= //

    /// DONE
    /// [X] Wall regenerates when PRICE on other side of MA for enough observations
    /// [X] Wrap around logic works for counting observations
    /// [X] Regen period enforces a minimum time to wait for regeneration
    /// [X] Wall regenerates when price is below liquid backing per ohm backed and capacity is less than 20% of full capacity

    function testCorrectness_lowWallRegenA() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Tests the simplest case of regen
        /// Takes down wall, moves PRICE in regen RANGE,
        /// and hits regen count required with consequtive calls

        /// Confirm wall is up
        assertTrue(RANGE.active(false));

        /// Take down the wall
        knockDownWall(false);

        /// Check that the wall is down
        assertTrue(!RANGE.active(false));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the low wall and verify under threshold
        uint256 startCapacity = RANGE.capacity(false);
        uint256 fullCapacity = operator.fullCapacity(false);
        assertLe(startCapacity, fullCapacity.mulDiv(RANGE.thresholdFactor(), 1e4));

        /// Set price above the moving average to regenerate low wall
        PRICE.setPrice(address(ohm), 101e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 5; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is up
        assertTrue(RANGE.active(false));

        /// Check that the capacity has regenerated
        uint256 endCapacity = RANGE.capacity(false);
        assertEq(endCapacity, fullCapacity);
    }

    function testCorrectness_lowWallRegenB() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Tests wrap around logic of regen
        /// Takes down wall, calls operate a few times with PRICE not in regen RANGE,
        /// moves PRICE into regen RANGE, and hits regen count required with consequtive calls
        /// that wrap around the count array

        /// Confirm wall is up
        assertTrue(RANGE.active(false));

        /// Take down the wall
        knockDownWall(false);

        /// Check that the wall is down
        assertTrue(!RANGE.active(false));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the low wall and verify under threshold
        uint256 startCapacity = RANGE.capacity(false);
        uint256 fullCapacity = operator.fullCapacity(false);
        assertLe(startCapacity, fullCapacity.mulDiv(RANGE.thresholdFactor(), 1e4));

        /// Set price below the moving average so regeneration doesn't start
        PRICE.setPrice(address(ohm), 98e18);

        /// Trigger the operator function with negative
        for (uint256 i; i < 8; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!RANGE.active(false));

        /// Set price above the moving average to regenerate low wall
        PRICE.setPrice(address(ohm), 101e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 5; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is up
        assertTrue(RANGE.active(false));

        /// Check that the capacity has regenerated
        uint256 endCapacity = RANGE.capacity(false);
        assertEq(endCapacity, fullCapacity);
    }

    function testCorrectness_lowWallRegenC() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Tests that wall does not regenerate before the required count is reached

        /// Confirm wall is up
        assertTrue(RANGE.active(false));

        /// Take down the wall
        knockDownWall(false);

        /// Check that the wall is down
        assertTrue(!RANGE.active(false));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the low wall and verify under threshold
        uint256 startCapacity = RANGE.capacity(false);
        uint256 fullCapacity = operator.fullCapacity(false);
        assertLe(startCapacity, fullCapacity.mulDiv(RANGE.thresholdFactor(), 1e4));

        /// Set price above the moving average to regenerate low wall
        PRICE.setPrice(address(ohm), 101e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 4; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!RANGE.active(false));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = RANGE.capacity(false);
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
        assertTrue(RANGE.active(false));

        /// Take down the wall
        knockDownWall(false);

        /// Check that the wall is down
        assertTrue(!RANGE.active(false));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the low wall and verify under threshold
        uint256 startCapacity = RANGE.capacity(false);
        uint256 fullCapacity = operator.fullCapacity(false);
        assertLe(startCapacity, fullCapacity.mulDiv(RANGE.thresholdFactor(), 1e4));

        /// Set price above the moving average to regenerate low wall
        PRICE.setPrice(address(ohm), 101e18);

        /// Trigger the operator once to get a positive check
        vm.prank(heart);
        operator.operate();

        /// Set price below the moving average to get negative checks
        PRICE.setPrice(address(ohm), 99e18);

        /// Trigger the operator function several times with negative checks
        for (uint256 i; i < 3; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Set price above the moving average to regenerate low wall
        PRICE.setPrice(address(ohm), 101e18);

        /// Trigger the operator function several times with positive checks
        for (uint256 i; i < 4; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!RANGE.active(false));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = RANGE.capacity(false);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_lowWallRegen_belowLiquidBacking() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Tests that wall regenerates when price is below liquid backing per ohm backed.

        /// Move price below liquid backing per ohm backed
        PRICE.setPrice(address(ohm), 5e18);
        vm.prank(heart);
        operator.operate();

        uint256 lbbo = appraiser.getMetric(IAppraiserMetric.Metric.LIQUID_BACKING_PER_BACKED_OHM);
        uint256 currentPrice = PRICE.getPriceIn(address(ohm), address(reserve));
        assertLt(currentPrice, lbbo);

        /// Confirm wall is up
        assertTrue(RANGE.active(false));

        /// Take down the wall
        knockDownWall(false);

        /// Check that the wall is down
        assertTrue(!RANGE.active(false));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the low wall and verify under threshold
        uint256 startCapacity = RANGE.capacity(false);
        uint256 fullCapacity = operator.fullCapacity(false);
        assertLt(startCapacity, (fullCapacity.mulDiv(RANGE.thresholdFactor(), 1e4) * 20) / 100);

        /// Below lbbo a single operate call should regenerate the capacity
        vm.prank(heart);
        operator.operate();

        /// Check that the wall is up
        assertTrue(RANGE.active(false));
        /// Check that the capacity has regenerated
        uint256 endCapacity = RANGE.capacity(false);
        assertEq(endCapacity, fullCapacity, "fullCapacity");
    }

    function testCorrectness_lowWallRegenTime() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Tests that the wall won't regenerate before the required time has passed,
        /// even with enough observations
        /// Takes down wall, moves PRICE in regen RANGE,
        /// and hits regen count required with consequtive calls

        /// Confirm wall is up
        assertTrue(RANGE.active(false));

        /// Take down the wall
        knockDownWall(false);

        /// Check that the wall is down
        assertTrue(!RANGE.active(false));

        /// Don't move time forward past the regen period so it won't regen

        /// Get capacity of the low wall and verify under threshold
        uint256 startCapacity = RANGE.capacity(false);
        uint256 fullCapacity = operator.fullCapacity(false);
        assertLe(startCapacity, fullCapacity.mulDiv(RANGE.thresholdFactor(), 1e4));

        /// Set price above the moving average to regenerate low wall
        PRICE.setPrice(address(ohm), 101e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 5; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!RANGE.active(false));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = RANGE.capacity(false);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_lowCushionClosedOnRegen() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Tests that a manually regenerated wall will close the cushion that is deployed currently

        /// Trigger a cushion
        PRICE.setPrice(address(ohm), 89e18);
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed
        assertTrue(auctioneer.isLive(RANGE.market(false)));
        assertEq(RANGE.market(false), 0);

        /// Regenerate the wall manually, expect market to close
        vm.prank(policy);
        operator.regenerate(false);

        /// Check that the market is closed
        assertTrue(!auctioneer.isLive(RANGE.market(false)));
        assertEq(RANGE.market(false), type(uint256).max);
    }

    function testCorrectness_highWallRegenA() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Tests the simplest case of regen
        /// Takes down wall, moves PRICE in regen RANGE,
        /// and hits regen count required with consequtive calls

        /// Confirm wall is up
        assertTrue(RANGE.active(true));

        /// Take down the wall
        knockDownWall(true);

        /// Check that the wall is down
        assertTrue(!RANGE.active(true));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the high wall and verify under threshold
        uint256 startCapacity = RANGE.capacity(true);
        uint256 fullCapacity = operator.fullCapacity(true);
        assertLe(startCapacity, fullCapacity.mulDiv(RANGE.thresholdFactor(), 1e4));

        /// Set price below the moving average to regenerate high wall
        PRICE.setPrice(address(ohm), 99e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 5; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is up
        assertTrue(RANGE.active(true));

        /// Check that the capacity has regenerated
        uint256 endCapacity = RANGE.capacity(true);
        assertEq(endCapacity, fullCapacity);
    }

    function testCorrectness_highWallRegenB() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Tests wrap around logic of regen
        /// Takes down wall, calls operate a few times with PRICE not in regen RANGE,
        /// moves PRICE into regen RANGE, and hits regen count required with consequtive calls
        /// that wrap around the count array

        /// Confirm wall is up
        assertTrue(RANGE.active(true));

        /// Take down the wall
        knockDownWall(true);

        /// Check that the wall is down
        assertTrue(!RANGE.active(true));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the high wall and verify under threshold
        uint256 startCapacity = RANGE.capacity(true);
        uint256 fullCapacity = operator.fullCapacity(true);
        assertLe(startCapacity, fullCapacity.mulDiv(RANGE.thresholdFactor(), 1e4));

        /// Set price above the moving average so regeneration doesn't start
        PRICE.setPrice(address(ohm), 101e18);

        /// Trigger the operator function with negative
        for (uint256 i; i < 8; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!RANGE.active(true));

        /// Set price below the moving average to regenerate high wall
        PRICE.setPrice(address(ohm), 98e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 5; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is up
        assertTrue(RANGE.active(true));

        /// Check that the capacity has regenerated
        uint256 endCapacity = RANGE.capacity(true);
        assertEq(endCapacity, fullCapacity);
    }

    function testCorrectness_highWallRegenC() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Tests that wall does not regenerate before the required count is reached

        /// Confirm wall is up
        assertTrue(RANGE.active(true));

        /// Take down the wall
        knockDownWall(true);

        /// Check that the wall is down
        assertTrue(!RANGE.active(true));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the high wall and verify under threshold
        uint256 startCapacity = RANGE.capacity(true);
        uint256 fullCapacity = operator.fullCapacity(true);
        assertLe(startCapacity, fullCapacity.mulDiv(RANGE.thresholdFactor(), 1e4));

        /// Set price below the moving average to regenerate high wall
        PRICE.setPrice(address(ohm), 98e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 4; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!RANGE.active(true));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = RANGE.capacity(true);
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
        assertTrue(RANGE.active(true));

        /// Take down the wall
        knockDownWall(true);

        /// Check that the wall is down
        assertTrue(!RANGE.active(true));

        /// Move time forward past the regen period
        vm.warp(block.timestamp + 1 hours);

        /// Get capacity of the high wall and verify under threshold
        uint256 startCapacity = RANGE.capacity(true);
        uint256 fullCapacity = operator.fullCapacity(true);
        assertLe(startCapacity, fullCapacity.mulDiv(RANGE.thresholdFactor(), 1e4));

        /// Set price below the moving average to regenerate low wall
        PRICE.setPrice(address(ohm), 98e18);

        /// Trigger the operator once to get a positive check
        vm.prank(heart);
        operator.operate();

        /// Set price above the moving average to get negative checks
        PRICE.setPrice(address(ohm), 101e18);

        /// Trigger the operator function several times with negative checks
        for (uint256 i; i < 3; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Set price below the moving average to regenerate high wall
        PRICE.setPrice(address(ohm), 98e18);

        /// Trigger the operator function several times with positive checks
        for (uint256 i; i < 4; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!RANGE.active(true));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = RANGE.capacity(true);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_highWallRegenTime() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Tests that the wall won't regenerate before the required time has passed,
        /// even with enough observations
        /// Takes down wall, moves PRICE in regen RANGE,
        /// and hits regen count required with consequtive calls

        /// Confirm wall is up
        assertTrue(RANGE.active(true));

        /// Take down the wall
        knockDownWall(true);

        /// Check that the wall is down
        assertTrue(!RANGE.active(true));

        /// Don't move time forward past the regen period so it won't regen

        /// Get capacity of the high wall and verify under threshold
        uint256 startCapacity = RANGE.capacity(true);
        uint256 fullCapacity = operator.fullCapacity(true);
        assertLe(startCapacity, fullCapacity.mulDiv(RANGE.thresholdFactor(), 1e4));

        /// Set price below the moving average to regenerate high wall
        PRICE.setPrice(address(ohm), 99e18);

        /// Trigger the operator function enough times to regenerate the wall
        for (uint256 i; i < 5; ++i) {
            vm.prank(heart);
            operator.operate();
        }

        /// Check that the wall is still down
        assertTrue(!RANGE.active(true));

        /// Check that the capacity hasn't regenerated
        uint256 endCapacity = RANGE.capacity(true);
        assertEq(endCapacity, startCapacity);
    }

    function testCorrectness_highCushionClosedOnRegen() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Tests that a manually regenerated wall will close the cushion that is deployed currently

        /// Trigger a cushion
        PRICE.setPrice(address(ohm), 111e18);
        vm.prank(heart);
        operator.operate();

        /// Check that the cushion is deployed
        assertTrue(auctioneer.isLive(RANGE.market(true)));
        assertEq(RANGE.market(true), 0);

        /// Regenerate the wall manually, expect market to close
        vm.prank(policy);
        operator.regenerate(true);

        /// Check that the market is closed
        assertTrue(!auctioneer.isLive(RANGE.market(true)));
        assertEq(RANGE.market(true), type(uint256).max);
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
        operator.setSpreads(false, 1500, 3000);

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
        OlympusRange.Range memory startRange = RANGE.range();

        /// Set spreads larger as admin
        vm.prank(policy);
        operator.setSpreads(false, 1500, 3000);

        /// Get new bands
        OlympusRange.Range memory newRange = RANGE.range();

        /// Spreads not updated
        assertEq(newRange.high.cushion.spread, 1000);
        assertEq(newRange.high.wall.spread, 2000);
        assertEq(newRange.high.cushion.price, startRange.high.cushion.price);
        assertEq(newRange.high.wall.price, startRange.high.wall.price);

        /// Spreads not updated
        assertEq(newRange.high.cushion.spread, 1000);
        assertEq(newRange.high.wall.spread, 2000);
        assertEq(newRange.high.cushion.price, startRange.high.cushion.price);
        assertEq(newRange.high.wall.price, startRange.high.wall.price);

        /// Check that the spreads have been set and prices are updated
        assertEq(newRange.low.cushion.spread, 1500);
        assertEq(newRange.low.wall.spread, 3000);
        assertLt(newRange.low.cushion.price, startRange.low.cushion.price);
        assertLt(newRange.low.wall.price, startRange.low.wall.price);

        /// Set spreads smaller as admin
        vm.prank(policy);
        operator.setSpreads(false, 500, 1000);

        /// Get new bands
        newRange = RANGE.range();

        /// Spreads not updated
        assertEq(newRange.high.cushion.spread, 1000);
        assertEq(newRange.high.wall.spread, 2000);
        assertEq(newRange.high.cushion.price, startRange.high.cushion.price);
        assertEq(newRange.high.wall.price, startRange.high.wall.price);

        /// Spreads not updated
        assertEq(newRange.high.cushion.spread, 1000);
        assertEq(newRange.high.wall.spread, 2000);
        assertEq(newRange.high.cushion.price, startRange.high.cushion.price);
        assertEq(newRange.high.wall.price, startRange.high.wall.price);

        /// Check that the spreads have been set and prices are updated
        assertEq(newRange.low.cushion.spread, 500);
        assertEq(newRange.low.wall.spread, 1000);
        assertGt(newRange.low.cushion.price, startRange.low.cushion.price);
        assertGt(newRange.low.wall.price, startRange.low.wall.price);

        // Reset lower spreads as admin
        vm.prank(policy);
        operator.setSpreads(false, 1000, 2000);

        // Set upper spreads as admin
        vm.prank(policy);
        operator.setSpreads(true, 500, 1000);

        /// Get new bands
        newRange = RANGE.range();

        /// Lower spreads not updated
        assertEq(newRange.low.cushion.spread, 1000);
        assertEq(newRange.low.wall.spread, 2000);
        assertEq(newRange.low.cushion.price, startRange.low.cushion.price);
        assertEq(newRange.low.wall.price, startRange.low.wall.price);

        /// Upper spreads have been set and prices are updated
        assertEq(newRange.high.cushion.spread, 500);
        assertEq(newRange.high.wall.spread, 1000);
        assertLt(newRange.high.cushion.price, startRange.high.cushion.price);
        assertLt(newRange.high.wall.price, startRange.high.wall.price);
    }

    function testCorrectness_setThresholdFactor() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Check that the threshold factor is the same as initialized
        assertEq(RANGE.thresholdFactor(), 100);

        /// Set threshold factor larger as admin
        vm.prank(policy);
        operator.setThresholdFactor(150);

        /// Check that the threshold factor has been updated
        assertEq(RANGE.thresholdFactor(), 150);
    }

    function testCorrectness_cannotSetSpreadWithInvalidParams() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Set spreads with invalid params as admin (both too low)
        bytes memory err = abi.encodeWithSignature("RANGE_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setSpreads(false, 99, 99);

        /// Set spreads with invalid params as admin (both too high)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setSpreads(false, 10001, 10001);

        /// Set spreads with invalid params as admin (one high, one low)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setSpreads(false, 99, 10001);

        /// Set spreads with invalid params as admin (one high, one low)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setSpreads(false, 10001, 99);

        /// Set spreads with invalid params as admin (cushion > wall)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setSpreads(false, 2000, 1000);

        /// Set spreads with invalid params as admin (one in, one high)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setSpreads(false, 1000, 10001);

        /// Set spreads with invalid params as admin (one in, one low)
        vm.expectRevert(err);
        vm.prank(policy);
        operator.setSpreads(false, 99, 2000);
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
        assertTrue(!RANGE.active(true));
        assertTrue(!RANGE.active(false));
        assertEq(TRSRY.withdrawApproval(address(operator), reserve), 0);
        assertEq(TRSRY.withdrawApproval(address(operator), wrappedReserve), 0);
        assertEq(RANGE.price(false, false), 0);
        assertEq(RANGE.price(false, true), 0);
        assertEq(RANGE.price(true, false), 0);
        assertEq(RANGE.price(true, true), 0);
        assertEq(RANGE.capacity(false), 0);
        assertEq(RANGE.capacity(true), 0);

        /// Initialize the operator
        vm.prank(guardian);
        operator.initialize();

        /// Confirm that the operator is initialized and walls are up
        assertTrue(operator.initialized());
        assertTrue(operator.active());
        assertTrue(RANGE.active(true));
        assertTrue(RANGE.active(false));
        assertEq(TRSRY.withdrawApproval(address(operator), reserve), 0);
        assertEq(TRSRY.withdrawApproval(address(operator), wrappedReserve), RANGE.capacity(false));
        assertGt(RANGE.price(false, false), 0);
        assertGt(RANGE.price(false, true), 0);
        assertGt(RANGE.price(true, false), 0);
        assertGt(RANGE.price(true, true), 0);
        assertGt(RANGE.capacity(false), 0);
        assertGt(RANGE.capacity(true), 0);
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
        assertTrue(RANGE.active(true));
        assertTrue(RANGE.active(false));

        /// Confirm that the Regen structs are at the initial state
        Operator.Status memory status = operator.status();
        assertEq(status.high.count, uint32(0));
        assertEq(status.high.nextObservation, uint32(0));
        assertEq(status.high.lastRegen, startTime);
        assertEq(status.low.count, uint32(0));
        assertEq(status.low.nextObservation, uint32(0));
        assertEq(status.low.lastRegen, startTime);

        /// Call operate twice, at different price points, to make the regen counts higher than zero
        PRICE.setPrice(address(ohm), 105e18);
        vm.prank(heart);
        operator.operate();

        PRICE.setPrice(address(ohm), 95e18);
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
        assertTrue(!RANGE.active(true));
        assertTrue(!RANGE.active(false));

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
        assertTrue(!RANGE.active(true));
        assertTrue(!RANGE.active(false));

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
        assertTrue(RANGE.active(true));
        assertTrue(RANGE.active(false));
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
        assertTrue(RANGE.active(true));

        /// Set price on mock oracle into the high cushion
        PRICE.setPrice(address(ohm), 111e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Get current market
        uint256 currentMarket = RANGE.market(true);

        /// Check market has been updated and is live
        assertTrue(type(uint256).max != currentMarket);
        assertTrue(auctioneer.isLive(currentMarket));

        /// Deactivate the operator
        vm.prank(policy);
        operator.deactivate();

        /// Check market has been updated and is not live
        assertTrue(!auctioneer.isLive(currentMarket));
        assertEq(type(uint256).max, RANGE.market(true));

        /// Reactivate the operator
        vm.prank(policy);
        operator.activate();

        /// Set price on mock oracle into the low cushion
        PRICE.setPrice(address(ohm), 89e18);

        /// Trigger the operate function manually
        vm.prank(heart);
        operator.operate();

        /// Get current market
        currentMarket = RANGE.market(false);

        /// Check market has been updated and is live
        assertTrue(type(uint256).max != currentMarket);
        assertTrue(auctioneer.isLive(currentMarket));

        /// Deactivate the operator
        vm.prank(policy);
        operator.deactivate();

        /// Check market has been updated and is not live
        assertTrue(!auctioneer.isLive(currentMarket));
        assertEq(type(uint256).max, RANGE.market(false));
    }

    // =========  ´TESTS ========= //

    /// DONE
    /// [X] fullCapacity
    /// [X] getAmountOut
    /// [X] targetPrice

    function testCorrectness_viewFullCapacity() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Load config
        Operator.Config memory config = operator.config();

        /// Check that fullCapacity returns the full capacity based on the reserveFactor
        uint256 resInTreasury = wrappedReserve.previewRedeem(
            TRSRY.getReserveBalance(wrappedReserve)
        );
        uint256 lowCapacity = resInTreasury.mulDiv(config.reserveFactor, 1e4);
        uint256 highCapacity = (lowCapacity.mulDiv(
            1e9 * 10 ** PRICE.decimals(),
            1e18 * RANGE.price(true, true)
        ) * (1e4 + RANGE.spread(true, true) + RANGE.spread(false, true))) / 1e4;

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
        uint256 expAmountOut = amountIn.mulDiv(1e18 * RANGE.price(false, true), 1e9 * 1e18);

        assertEq(expAmountOut, operator.getAmountOut(ohm, amountIn));

        /// Case 2: OHM In, more than capacity
        amountIn = RANGE.capacity(false).mulDiv(1e9 * 1e18, 1e18 * RANGE.price(false, true)) + 1e9;

        bytes memory err = abi.encodeWithSignature("Operator_InsufficientCapacity()");
        vm.expectRevert(err);
        operator.getAmountOut(ohm, amountIn);

        /// Case 3: Reserve In, less than capacity
        amountIn = 10000 * 1e18;
        expAmountOut = amountIn.mulDiv(1e9 * 1e18, 1e18 * RANGE.price(true, true));

        assertEq(expAmountOut, operator.getAmountOut(reserve, amountIn));

        /// Case 4: Reserve In, more than capacity
        amountIn = RANGE.capacity(true).mulDiv(1e18 * RANGE.price(true, true), 1e9 * 1e18) + 1e18;

        vm.expectRevert(err);
        operator.getAmountOut(reserve, amountIn);

        /// Case 5: Random, non-accepted token
        err = abi.encodeWithSignature("Operator_InvalidParams()");
        ERC20 token = ERC20(bob);
        amountIn = 100 * 1e18;
        vm.expectRevert(err);
        operator.getAmountOut(token, amountIn);
    }

    function testFuzz_targetPrice(uint256 priceMA_) public {
        // Ensure non-zero price and no overflow
        priceMA_ = bound(priceMA_, 1, type(uint256).max / 1e18);

        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        // Get liquid backing per backed ohm from appraiser
        uint256 lbbo = appraiser.getMetric(IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM);

        /// Update moving average upwards and trigger the operator
        PRICE.setMovingAverage(address(ohm), priceMA_);

        // Get the target price from the operator
        uint256 target = operator.targetPrice();

        // Check that the target price is the max of the moving average and the liquid backing per ohm backed
        if (priceMA_ > lbbo) {
            assertEq(target, priceMA_);
        } else {
            assertEq(target, lbbo);
        }
    }

    // =========  INTERNAL FUNCTION TESTS ========= //

    /// DONE
    /// [X] Range updates from new PRICE data when operate is called (triggers _updateRange)

    function testCorrectness_updateRange() public {
        /// Initialize operator
        vm.prank(guardian);
        operator.initialize();

        /// Store the starting bands
        OlympusRange.Range memory startRange = RANGE.range();

        /// Update moving average upwards and trigger the operator
        PRICE.setMovingAverage(address(ohm), 105e18);
        vm.prank(heart);
        operator.operate();

        /// Check that the bands have updated
        assertGt(RANGE.price(false, false), startRange.low.cushion.price);
        assertGt(RANGE.price(false, true), startRange.low.wall.price);
        assertGt(RANGE.price(true, false), startRange.high.cushion.price);
        assertGt(RANGE.price(true, true), startRange.high.wall.price);

        /// Update moving average downwards and trigger the operator
        PRICE.setMovingAverage(address(ohm), 95e18);
        vm.prank(heart);
        operator.operate();

        /// Check that the bands have updated
        assertLt(RANGE.price(false, false), startRange.low.cushion.price);
        assertLt(RANGE.price(false, true), startRange.low.wall.price);
        assertLt(RANGE.price(true, false), startRange.high.cushion.price);
        assertLt(RANGE.price(true, true), startRange.high.wall.price);

        /// Check that the bands do not get reduced further past the minimum target price
        PRICE.setMovingAverage(address(ohm), 10e18); // At minimum price to get initial values
        vm.prank(heart);
        operator.operate();

        /// Get the current bands
        OlympusRange.Range memory currentRange = RANGE.range();

        /// Move moving average below liquid backing per ohm backed
        PRICE.setMovingAverage(address(ohm), 5e18);
        vm.prank(heart);
        operator.operate();

        /// Check that the bands have not changed
        assertEq(currentRange.low.cushion.price, RANGE.price(false, false));
        assertEq(currentRange.low.wall.price, RANGE.price(false, true));
        assertEq(currentRange.high.cushion.price, RANGE.price(true, false));
        assertEq(currentRange.high.wall.price, RANGE.price(true, true));
    }
}
