// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansConfigTimelock.sol";
import {IBurnerLoansInventoryConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol";
import {IBurnerLoansPayoutConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansPayoutConfigTimelock.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ISimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {fromSubKeycode, toSubKeycode} from "src/Submodules.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_INVENTORY_PROVIDER_ROLE, BACKING_ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Policy} from "src/Kernel.sol";
import {BurnerLoansForkTest} from "./BurnerLoansProposal/fixtures/BurnerLoansForkTest.sol";
import {ContinuouslyUpdatedFeed} from "./BurnerLoansProposal/fixtures/ContinuouslyUpdatedFeed.sol";
import {UnavailableFeed} from "./BurnerLoansProposal/fixtures/UnavailableFeed.sol";
import {SimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

contract BurnerLoansProposalForkTest is BurnerLoansForkTest {
    // Scenarios: BLPF-P09.
    function test_givenOneUsdeFeedUnavailable_whenPriceRead(uint8 index_) public {
        address[3] memory feeds = [_USDE_FEED, _USDE_REDSTONE_FEED, _USDE_API3_FEED];
        address failed = feeds[bound(index_, 0, 2)];
        vm.mockFunction(
            failed,
            address(new UnavailableFeed()),
            abi.encodeWithSignature("latestRoundData()")
        );
        vm.expectRevert(UnavailableFeed.FeedUnavailable.selector);
        // The exact expected revert returns no feed data.
        // forge-lint: disable-next-item(unused-return)
        AggregatorV2V3Interface(failed).latestRoundData();
        uint256 price = _price.getPrice(_graph.usde);
        assertGt(price, 99e16, "Two remaining witnessed feeds return a price above $0.99");
        assertLt(price, 101e16, "Two remaining witnessed feeds return a price below $1.01");
    }

    // Scenarios: BLPF-P10.
    // Replace at most two of the three fixed feed endpoints in this fork fixture.
    // forge-lint: disable-next-item(calls-loop)
    function test_givenOnlyOneUsdeFeedAvailable_whenPriceRead_reverts(uint8 index_) public {
        address[3] memory feeds = [_USDE_FEED, _USDE_REDSTONE_FEED, _USDE_API3_FEED];
        uint256 remaining = bound(index_, 0, 2);
        for (uint256 i; i < feeds.length; ++i) {
            if (i == remaining) continue;
            vm.mockFunction(
                feeds[i],
                address(new UnavailableFeed()),
                abi.encodeWithSignature("latestRoundData()")
            );
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_StrategyFailed.selector,
                _graph.usde,
                abi.encodeWithSelector(
                    ISimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector,
                    1,
                    2
                )
            )
        );
        // The exact expected strategy failure returns no price.
        // forge-lint: disable-next-item(unused-return)
        _price.getPrice(_graph.usde);
    }

    // Scenarios: BLPF-P11.
    // Configure the three fixed fork feeds; no production execution loop is measured here.
    // forge-lint: disable-next-item(calls-loop)
    function test_givenOneUsdeFeedDeviates_whenPriceRead(uint8 index_) public {
        address[3] memory feeds = [_USDE_FEED, _USDE_REDSTONE_FEED, _USDE_API3_FEED];
        uint256 outlier = bound(index_, 0, 2);
        for (uint256 i; i < feeds.length; ++i) {
            // Chainlink/RedStone use 8 decimals; API3 uses 18. Two feeds report $1,
            // the outlier reports $2. Median = $1; exclude $2; (1e18 + 1e18) / 2 = 1e18.
            int256 answer = int256(10 ** AggregatorV2V3Interface(feeds[i]).decimals()) *
                (i == outlier ? int256(2) : int256(1));
            vm.mockFunction(
                feeds[i],
                address(new ContinuouslyUpdatedFeed(1, answer, 1)),
                abi.encodeWithSignature("latestRoundData()")
            );
        }
        assertEq(
            _price.getPrice(_graph.usde),
            1e18,
            "USDe excludes the outlier and averages the two $1 feeds"
        );
    }

    // Scenarios: BLPF-P01.
    function test_givenPreparedMainnet_whenGovernanceExecutes() public view {
        assertTrue(_activator.isActivated(), "Governance activates the lending graph");
        assertEq(
            IBackingOracle(_graph.backingOracle).backing(),
            1199e16,
            "OCG initializes $11.99 backing per OHM"
        );
        assertTrue(_price.isAssetApproved(_graph.usde), "Governance admits USDe into PRICE");
        assertEq(_core.getAssetCount(), 2, "Governance configures both lending markets");
        assertTrue(
            IBurnerLoansConfig(_graph.config).getAssetConfig(_graph.usds).originationsEnabled,
            "USDS originations start enabled"
        );
        assertTrue(
            IBurnerLoansConfig(_graph.config).getAssetConfig(_graph.usde).originationsEnabled,
            "USDe originations start enabled"
        );
        (address selectedAuth, uint256 authEpoch) = _core.authConfig();
        assertEq(
            selectedAuth,
            addresses.getAddress("olympus-periphery-burner-loans-auth"),
            "Governance selects the deployed Auth"
        );
        assertEq(authEpoch, 1, "Governance installs Auth exactly once");
        assertEq(
            IPriceCache(_graph.priceCache).getCachedPrice(_graph.ohm, _graph.usde).updatedAt,
            0,
            "OCG leaves USDe cache cold"
        );
        assertTrue(
            _roles.hasRole(_dao, BURNER_LOANS_INVENTORY_PROVIDER_ROLE),
            "DAO inventory provider granted"
        );
        assertFalse(_roles.hasRole(address(_activator), ADMIN_ROLE), "Temporary ADMIN is removed");
        assertTrue(
            _roles.hasRole(_dao, BURNER_LOANS_ADMIN_ROLE),
            "DAO receives delegated operational authority"
        );
        assertEq(
            keccak256(abi.encode(_price.getAssetData(_graph.ohm))),
            _ohmConfiguration,
            "Existing OHM PRICE configuration is preserved"
        );
        assertEq(
            keccak256(abi.encode(_price.getAssetData(_graph.usds))),
            _usdsConfiguration,
            "Existing USDS PRICE configuration is preserved"
        );
        assertEq(
            IDepositManager(_graph.depositManager).getAssetConfiguration(IERC20(_graph.usds)).vault,
            _graph.susds,
            "Shared v1.1 custody registers USDS with sUSDS"
        );
        assertEq(
            IDepositManager(_graph.depositManager).getAssetConfiguration(IERC20(_graph.usde)).vault,
            _graph.susde,
            "Shared v1.1 custody registers USDe with sUSDe"
        );
        assertTrue(
            _roles.hasRole(_dao, BACKING_ADMIN_ROLE),
            "OCG delegates backing updates to DAO"
        );
        assertTrue(
            _roles.hasRole(_dao, REVENUE_DISTRIBUTOR_ADMIN_ROLE),
            "OCG delegates distributor configuration to DAO"
        );
        assertFalse(_roles.hasRole(_dao, ADMIN_ROLE), "DAO does not receive general ADMIN");
        _assertTimelocks();
        _assertRevenueRoutes();
        _assertPriceAdmission();
        _assertExistingHeartSnapshot();
        _assertHeartOrder();
    }

    // Read-only postconditions for the fixed six-queue deployment graph.
    // forge-lint: disable-next-item(calls-loop)
    function _assertTimelocks() private view {
        address backingQueue = addresses.getAddress(
            "olympus-policy-backing-oracle-config-timelock"
        );
        address[6] memory queues = [
            _graph.configTimelock,
            _graph.riskTimelock,
            _graph.payoutTimelock,
            _graph.inventoryTimelock,
            _graph.revenueDistributorTimelock,
            backingQueue
        ];
        address[6] memory targets = [
            _graph.config,
            _graph.risk,
            _graph.payout,
            _graph.inventory,
            _graph.revenueDistributor,
            _graph.backingOracle
        ];
        address[6] memory boundTargets = [
            address(IBurnerLoansConfigTimelock(queues[0]).burnerLoans()),
            address(IBurnerLoansRiskConfigTimelock(queues[1]).risk()),
            address(IBurnerLoansPayoutConfigTimelock(queues[2]).payout()),
            address(IBurnerLoansInventoryConfigTimelock(queues[3]).inventory()),
            IRevenueDistributorConfigTimelock(queues[4]).distributor(),
            address(IBackingOracleConfigTimelock(queues[5]).backingOracle())
        ];
        for (uint256 i; i < queues.length; ++i) {
            assertGt(queues[i].code.length, 0, "Timelock is deployed");
            assertEq(
                address(Policy(queues[i]).kernel()),
                address(_kernel),
                "Timelock belongs to launch Kernel"
            );
            assertTrue(_kernel.isPolicyActive(Policy(queues[i])), "Timelock is Kernel-active");
            assertEq(boundTargets[i], targets[i], "Timelock binds the intended target");
            assertTrue(
                _kernel.isPolicyActive(Policy(targets[i])),
                "Timelock target is Kernel-active"
            );
            assertEq(
                IConfigOperator(targets[i]).configOperator(),
                queues[i],
                "Target delegates configuration to its timelock"
            );
            assertTrue(IEnabler(queues[i]).isEnabled(), "Timelock is enabled after launch");
            assertTrue(IEnabler(targets[i]).isEnabled(), "Timelock target is enabled after launch");
        }
        assertEq(
            IConfigOperator(_graph.core).configOperator(),
            _graph.config,
            "Config routes its timelocked changes through Core"
        );
    }

    // Read-only postconditions for the four fixed launch revenue assets.
    // forge-lint: disable-next-item(calls-loop)
    function _assertRevenueRoutes() private view {
        address[4] memory assets = [_graph.usds, _graph.susds, _graph.usde, _graph.susde];
        IRevenueDistributor distributor = IRevenueDistributor(_graph.revenueDistributor);
        for (uint256 i; i < assets.length; ++i) {
            assertEq(
                uint256(distributor.assetState(assets[i])),
                uint256(IRevenueDistributor.AssetState.Active),
                "Underlying and vault-share revenue routes are active"
            );
            (uint16 repurchaseBps, IRevenueDistributor.AssetRoute[] memory routes) = distributor
                .getAssetDistribution(assets[i]);
            assertEq(repurchaseBps, 0, "Launch revenue allocates nothing to repurchases");
            assertEq(routes.length, 0, "Launch revenue all accrues to Treasury");
        }
    }

    function _assertExistingHeartSnapshot() private view {
        address[6] memory expected = [
            addresses.getAddress("olympus-policy-convertible-deposit-facility-1_0"),
            addresses.getAddress("olympus-policy-reserve-migrator-1_0"),
            addresses.getAddress("olympus-policy-reserve-wrapper-1_0"),
            addresses.getAddress("olympus-policy-operator-1_5"),
            addresses.getAddress("olympus-policy-yieldrepurchasefacility-1_2"),
            addresses.getAddress("olympus-policy-emissionmanager-1_2")
        ];
        // Zero selects execute(); the explicit selectors are migrate(), operate() and endEpoch().
        bytes4[6] memory selectors = [
            bytes4(0),
            bytes4(0x8fd3ab80),
            bytes4(0),
            bytes4(0x7159a618),
            bytes4(0x0b9663db),
            bytes4(0)
        ];
        assertEq(
            _existingHeartTasks.length,
            expected.length,
            "Pinned Heart baseline has six tasks"
        );
        for (uint256 i; i < expected.length; ++i) {
            assertEq(
                _existingHeartTasks[i],
                expected[i],
                "Pinned Heart task retains its recorded index"
            );
            assertEq(
                _existingHeartSelectors[i],
                selectors[i],
                "Pinned Heart selector matches its recorded task"
            );
        }
    }

    function _assertPriceAdmission() private view {
        IPRICEv2.Asset memory asset = _price.getAssetData(_graph.usde);
        assertFalse(asset.storeMovingAverage, "USDe stores no moving average");
        assertFalse(asset.useMovingAverage, "USDe uses no moving average");
        IPRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 3, "USDe has three independent market-price feeds");
        address[3] memory expected = [
            0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961,
            0xbC5FBcf58CeAEa19D523aBc76515b9AEFb5cfd58,
            0x22a35f4BDD167EAF7Cbf0C0Dc0C2001071714cc6
        ];
        for (uint256 i; i < feeds.length; ++i) {
            assertEq(
                fromSubKeycode(feeds[i].target),
                fromSubKeycode(toSubKeycode("PRICE.CHAINLINK")),
                "USDe feed uses the Chainlink-compatible adapter"
            );
            assertEq(feeds[i].selector, bytes4(0x8daf88ac), "USDe feed uses getOneFeedPrice");
            (address feed, uint48 maximumAge) = abi.decode(feeds[i].params, (address, uint48));
            assertEq(feed, expected[i], "USDe feed is the reviewed market-price source");
            assertEq(
                maximumAge,
                i == 2 ? 90_000 : 86_400,
                "USDe feed freshness matches its heartbeat policy"
            );
        }
        IPRICEv2.Component memory strategy = abi.decode(asset.strategy, (IPRICEv2.Component));
        assertEq(
            fromSubKeycode(strategy.target),
            fromSubKeycode(toSubKeycode("PRICE.SIMPLESTRATEGY")),
            "USDe uses the reviewed aggregation submodule"
        );
        assertEq(
            strategy.selector,
            SimplePriceFeedStrategy.getAveragePriceExcludingDeviations.selector,
            "USDe averages after excluding outliers"
        );
        (uint16 deviationBps, bool strict) = abi.decode(strategy.params, (uint16, bool));
        assertEq(deviationBps, 100, "USDe excludes 1% deviations");
        assertTrue(strict, "USDe requires at least two valid feeds");
        // Only action targets are needed for the ordering and action-budget assertions.
        // forge-lint: disable-next-item(unused-return)
        (address[] memory targets, , ) = _proposal.getProposalActions();
        assertLe(targets.length, 15, "Actual proposal fits Governor action budget");
        for (uint256 i; i < targets.length; ++i) {
            assertTrue(
                targets[i] != 0x5c69f61D384e41b55699C3B10523Ed81c5ef9cbd,
                "PRICE admission is inside the atomic activator call"
            );
        }
    }
}
