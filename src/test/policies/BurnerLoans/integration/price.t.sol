// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Test actions assert their effects directly; return values are intentionally unused.
// forge-lint: disable-start(unused-return)

import {Actions} from "src/Kernel.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ISimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";
import {SimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";
import {PriceCacher} from "src/policies/PriceCacher.sol";
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockPeriodicTaskManager} from "src/test/bases/PeriodicTaskManager/MockPeriodicTaskManager.sol";
import {toSubKeycode} from "src/Submodules.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {BurnerLoansPriceIntegrationTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansPriceIntegrationTestBase.sol";

contract BurnerLoansPriceIntegrationTest is BurnerLoansPriceIntegrationTestBase {
    uint128 internal constant _LIFECYCLE_COLLATERAL = 2_000e6;
    uint48 internal constant _MAX_CACHE_AGE = 60;

    // integration
    // given supported production prices
    //  when the integration flow is executed
    //   then it drives borrow, withdraw, extend, and seize
    function test_supportedProductionPrices_driveBorrowWithdrawExtendAndSeize() public {
        backingOracle.setBacking(10e18);
        _depositCollateral(_LIFECYCLE_COLLATERAL);
        IBurnerLoans.BorrowPreview memory borrowPreview = burnerLoans.previewBorrow(
            address(usds),
            _BORROW_AMOUNT,
            alice
        );
        vm.prank(alice);
        burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, borrowPreview.fee);

        vm.prank(alice);
        (, uint256 withdrawn, uint256 remaining, uint256 withdrawalHealth) = burnerLoans
            .withdrawCollateral(address(usds), 100e6, alice, alice);
        assertEq(withdrawn, 100e6, "withdrawn collateral");
        assertEq(remaining, 1_900e6, "remaining collateral");
        // Launch parameters: maxLtvBps = 8,500 and backingMultiplierBps = 12,500.
        // Debt = 100e9 OHM (9 decimals); backing = $10e18 per OHM (18 decimals).
        // Backing debt value = 100e9 * $10e18 / 1e9 = $1,000e18.
        // Backing requirement = $1,000e18 * 12,500 / 10,000 = $1,250e18.
        // OHM market price is $10e18, below the $10.625e18 crossover, so backing dominates.
        // Remaining collateral value = 1,900e6 * $1e18 / 1e6 = $1,900e18.
        // Health = floor($1,900e18 * 1e18 / $1,250e18) = 1.52e18 WAD.
        assertEq(withdrawalHealth, 1.52e18, "backing-dominant withdrawal health");

        IBurnerLoans.ExtendPreview memory extendPreview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        vm.prank(alice);
        (uint256 extensionFee, uint48 maturity, uint256 extensionHealth) = burnerLoans.extend(
            address(usds),
            alice,
            1,
            extendPreview.fee
        );
        assertEq(extensionFee, extendPreview.fee, "extension fee");
        assertEq(maturity, extendPreview.maturity, "extension maturity");
        assertEq(extensionHealth, extendPreview.healthFactor, "extension health");

        _ohmUsdFeed.setLatestAnswer(20e8);
        _ohmUsdFeed.setTimestamp(block.timestamp);
        assertTrue(burnerLoans.isSeizable(address(usds), alice), "position seizable");

        address[] memory borrowers = new address[](1);
        borrowers[0] = alice;
        burnerLoans.seize(address(usds), borrowers);

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(position.debtOhm, 0, "seized debt");
        assertEq(position.depositedCollateral, 0, "seized collateral");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active debt after seizure");
        assertEq(
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(usds))),
            _BORROW_AMOUNT,
            "defaulted principal"
        );
    }

    // integration
    // given stale production price
    //  when the integration flow is executed
    //   then it blocks risk actions and rolls back
    function test_staleProductionPrice_blocksRiskActionsAndRollsBack() public {
        _depositCollateral(_LIFECYCLE_COLLATERAL);
        IBurnerLoans.BorrowPreview memory borrowPreview = burnerLoans.previewBorrow(
            address(usds),
            _BORROW_AMOUNT,
            alice
        );
        vm.prank(alice);
        burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, borrowPreview.fee);
        IBurnerLoans.Position memory beforePosition = burnerLoans.getPosition(address(usds), alice);
        _ohmUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);
        bytes memory error = abi.encodeWithSelector(
            IPRICEv2.PRICE_PriceZero.selector,
            address(ohm)
        );

        vm.expectRevert(error);
        vm.prank(alice);
        burnerLoans.withdrawCollateral(address(usds), 1e6, alice, alice);

        vm.expectRevert(error);
        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);

        address[] memory borrowers = new address[](1);
        borrowers[0] = alice;
        vm.expectRevert(error);
        burnerLoans.seize(address(usds), borrowers);

        IBurnerLoans.Position memory afterPosition = burnerLoans.getPosition(address(usds), alice);
        assertEq(
            afterPosition.depositedCollateral,
            beforePosition.depositedCollateral,
            "collateral"
        );
        assertEq(afterPosition.debtOhm, beforePosition.debtOhm, "debt");
        assertEq(afterPosition.maturity, beforePosition.maturity, "maturity");
        assertEq(burnerLoans.totalActiveDebtOhm(), _BORROW_AMOUNT, "active debt");
    }

    // given the operational cache has no snapshot
    //  when an ordinary preview needs a price
    //   then it falls back to PRICE without writing the cache
    function test_givenMissingOperationalCache_ordinaryPreviewFallsBackWithoutCacheWrite() public {
        _depositCollateral(_LIFECYCLE_COLLATERAL);
        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);

        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            _BORROW_AMOUNT,
            alice
        );
        IPriceCache.CachedPrice memory cachedPrice = cache.getCachedPrice(
            address(ohm),
            address(usds)
        );

        assertTrue(preview.executable, "fallback preview should be executable");
        assertEq(cachedPrice.roundId, 0, "preview should not write a missing cache snapshot");
    }

    // given the operational cache snapshot is stale
    //  when an ordinary preview and matching action run
    //   then preview falls back without a write and action refreshes once
    function test_givenStaleOperationalCache_withdrawPreviewFallsBackAndActionRefreshesOnce()
        public
    {
        _openLoan();
        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);
        _cacheConfiguredPair(cache);
        IPriceCache.CachedPrice memory beforeCache = cache.getCachedPrice(
            address(ohm),
            address(usds)
        );

        vm.warp(block.timestamp + _MAX_CACHE_AGE + 1);
        _ohmUsdFeed.setTimestamp(block.timestamp);
        _usdsUsdFeed.setTimestamp(block.timestamp);

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(usds),
            100e6,
            alice
        );
        assertEq(
            cache.getCachedPrice(address(ohm), address(usds)).roundId,
            beforeCache.roundId,
            "preview should preserve stale cache round"
        );

        vm.expectCall(
            address(cache),
            abi.encodeCall(
                IPriceCache.cachePriceIfNecessary,
                (address(ohm), address(usds), _MAX_CACHE_AGE)
            ),
            1
        );
        vm.prank(alice);
        (, uint256 amountOut, uint256 remaining, uint256 healthFactor) = burnerLoans
            .withdrawCollateral(address(usds), 100e6, alice, alice);

        assertEq(amountOut, preview.returnAmount, "withdraw output should match fallback preview");
        assertEq(
            remaining,
            preview.remainingDepositedCollateral,
            "remaining collateral should match fallback preview"
        );
        assertEq(
            healthFactor,
            preview.resultingHealthFactor,
            "withdraw health should match fallback preview"
        );
        assertEq(
            cache.getCachedPrice(address(ohm), address(usds)).roundId,
            beforeCache.roundId + 1,
            "action should refresh the stale pair exactly once"
        );
    }

    // given PriceCache is configured but unavailable
    //  when an ordinary preview needs a price
    //   then it bypasses cache methods and uses PRICE
    function test_givenInactiveOrDisabledCache_ordinaryPreviewFallsBackToPrice() public {
        _depositCollateral(_LIFECYCLE_COLLATERAL);
        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);
        _cacheConfiguredPair(cache);

        IBurnerLoans.BorrowPreview memory cachedPreview = burnerLoans.previewBorrow(
            address(usds),
            _BORROW_AMOUNT,
            alice
        );

        _usdsUsdFeed.setLatestAnswer(2e8);
        _usdsUsdFeed.setTimestamp(block.timestamp);

        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(cache));

        IBurnerLoans.BorrowPreview memory inactivePreview = burnerLoans.previewBorrow(
            address(usds),
            _BORROW_AMOUNT,
            alice
        );
        assertTrue(inactivePreview.executable, "inactive-cache fallback should be executable");
        // Debt = 100e9 OHM * $10e18 / 1e9 = $1,000e18.
        // Required collateral = ceil($1,000e18 * 10,000 / 8,500)
        //                     = $1,176.470588235294117648e18.
        // Cached collateral = 2,000e6 USDS * $1e18 / 1e6 = $2,000e18.
        // Cached health = floor($2,000e18 * 1e18 / required) = 1.699999999999999999e18.
        assertEq(
            cachedPreview.resultingHealthFactor,
            1_699_999_999_999_999_999,
            "cached preview should use the cached $1 USDS price"
        );
        // Live PRICE collateral = 2,000e6 USDS * $2e18 / 1e6 = $4,000e18.
        // Live health = floor($4,000e18 * 1e18 / required) = 3.399999999999999999e18.
        assertEq(
            inactivePreview.resultingHealthFactor,
            3_399_999_999_999_999_999,
            "inactive cache should use the live $2 USDS price"
        );

        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(cache));
        vm.prank(admin);
        cache.disable("");
        IBurnerLoans.BorrowPreview memory disabledPreview = burnerLoans.previewBorrow(
            address(usds),
            _BORROW_AMOUNT,
            alice
        );
        assertEq(
            disabledPreview.resultingHealthFactor,
            inactivePreview.resultingHealthFactor,
            "inactive and disabled fallbacks should use identical PRICE observations"
        );
    }

    // given PriceCache is configured but inactive
    //  when a priced action is executed
    //   then it bypasses the cache and uses PRICE
    function test_givenInactiveCache_borrowFallsBackToPrice() public {
        _depositCollateral(_LIFECYCLE_COLLATERAL);
        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);
        _cacheConfiguredPair(cache);
        uint80 cachedRound = cache.getCachedPrice(address(ohm), address(usds)).roundId;

        _usdsUsdFeed.setLatestAnswer(2e8);
        _usdsUsdFeed.setTimestamp(block.timestamp);
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(cache));

        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            _BORROW_AMOUNT,
            alice
        );
        vm.mockCallRevert(
            address(cache),
            abi.encodeWithSelector(IPriceCache.cachePriceIfNecessary.selector),
            abi.encodeWithSignature("UnexpectedCacheCall()")
        );

        vm.prank(alice);
        (, , uint256 resultingDebt, , uint256 healthFactor) = burnerLoans.borrow(
            address(usds),
            _BORROW_AMOUNT,
            alice,
            alice,
            preview.fee
        );

        assertEq(resultingDebt, preview.resultingDebtOhm, "borrow debt should match PRICE preview");
        assertEq(
            healthFactor,
            preview.resultingHealthFactor,
            "borrow health should match PRICE preview"
        );
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(cache));
        assertEq(
            cache.getCachedPrice(address(ohm), address(usds)).roundId,
            cachedRound,
            "inactive-cache fallback should not refresh the cache"
        );
    }

    // given the operational cache faults
    //  when a preview or action needs a price
    //   then the fault propagates without retrying PRICE and action state rolls back
    function test_givenOperationalCacheFault_pricePathsPropagateAndRollBack() public {
        _depositCollateral(_LIFECYCLE_COLLATERAL);
        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);
        bytes memory cacheFault = abi.encodeWithSignature("CacheFault()");

        vm.mockCallRevert(
            address(cache),
            abi.encodeWithSelector(
                IPriceCache.getCachedPrice.selector,
                address(ohm),
                address(usds)
            ),
            cacheFault
        );
        vm.expectRevert(cacheFault);
        burnerLoans.previewBorrow(address(usds), _BORROW_AMOUNT, alice);
        vm.clearMockedCalls();

        vm.mockCallRevert(
            address(cache),
            abi.encodeWithSelector(
                IPriceCache.cachePriceIfNecessary.selector,
                address(ohm),
                address(usds),
                _MAX_CACHE_AGE
            ),
            cacheFault
        );
        vm.expectRevert(cacheFault);
        vm.prank(alice);
        burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, type(uint256).max);

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(position.debtOhm, 0, "cache fault should not create debt");
        assertEq(ohm.balanceOf(alice), 0, "cache fault should not mint OHM");
    }

    // given one cache snapshot is accepted for seizure preview and execution
    //  when it crosses the exact governed age boundary
    //   then the boundary is fresh, a stale view falls back, and seize refreshes once
    function test_givenOperationalCache_seizureUsesExactBoundaryAndActionRefreshes() public {
        _openLoan();
        _ohmUsdFeed.setLatestAnswer(20e8);
        _ohmUsdFeed.setTimestamp(block.timestamp);
        _usdsUsdFeed.setTimestamp(block.timestamp);
        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);
        _cacheConfiguredPair(cache);
        IPriceCache.CachedPrice memory cachedPrice = cache.getCachedPrice(
            address(ohm),
            address(usds)
        );

        vm.warp(block.timestamp + _MAX_CACHE_AGE);
        assertTrue(
            burnerLoans.isSeizable(address(usds), alice),
            "exact cache-age boundary should remain fresh"
        );

        address[] memory borrowers = new address[](1);
        borrowers[0] = alice;
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            borrowers
        );
        assertTrue(preview.executable, "boundary seizure preview should be executable");

        vm.warp(block.timestamp + 1);
        _ohmUsdFeed.setTimestamp(block.timestamp);
        _usdsUsdFeed.setTimestamp(block.timestamp);
        preview = burnerLoans.previewSeize(address(usds), borrowers);
        assertTrue(preview.executable, "stale-cache seizure preview should fall back to PRICE");
        assertEq(
            cache.getCachedPrice(address(ohm), address(usds)).roundId,
            cachedPrice.roundId,
            "seizure preview should not refresh a stale cache"
        );

        vm.expectCall(
            address(cache),
            abi.encodeCall(
                IPriceCache.cachePriceIfNecessary,
                (address(ohm), address(usds), _MAX_CACHE_AGE)
            ),
            1
        );
        burnerLoans.seize(address(usds), borrowers);

        assertEq(
            cache.getCachedPrice(address(ohm), address(usds)).roundId,
            cachedPrice.roundId + 1,
            "seize should refresh the stale snapshot once"
        );
        assertEq(
            burnerLoans.getPosition(address(usds), alice).debtOhm,
            0,
            "seize should clear debt after refreshing"
        );
    }

    // given an operational cache has a fresh seizable snapshot
    //  when PRICE becomes unavailable before preview and execution
    //   then both seizure paths use the cached snapshot
    function test_givenFreshOperationalCache_seizureDoesNotFallBackToPrice() public {
        _openLoan();
        _ohmUsdFeed.setLatestAnswer(20e8);
        _ohmUsdFeed.setTimestamp(block.timestamp);
        _usdsUsdFeed.setTimestamp(block.timestamp);
        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);
        _cacheConfiguredPair(cache);

        _ohmUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);
        _usdsUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);

        address[] memory borrowers = new address[](1);
        borrowers[0] = alice;
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            borrowers
        );
        assertTrue(preview.executable, "fresh-cache seizure preview should be executable");

        vm.expectCall(
            address(cache),
            abi.encodeCall(
                IPriceCache.cachePriceIfNecessary,
                (address(ohm), address(usds), _MAX_CACHE_AGE)
            ),
            1
        );
        (address tokenOut, uint256 keeperReward, uint256 collateralToTreasury) = burnerLoans.seize(
            address(usds),
            borrowers
        );

        assertEq(tokenOut, address(usds), "seizure output token should be USDS");
        assertEq(keeperReward, preview.keeperReward, "keeper reward should match cached preview");
        assertEq(
            collateralToTreasury,
            preview.collateralToTreasury,
            "treasury collateral should match cached preview"
        );
        assertEq(
            burnerLoans.getPosition(address(usds), alice).debtOhm,
            0,
            "cached seizure should clear debt"
        );
        assertEq(
            cache.getCachedPrice(address(ohm), address(usds)).roundId,
            1,
            "fresh cached seizure should not refresh the snapshot"
        );
    }

    // given the collateral quote address sorts below OHM
    //  when Burner Loans reads and consumes a fresh cached pair
    //   then it preserves the requested OHM/collateral price orientation
    function test_givenCollateralAddressIsLowerThanOhm_cachedBorrowUsesRequestedPriceOrientation()
        public
    {
        address collateral = address(uint160(address(ohm)) - 1);
        assertLt(uint160(collateral), uint160(address(ohm)), "collateral should sort below OHM");

        _assertCachedBorrowPriceOrientation(collateral);
    }

    // given the collateral quote address sorts above OHM
    //  when Burner Loans reads and consumes a fresh cached pair
    //   then it preserves the requested OHM/collateral price orientation
    function test_givenCollateralAddressIsHigherThanOhm_cachedBorrowUsesRequestedPriceOrientation()
        public
    {
        address collateral = address(uint160(address(ohm)) + 1);
        assertGt(uint160(collateral), uint160(address(ohm)), "collateral should sort above OHM");

        _assertCachedBorrowPriceOrientation(collateral);
    }

    // given the maximum uint48 freshness window
    //  when a current snapshot is read
    //   then freshness arithmetic cannot overflow
    function test_givenMaximumCacheAge_currentSnapshotRemainsUsable() public {
        _depositCollateral(_LIFECYCLE_COLLATERAL);
        PriceCache cache = _installOperationalPriceCache(type(uint48).max);
        _cacheConfiguredPair(cache);

        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            _BORROW_AMOUNT,
            alice
        );

        assertTrue(preview.executable, "maximum cache age preview should remain executable");
    }

    // given debt-free collateral and an operational cache with no snapshot
    //  when deposit, health, and withdrawal run while PRICE is unavailable
    //   then every debt-free path remains price-free
    function test_givenDebtFreePosition_collateralAndHealthPathsRemainPriceFree() public {
        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);
        _ohmUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);
        _usdsUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);

        usds.mint(alice, _LIFECYCLE_COLLATERAL);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        (, , uint256 depositHealth) = burnerLoans.depositCollateral(
            address(usds),
            _LIFECYCLE_COLLATERAL,
            alice
        );
        (, uint256 amountOut, , uint256 withdrawHealth) = burnerLoans.withdrawCollateral(
            address(usds),
            100e6,
            alice,
            alice
        );
        vm.stopPrank();

        assertEq(depositHealth, type(uint256).max, "debt-free deposit health");
        assertEq(withdrawHealth, type(uint256).max, "debt-free withdrawal health");
        assertEq(amountOut, 100e6, "debt-free withdrawal amount");
        assertEq(
            burnerLoans.positionHealthFactor(address(usds), _LIFECYCLE_COLLATERAL, 0),
            type(uint256).max,
            "zero-debt health getter"
        );
        assertEq(
            cache.getCachedPrice(address(ohm), address(usds)).roundId,
            0,
            "debt-free paths should not populate cache"
        );
    }

    // given a live loan and an operational cache with no snapshot
    //  when the full debt is repaid while PRICE is unavailable
    //   then repayment remains price-free
    function test_givenFullRepayment_actionRemainsPriceFree() public {
        _openLoan();
        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);
        _ohmUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);
        _usdsUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);
        vm.roll(block.number + 1);
        ohm.mint(alice, _BORROW_AMOUNT);
        vm.startPrank(alice);
        ohm.approve(address(burnerLoans), _BORROW_AMOUNT);
        (uint256 remainingDebt, uint256 healthFactor) = burnerLoans.repay(
            address(usds),
            _BORROW_AMOUNT,
            alice
        );
        vm.stopPrank();

        assertEq(remainingDebt, 0, "full repayment should clear debt");
        assertEq(healthFactor, type(uint256).max, "full repayment health");
        assertEq(
            cache.getCachedPrice(address(ohm), address(usds)).roundId,
            0,
            "full repayment should not populate cache"
        );
    }

    // given a matured loan and an operational cache with no snapshot
    //  when eligibility is inspected while PRICE is unavailable
    //   then the maturity-only decision remains price-free
    function test_givenMaturedPosition_isSeizableRemainsPriceFree() public {
        _openLoan();
        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);
        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        vm.warp(position.maturity);
        _ohmUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);
        _usdsUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);

        assertTrue(burnerLoans.isSeizable(address(usds), alice), "matured position seizable");
        assertEq(
            cache.getCachedPrice(address(ohm), address(usds)).roundId,
            0,
            "maturity-only check should not populate cache"
        );
    }

    // given a fresh operational cache
    //  when every priced non-seizure action is executed
    //   then each action consumes exactly one returned snapshot without another cache read
    function test_givenFreshOperationalCache_pricedLifecycleActionsUseOneSnapshotEach() public {
        _openLoan();
        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);
        _cacheConfiguredPair(cache);
        IPriceCache.CachedPrice memory cachedPrice = cache.getCachedPrice(
            address(ohm),
            address(usds)
        );
        _ohmUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);
        _usdsUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);

        vm.mockCallRevert(
            address(cache),
            abi.encodeWithSelector(
                IPriceCache.getCachedPrice.selector,
                address(ohm),
                address(usds)
            ),
            abi.encodeWithSignature("UnexpectedCacheGetter()")
        );
        vm.expectCall(
            address(cache),
            abi.encodeCall(
                IPriceCache.cachePriceIfNecessary,
                (address(ohm), address(usds), _MAX_CACHE_AGE)
            ),
            4
        );

        usds.mint(alice, 100e6);
        vm.startPrank(alice);
        burnerLoans.depositCollateral(address(usds), 100e6, alice);
        burnerLoans.withdrawCollateral(address(usds), 50e6, alice, alice);
        vm.roll(block.number + 1);
        ohm.approve(address(burnerLoans), 10e9);
        burnerLoans.repay(address(usds), 10e9, alice);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
        vm.stopPrank();
        vm.clearMockedCalls();

        assertEq(
            cache.getCachedPrice(address(ohm), address(usds)).roundId,
            cachedPrice.roundId,
            "fresh action snapshots should not increment the cache round"
        );
    }

    // gas measurement
    // given identical production-oracle observations and loan state
    //  when a representative borrow uses direct PRICE or a fresh PriceCache
    //   then the fresh-cache action consumes less gas
    function test_gasGate_freshCacheBorrowIsCheaperThanDirectPrice() public {
        _depositCollateral(_LIFECYCLE_COLLATERAL);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            _BORROW_AMOUNT,
            alice
        );
        uint256 state = vm.snapshotState();

        vm.prank(alice);
        uint256 gasBefore = gasleft();
        burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, preview.fee);
        uint256 directPriceGas = gasBefore - gasleft();

        assertTrue(vm.revertToState(state), "state snapshot should restore direct-price baseline");
        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);
        _cacheConfiguredPair(cache);

        vm.prank(alice);
        gasBefore = gasleft();
        burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, preview.fee);
        uint256 freshCacheGas = gasBefore - gasleft();

        emit log_named_uint("direct PRICE borrow gas", directPriceGas);
        emit log_named_uint("fresh PriceCache borrow gas", freshCacheGas);
        emit log_named_uint("fresh-cache borrow savings", directPriceGas - freshCacheGas);
        assertLt(freshCacheGas, directPriceGas, "fresh-cache borrow should use less gas");
    }

    // gas viability gate
    // given two active collateral markets and identical production-oracle observations
    //  when a complete Heart-style PriceCacher-plus-Seizer beat is compared with direct PRICE
    //   then the independent two-pair cache cost is reported separately from Seizer's one-asset scan
    function test_gasMeasurement_twoPairPriceCacherAndSeizerRecordsIndependentCost() public {
        MockERC20 usde = _configureUsdeMarket();

        {
            SimplePriceFeedStrategy strategy = new SimplePriceFeedStrategy(_productionPrice);
            vm.prank(_moduleWriter);
            _productionPrice.installSubmodule(strategy);

            MockPriceFeed[] memory ohmFeeds = _configureRepresentativePriceFeeds(
                address(ohm),
                4,
                10e8
            );
            MockPriceFeed[] memory usdsFeeds = _configureRepresentativePriceFeeds(
                address(usds),
                3,
                1e8
            );
            MockPriceFeed[] memory usdeFeeds = _configureRepresentativePriceFeeds(
                address(usde),
                3,
                1e8
            );

            _openLoan();
            _setFeedObservations(ohmFeeds, 20e8, block.timestamp - 1);
            _setFeedObservations(usdsFeeds, 1e8, block.timestamp - 1);
            _setFeedObservations(usdeFeeds, 1e8, block.timestamp - 1);
        }

        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);
        BurnerLoansSeizer seizer;
        PriceCacher cacher;
        MockPeriodicTaskManager directPriceBeat;
        MockPeriodicTaskManager cachedPriceBeat;
        vm.startPrank(admin);
        seizer = new BurnerLoansSeizer(kernel, address(burnerLoans), 10, 5, 10_000_000);
        cacher = new PriceCacher(kernel, cache);
        directPriceBeat = new MockPeriodicTaskManager(kernel);
        cachedPriceBeat = new MockPeriodicTaskManager(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(seizer));
        kernel.executeAction(Actions.ActivatePolicy, address(cacher));
        kernel.executeAction(Actions.ActivatePolicy, address(directPriceBeat));
        kernel.executeAction(Actions.ActivatePolicy, address(cachedPriceBeat));
        rolesAdmin.grantRole(HEART_ROLE, address(directPriceBeat));
        rolesAdmin.grantRole(HEART_ROLE, address(cachedPriceBeat));
        rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(seizer));
        seizer.addAsset(address(usds));
        seizer.enable("");
        cacher.addAssetPair(address(ohm), address(usds));
        cacher.addAssetPair(address(ohm), address(usde));
        cacher.enable("");
        directPriceBeat.addPeriodicTask(address(seizer));
        cachedPriceBeat.addPeriodicTask(address(cacher));
        cachedPriceBeat.addPeriodicTask(address(seizer));
        vm.stopPrank();

        vm.prank(admin);
        burnerLoans.setPriceCache(address(0));

        uint256 state = vm.snapshotState();
        vm.startSnapshotGas("BurnerLoans.heart.directPriceSeizer");
        directPriceBeat.executeAllTasks();
        uint256 directPriceGas = vm.stopSnapshotGas();

        assertTrue(vm.revertToState(state), "state snapshot should restore Seizer baseline");
        vm.prank(admin);
        burnerLoans.setPriceCache(address(cache));

        assertEq(
            cache.getCachedPrice(address(ohm), address(usds)).roundId,
            0,
            "OHM/USDS cache should start empty"
        );
        assertEq(
            cache.getCachedPrice(address(ohm), address(usde)).roundId,
            0,
            "OHM/USDe cache should start empty"
        );

        vm.startSnapshotGas("BurnerLoans.heart.priceCacherPlusSeizer");
        cachedPriceBeat.executeAllTasks();
        uint256 cacheAndSeizerGas = vm.stopSnapshotGas();
        uint256 absoluteGasDelta = cacheAndSeizerGas > directPriceGas
            ? cacheAndSeizerGas - directPriceGas
            : directPriceGas - cacheAndSeizerGas;
        vm.snapshotValue("BurnerLoans.heart.absoluteDelta", absoluteGasDelta);

        // Both rounds start at zero. A final round of one proves PriceCacher populated each pair
        // once and the following Seizer scan reused OHM/USDS instead of refreshing it again.
        assertEq(
            cache.getCachedPrice(address(ohm), address(usds)).roundId,
            1,
            "Seizer should reuse the OHM/USDS round populated by PriceCacher"
        );
        assertEq(
            cache.getCachedPrice(address(ohm), address(usde)).roundId,
            1,
            "PriceCacher should populate OHM/USDe exactly once"
        );

        emit log_named_uint("direct PRICE Heart Seizer beat gas", directPriceGas);
        emit log_named_uint("PriceCacher plus Seizer Heart beat gas", cacheAndSeizerGas);
        if (cacheAndSeizerGas < directPriceGas) {
            emit log_named_uint(
                "two-pair cache plus Seizer savings",
                directPriceGas - cacheAndSeizerGas
            );
        } else {
            emit log_named_uint(
                "two-pair cache plus Seizer overhead",
                cacheAndSeizerGas - directPriceGas
            );
        }
        assertGt(directPriceGas, 0, "direct PRICE beat gas");
        assertGt(cacheAndSeizerGas, 0, "PriceCacher plus Seizer beat gas");
    }

    function _openLoan() internal {
        backingOracle.setBacking(10e18);
        _depositCollateral(_LIFECYCLE_COLLATERAL);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            _BORROW_AMOUNT,
            alice
        );
        vm.prank(alice);
        burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, preview.fee);
    }

    function _configureUsdeMarket() internal returns (MockERC20 usde_) {
        usde_ = new MockERC20("USDe", "USDe", 6);
        MockPriceFeed usdeUsdFeed = _newPriceFeed(1e8);
        _addPriceAsset(address(usde_), usdeUsdFeed);
        _configureDepositManagerAsset(address(usde_));

        vm.prank(admin);
        burnerLoansConfig.addAsset(
            address(usde_),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig(),
            false
        );
    }

    function _assertCachedBorrowPriceOrientation(address collateral_) internal {
        (MockERC20 collateral, MockPriceFeed collateralFeed) = _configureCollateralAt(collateral_);
        collateral.mint(alice, uint256(_LIFECYCLE_COLLATERAL) + _feeReserve());
        vm.startPrank(alice);
        collateral.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(collateral_, _LIFECYCLE_COLLATERAL, alice);
        vm.stopPrank();

        IBurnerLoans.BorrowPreview memory directPreview = burnerLoans.previewBorrow(
            collateral_,
            _BORROW_AMOUNT,
            alice
        );
        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);
        cache.cachePrice(address(ohm), collateral_);

        IPriceCache.CachedPrice memory cachedPrice = cache.getCachedPrice(
            address(ohm),
            collateral_
        );
        assertEq(cachedPrice.assetPriceUsd, 10e18, "cached asset leg should be OHM/USD");
        assertEq(cachedPrice.quotePriceUsd, 2e18, "cached quote leg should be collateral/USD");

        _ohmUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);
        collateralFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);

        IBurnerLoans.BorrowPreview memory cachedPreview = burnerLoans.previewBorrow(
            collateral_,
            _BORROW_AMOUNT,
            alice
        );
        assertEq(
            cachedPreview.resultingHealthFactor,
            directPreview.resultingHealthFactor,
            "cached preview should preserve OHM/collateral orientation"
        );

        vm.prank(alice);
        (, , , , uint256 healthFactor) = burnerLoans.borrow(
            collateral_,
            _BORROW_AMOUNT,
            alice,
            alice,
            cachedPreview.fee
        );
        assertEq(
            healthFactor,
            directPreview.resultingHealthFactor,
            "cached action should preserve OHM/collateral orientation"
        );
    }

    function _configureCollateralAt(
        address collateral_
    ) internal returns (MockERC20 collateral, MockPriceFeed collateralFeed) {
        assertEq(collateral_.code.length, 0, "chosen collateral address should be unused");
        MockERC20 implementation = new MockERC20("Ordered Collateral", "ORDERED", 6);
        vm.etch(collateral_, address(implementation).code);
        collateral = MockERC20(collateral_);

        collateralFeed = _newPriceFeed(2e8);
        _addPriceAsset(collateral_, collateralFeed);
        _configureDepositManagerAsset(collateral_);

        vm.prank(admin);
        burnerLoansConfig.addAsset(
            collateral_,
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig(),
            false
        );
    }

    function _configureRepresentativePriceFeeds(
        address asset_,
        uint256 feedCount_,
        int256 price_
    ) internal returns (MockPriceFeed[] memory priceFeeds_) {
        priceFeeds_ = new MockPriceFeed[](feedCount_);
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](feedCount_);
        for (uint256 i; i < feedCount_; ++i) {
            MockPriceFeed feed = _newPriceFeed(price_);
            priceFeeds_[i] = feed;
            feeds[i] = IPRICEv2.Component({
                target: toSubKeycode("PRICE.CHAINLINK"),
                selector: ChainlinkPriceFeeds.getOneFeedPrice.selector,
                params: abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams({
                        feed: feed,
                        updateThreshold: _FEED_UPDATE_THRESHOLD
                    })
                )
            });
        }

        IPRICEv2.Component memory strategy = IPRICEv2.Component({
            target: toSubKeycode("PRICE.SIMPLESTRATEGY"),
            selector: SimplePriceFeedStrategy.getAveragePriceExcludingDeviations.selector,
            params: abi.encode(
                ISimplePriceFeedStrategy.DeviationParams({
                    deviationBps: 100,
                    revertOnInsufficientCount: true
                })
            )
        });

        vm.prank(_priceWriter);
        _productionPrice.updateAsset(
            asset_,
            IPRICEv2.UpdateAssetParams({
                updateFeeds: true,
                updateStrategy: true,
                updateMovingAverage: false,
                feeds: feeds,
                strategy: strategy,
                useMovingAverage: false,
                storeMovingAverage: false,
                movingAverageDuration: 0,
                lastObservationTime: 0,
                observations: new uint256[](0)
            })
        );
    }

    function _setFeedObservations(
        MockPriceFeed[] memory feeds_,
        int256 price_,
        uint256 timestamp_
    ) internal {
        // Each production-price test feed must receive the same observation.
        // forge-lint: disable-start(calls-loop)
        for (uint256 i; i < feeds_.length; ++i) {
            feeds_[i].setLatestAnswer(price_);
            feeds_[i].setTimestamp(timestamp_);
        }
        // forge-lint: disable-end(calls-loop)
    }
}

// forge-lint: disable-end(unused-return)

// forge-lint: disable-end(literal-instead-of-constant)
