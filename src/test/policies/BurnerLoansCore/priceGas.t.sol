// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ISimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansSeize} from "src/policies/interfaces/burnerloans/IBurnerLoansSeize.sol";

// Libraries
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";
import {ModulePermissions} from "test/lib/generated/ModulePermissions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {toSubKeycode} from "src/Submodules.sol";
import {OlympusPricev2} from "src/modules/PRICE/OlympusPrice.v2.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {SimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {PriceCacherTask} from "src/policies/PriceCacherTask.sol";
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {MockPeriodicTaskManager} from "src/test/bases/PeriodicTaskManager/MockPeriodicTaskManager.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockOlympusBackingOracle} from "src/test/mocks/MockOlympusBackingOracle.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";

// Bounded feed setup uses real production PRICE code; only feed observations are mocked.
// forge-lint: disable-start(calls-loop, unused-return)
contract BurnerLoansPriceIntegrationTest is BurnerLoansModularTest {
    using ModuleTestFixtureGenerator for OlympusPricev2;
    uint128 internal constant _BORROW_AMOUNT = 100e9;
    uint128 internal constant _LIFECYCLE_COLLATERAL = 2000e6;
    uint48 internal constant _FEED_UPDATE_THRESHOLD = 24 hours;
    uint48 internal constant _MAX_CACHE_AGE = 1 days;
    OlympusPricev2 internal _productionPrice;
    MockPriceFeed internal _ohmUsdFeed;
    MockPriceFeed internal _usdsUsdFeed;
    address internal _moduleWriter;
    address internal _priceWriter;

    function setUp() public virtual override {
        super.setUp();
        vm.warp(30 days);

        _productionPrice = new OlympusPricev2(_kernel, 18, uint32(8 hours));
        _moduleWriter = _productionPrice.generateMultiFunctionFixture(
            ModulePermissions.moduleWithSubmodules()
        );
        _priceWriter = _productionPrice.generateMultiFunctionFixture(
            ModulePermissions.olympusPricev2()
        );

        ChainlinkPriceFeeds chainlinkPrice = new ChainlinkPriceFeeds(_productionPrice);
        _ohmUsdFeed = _newPriceFeed(10e8);
        _usdsUsdFeed = _newPriceFeed(1e8);

        vm.startPrank(address(this));
        _kernel.executeAction(Actions.UpgradeModule, address(_productionPrice));
        _kernel.executeAction(Actions.ActivatePolicy, _moduleWriter);
        _kernel.executeAction(Actions.ActivatePolicy, _priceWriter);
        vm.stopPrank();

        vm.prank(_moduleWriter);
        _productionPrice.installSubmodule(chainlinkPrice);

        _addPriceAsset(address(_ohm), _ohmUsdFeed);
        _addPriceAsset(address(_asset), _usdsUsdFeed);
    }

    function _newPriceFeed(int256 price_) internal returns (MockPriceFeed feed) {
        // Forge incorrectly attributes these setup calls to a loop; this helper has no loop.
        // forge-lint: disable-start(calls-loop)
        feed = new MockPriceFeed();
        feed.setDecimals(8);
        feed.setLatestAnswer(price_);
        feed.setTimestamp(block.timestamp);
        feed.setRoundId(1);
        feed.setAnsweredInRound(1);
        // forge-lint: disable-end(calls-loop)
    }

    function _addPriceAsset(address asset_, MockPriceFeed feed_) internal {
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component({
            target: toSubKeycode("PRICE.CHAINLINK"),
            selector: ChainlinkPriceFeeds.getOneFeedPrice.selector,
            params: abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: feed_,
                    updateThreshold: _FEED_UPDATE_THRESHOLD
                })
            )
        });

        vm.prank(_priceWriter);
        _productionPrice.addAsset(
            asset_,
            false,
            false,
            0,
            0,
            new uint256[](0),
            IPRICEv2.Component({target: toSubKeycode(bytes20(0)), selector: bytes4(0), params: ""}),
            feeds
        );
    }

    function test_gasGate_freshCacheBorrowIsCheaperThanDirectPrice() public {
        _depositCollateral(_LIFECYCLE_COLLATERAL);
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory preview = _debt.previewBorrow(
            address(_asset),
            _BORROW_AMOUNT,
            _borrower,
            _borrower,
            type(uint256).max,
            address(0)
        );
        uint256 state = vm.snapshotState();

        vm.prank(_borrower);
        uint256 gasBefore = gasleft();
        _debt.borrow(
            address(_asset),
            _BORROW_AMOUNT,
            _borrower,
            _borrower,
            preview.fee,
            address(0)
        );
        uint256 directPriceGas = gasBefore - gasleft();

        assertTrue(vm.revertToState(state), "state snapshot should restore direct-price baseline");
        PriceCache cache = _installOperationalPriceCache(_MAX_CACHE_AGE);
        _cacheConfiguredPair(cache);

        vm.prank(_borrower);
        gasBefore = gasleft();
        _debt.borrow(
            address(_asset),
            _BORROW_AMOUNT,
            _borrower,
            _borrower,
            preview.fee,
            address(0)
        );
        uint256 freshCacheGas = gasBefore - gasleft();

        emit log_named_uint("direct PRICE borrow gas", directPriceGas);
        emit log_named_uint("fresh PriceCache borrow gas", freshCacheGas);
        assertLt(
            freshCacheGas,
            directPriceGas,
            "Fresh cache must reduce borrow gas before calculating savings"
        );
        emit log_named_uint("fresh-cache borrow savings", directPriceGas - freshCacheGas);
        assertLt(freshCacheGas, directPriceGas, "fresh-cache borrow should use less gas");
    }

    // gas viability gate
    // given two active collateral markets and identical production-oracle observations
    //  when a complete Heart-style PriceCacherTask-plus-Seizer beat is compared with direct PRICE
    //   then the independent two-pair cache cost is reported separately from Seizer's one-asset scan
    function test_gasMeasurement_twoPairPriceCacherTaskAndSeizerRecordsIndependentCost() public {
        MockERC20 usde = _configureUsdeMarket();

        {
            SimplePriceFeedStrategy strategy = new SimplePriceFeedStrategy(_productionPrice);
            vm.prank(_moduleWriter);
            _productionPrice.installSubmodule(strategy);

            MockPriceFeed[] memory ohmFeeds = _configureRepresentativePriceFeeds(
                address(_ohm),
                4,
                10e8
            );
            MockPriceFeed[] memory usdsFeeds = _configureRepresentativePriceFeeds(
                address(_asset),
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
        BurnerLoansSeizerTask seizer;
        PriceCacherTask cacher;
        MockPeriodicTaskManager directPriceBeat;
        MockPeriodicTaskManager cachedPriceBeat;
        vm.startPrank(address(this));
        seizer = new BurnerLoansSeizerTask(
            _kernel,
            IBurnerLoansSeize(address(_liquidation)),
            IBurnerLoansLens(address(_lens)),
            10,
            5,
            10_000_000
        );
        cacher = new PriceCacherTask(_kernel, cache);
        directPriceBeat = new MockPeriodicTaskManager(_kernel);
        cachedPriceBeat = new MockPeriodicTaskManager(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(seizer));
        _kernel.executeAction(Actions.ActivatePolicy, address(cacher));
        _kernel.executeAction(Actions.ActivatePolicy, address(directPriceBeat));
        _kernel.executeAction(Actions.ActivatePolicy, address(cachedPriceBeat));
        _rolesAdmin.grantRole(HEART_ROLE, address(directPriceBeat));
        _rolesAdmin.grantRole(HEART_ROLE, address(cachedPriceBeat));
        _rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(seizer));
        seizer.addAsset(address(_asset));
        seizer.enable("");
        cacher.addAssetPair(address(_ohm), address(_asset));
        cacher.addAssetPair(address(_ohm), address(usde));
        cacher.enable("");
        directPriceBeat.addPeriodicTask(address(seizer));
        cachedPriceBeat.addPeriodicTask(address(cacher));
        cachedPriceBeat.addPeriodicTask(address(seizer));
        vm.stopPrank();

        vm.prank(address(this));
        _risk.setPriceCache(address(0));

        uint256 state = vm.snapshotState();
        vm.startSnapshotGas("BurnerLoans.heart.directPriceSeizer");
        directPriceBeat.executeAllTasks();
        uint256 directPriceGas = vm.stopSnapshotGas();
        assertEq(_core.totalActiveDebtOhm(), 0, "Direct PRICE beat actually seizes the position");

        assertTrue(vm.revertToState(state), "state snapshot should restore Seizer baseline");
        vm.prank(address(this));
        _risk.setPriceCache(address(cache));

        assertEq(
            cache.getCachedPrice(address(_ohm), address(_asset)).roundId,
            0,
            "OHM/USDS cache should start empty"
        );
        assertEq(
            cache.getCachedPrice(address(_ohm), address(usde)).roundId,
            0,
            "OHM/USDe cache should start empty"
        );

        vm.startSnapshotGas("BurnerLoans.heart.priceCacherPlusSeizer");
        cachedPriceBeat.executeAllTasks();
        uint256 cacheAndSeizerGas = vm.stopSnapshotGas();
        assertEq(_core.totalActiveDebtOhm(), 0, "Cached PRICE beat actually seizes the position");
        uint256 absoluteGasDelta = cacheAndSeizerGas > directPriceGas
            ? cacheAndSeizerGas - directPriceGas
            : directPriceGas - cacheAndSeizerGas;
        vm.snapshotValue("BurnerLoans.heart.absoluteDelta", absoluteGasDelta);

        // Both rounds start at zero. A final round of one proves PriceCacherTask populated each pair
        // once and the following Seizer scan reused OHM/USDS instead of refreshing it again.
        assertEq(
            cache.getCachedPrice(address(_ohm), address(_asset)).roundId,
            1,
            "Seizer should reuse the OHM/USDS round populated by PriceCacherTask"
        );
        assertEq(
            cache.getCachedPrice(address(_ohm), address(usde)).roundId,
            1,
            "PriceCacherTask should populate OHM/USDe exactly once"
        );

        emit log_named_uint("direct PRICE Heart Seizer beat gas", directPriceGas);
        emit log_named_uint("PriceCacherTask plus Seizer Heart beat gas", cacheAndSeizerGas);
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
        assertGt(cacheAndSeizerGas, 0, "PriceCacherTask plus Seizer beat gas");
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

    function _depositCollateral(uint128 amount_) internal {
        _asset.mint(_borrower, uint256(amount_) + 100e6);
        vm.startPrank(_borrower);
        _asset.approve(address(_core), type(uint256).max);
        _collateral.depositCollateral(address(_asset), amount_, _borrower);
        vm.stopPrank();
    }

    function _installOperationalPriceCache(uint48 maxAge_) internal returns (PriceCache cache) {
        cache = new PriceCache(_kernel, 18, "USD");
        _kernel.executeAction(Actions.ActivatePolicy, address(cache));
        cache.enable("");
        _risk.setPriceCache(address(cache));
        _risk.setPriceCacheMaxAge(maxAge_);
    }

    function _cacheConfiguredPair(PriceCache cache_) internal {
        cache_.cachePrice(address(_ohm), address(_asset));
    }

    function _openLoan() internal {
        MockOlympusBackingOracle(_risk.backingOracle()).setBacking(10e18);
        _depositCollateral(_LIFECYCLE_COLLATERAL);
        vm.prank(_borrower);
        _debt.borrow(
            address(_asset),
            _BORROW_AMOUNT,
            _borrower,
            _borrower,
            type(uint256).max,
            address(0)
        );
    }

    function _configureUsdeMarket() internal returns (MockERC20 token) {
        token = new MockERC20("USDe", "USDe", 6);
        _addPriceAsset(address(token), _newPriceFeed(1e8));
        _admit(address(token));
    }
}
// forge-lint: disable-end(calls-loop, unused-return)
