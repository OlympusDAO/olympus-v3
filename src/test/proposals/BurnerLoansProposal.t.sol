// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

// Interfaces
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ISimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansConfigTimelock.sol";
import {IBurnerLoansInventoryConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol";
import {IBurnerLoansPayoutConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansPayoutConfigTimelock.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_INVENTORY_PROVIDER_ROLE, BACKING_ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE, DEPOSIT_MANAGER_ADMIN_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {fromSubKeycode, toSubKeycode} from "src/Submodules.sol";

// Contracts
import {BurnerLoansForkTest} from "./BurnerLoansProposal/fixtures/BurnerLoansForkTest.sol";
import {ContinuouslyUpdatedFeed} from "./BurnerLoansProposal/fixtures/ContinuouslyUpdatedFeed.sol";
import {UnavailableFeed} from "./BurnerLoansProposal/fixtures/UnavailableFeed.sol";
import {Policy} from "src/Kernel.sol";
import {SimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {IBurnerLoansActivator} from "src/proposals/interfaces/IBurnerLoansActivator.sol";
import {BurnerLoansProposal} from "src/proposals/BurnerLoansProposal.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

contract BurnerLoansProposalForkTest is BurnerLoansForkTest {
    error DepositManagerQueueNotSelected();

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

        assertTrue(
            _roles.hasRole(_dao, DEPOSIT_MANAGER_ADMIN_ROLE),
            "OCG grants custody proposer role"
        );
    }

    // Read-only postconditions for the fixed seven-queue deployment graph.
    // forge-lint: disable-next-item(calls-loop)
    function _assertTimelocks() private view {
        address backingQueue = addresses.getAddress(
            "olympus-policy-backing-oracle-config-timelock"
        );
        address[7] memory queues = [
            _graph.configTimelock,
            _graph.riskTimelock,
            _graph.payoutTimelock,
            _graph.inventoryTimelock,
            _graph.revenueDistributorTimelock,
            backingQueue,
            _graph.depositManagerTimelock
        ];
        address[7] memory targets = [
            _graph.config,
            _graph.risk,
            _graph.payout,
            _graph.inventory,
            _graph.revenueDistributor,
            _graph.backingOracle,
            _graph.depositManager
        ];
        address[7] memory boundTargets = [
            address(IBurnerLoansConfigTimelock(queues[0]).burnerLoans()),
            address(IBurnerLoansRiskConfigTimelock(queues[1]).risk()),
            address(IBurnerLoansPayoutConfigTimelock(queues[2]).payout()),
            address(IBurnerLoansInventoryConfigTimelock(queues[3]).inventory()),
            IRevenueDistributorConfigTimelock(queues[4]).distributor(),
            address(IBackingOracleConfigTimelock(queues[5]).backingOracle()),
            address(IDepositManagerConfigTimelock(queues[6]).depositManager())
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

    // Scenarios: BLPF-N01.
    // Inspect each actual Governor action for the exact role, holder and final cleanup call.
    // forge-lint: disable-next-item(calls-loop)
    function test_givenGovernanceLaunch_whenActionsRead_includesCustodyGrantWithinLimit()
        public
        view
    {
        // No ETH values are relevant to the role-grant and action-count assertions.
        // forge-lint: disable-next-item(unused-return)
        (address[] memory targets, , bytes[] memory calls) = _proposal.getProposalActions();
        assertLe(targets.length, 15, "Launch fits Governor action limit");
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        bytes32 expectedGrant = keccak256(
            abi.encodeCall(RolesAdmin.grantRole, (DEPOSIT_MANAGER_ADMIN_ROLE, _dao))
        );
        uint256 custodyGrants;
        for (uint256 i; i < targets.length; ++i) {
            if (targets[i] == rolesAdmin && keccak256(calls[i]) == expectedGrant) ++custodyGrants;
        }
        assertEq(custodyGrants, 1, "OCG explicitly grants the exact custody role to DAO once");
        assertEq(targets[targets.length - 1], rolesAdmin, "Final action uses RolesAdmin");
        assertEq(
            calls[calls.length - 1],
            abi.encodeCall(RolesAdmin.revokeRole, (ADMIN_ROLE, address(_activator))),
            "Final action revokes the temporary helper ADMIN"
        );
    }

    // Scenarios: BLPF-N01.
    function test_givenOnlyHeartRolePresent_whenActionsBuilt_fitsWorstCaseBudget() public {
        vm.mockCall(
            address(_roles),
            abi.encodeWithSelector(_roles.hasRole.selector),
            abi.encode(false)
        );
        vm.mockCall(
            address(_roles),
            abi.encodeCall(_roles.hasRole, (_graph.heart, HEART_ROLE)),
            abi.encode(true)
        );
        BurnerLoansProposal proposal = new BurnerLoansProposal();
        proposal.run(addresses, address(this), false, true, false, false, false, false);
        (address[] memory targets, , bytes[] memory calls) = proposal.getProposalActions();
        assertEq(targets.length, 15, "Worst case fills but never exceeds Governor limit");
        uint256 custodyGrants;
        for (uint256 i; i < calls.length; ++i) {
            if (
                keccak256(calls[i]) ==
                keccak256(abi.encodeCall(RolesAdmin.grantRole, (DEPOSIT_MANAGER_ADMIN_ROLE, _dao)))
            ) ++custodyGrants;
        }
        assertEq(custodyGrants, 1, "Worst case retains the exact custody proposer grant");
    }

    // Scenarios: BLPF-N01.
    function test_givenHeartRoleMissing_whenActionsBuilt_reverts() public {
        vm.mockCall(
            address(_roles),
            abi.encodeCall(_roles.hasRole, (_graph.heart, HEART_ROLE)),
            abi.encode(false)
        );
        BurnerLoansProposal proposal = new BurnerLoansProposal();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                _graph.heart
            )
        );
        proposal.run(addresses, address(this), false, true, false, false, false, false);
    }

    // Scenarios: BLPF-A02.
    function test_givenGovernanceLaunch_whenNonAdminReplacesController_reverts(
        address caller_
    ) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        address beforeOperator = IConfigOperator(_graph.depositManager).configOperator();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        IConfigOperator(_graph.depositManager).setConfigOperator(_dao);
        assertEq(
            IConfigOperator(_graph.depositManager).configOperator(),
            beforeOperator,
            "Unauthorized caller cannot replace controller"
        );
    }

    // Scenarios: BLPF-A02.
    function test_givenGovernanceLaunch_whenDaoReplacesController_reverts() public {
        test_givenGovernanceLaunch_whenNonAdminReplacesController_reverts(_dao);
    }

    // Scenarios: BLPF-D01.
    function test_givenGovernanceLaunch_whenDaoQueuesDepositCap_executes(address executor_) public {
        address selected = IConfigOperator(_graph.depositManager).configOperator();
        assertTrue(selected != address(0), "OCG must select the custody queue");
        // Preserve the missing-binding diagnostic under legacy non-halting assertions.
        if (selected == address(0)) revert DepositManagerQueueNotSelected();
        IDepositManagerConfigTimelock queue = IDepositManagerConfigTimelock(selected);
        assertEq(address(queue.depositManager()), _graph.depositManager, "Exact custody target");
        assertEq(address(Policy(selected).kernel()), address(_kernel), "Same Kernel queue");
        assertTrue(_kernel.isPolicyActive(Policy(selected)), "OCG-prepared queue is active");
        assertTrue(IEnabler(selected).isEnabled(), "OCG enables selected queue");
        IERC20 asset = IERC20(_graph.usds);
        uint256 balanceBefore = asset.balanceOf(_graph.depositManager);
        vm.prank(_dao);
        uint64 id = queue.queueSetAssetDepositCap(asset, 9_000_000e18);
        assertEq(
            IDepositManager(_graph.depositManager).getAssetConfiguration(asset).depositCap,
            10_000_000e18,
            "No cap change before delay"
        );
        ITimelockBatchQueue.QueuedAction memory queued = queue.getQueuedAction(id);
        vm.warp(queued.executableAt);
        vm.prank(executor_);
        queue.executeQueuedAction(id);
        assertEq(
            IDepositManager(_graph.depositManager).getAssetConfiguration(asset).depositCap,
            9_000_000e18,
            "DAO config executes after real launch"
        );
        assertEq(asset.balanceOf(_graph.depositManager), balanceBefore, "No custody delta");
    }

    // Scenarios: BLPF-D02.
    function test_givenGovernanceLaunch_whenControllerReplacedAndPaused_adminRepairAndEmergencyCancellationRemain()
        public
    {
        IDepositManagerConfigTimelock queue = IDepositManagerConfigTimelock(
            _graph.depositManagerTimelock
        );
        IERC20 asset = IERC20(_graph.usds);
        vm.prank(_dao);
        uint64 id = queue.queueSetAssetDepositCap(asset, 8_000_000e18);
        (bytes32 key, ) = IConfigTimelockBatchQueue(address(queue)).getQueuedConfigState(id, 0, 0);
        vm.startPrank(_timelock);
        IConfigOperator(_graph.depositManager).setConfigOperator(_dao);
        IDepositManager(_graph.depositManager).setAssetDepositCap(asset, 9_000_000e18);
        vm.stopPrank();
        assertEq(
            IDepositManager(_graph.depositManager).getAssetConfiguration(asset).depositCap,
            9_000_000e18,
            "ADMIN retains direct repair authority after queue replacement"
        );
        vm.startPrank(_emergency);
        IEnabler(_graph.depositManager).disable("");
        IEnabler(address(queue)).disable("");
        queue.cancelQueuedAction(id);
        vm.stopPrank();
        assertTrue(
            queue.getQueuedAction(id).cancelled,
            "Emergency cancels despite target pause and replacement"
        );
        assertEq(
            IConfigTimelockBatchQueue(address(queue)).pendingActionId(key),
            0,
            "Cancellation releases the old custody key"
        );
        assertFalse(_roles.hasRole(_dao, ADMIN_ROLE), "DAO retains no broad ADMIN");
    }

    // Scenarios: BLPF-P12.
    // Fixed four-token distribution checks exercise actual underlying and share-token balances.
    // forge-lint: disable-next-item(calls-loop)
    function test_givenGovernanceLaunch_whenRevenueDistributed_allReceiptsReachTreasury(
        address caller_
    ) public {
        IRevenueDistributor distributor = IRevenueDistributor(_graph.revenueDistributor);
        assertEq(
            distributor.yieldRecipient(),
            address(0),
            "Future V2 OCG owns recipient selection"
        );
        address[4] memory assets = [_graph.usds, _graph.susds, _graph.usde, _graph.susde];
        address treasury = distributor.treasury();
        for (uint256 i; i < assets.length; ++i) {
            IERC20 asset = IERC20(assets[i]);
            (uint16 bps, IRevenueDistributor.AssetRoute[] memory routes) = distributor
                .getAssetDistribution(assets[i]);
            assertEq(bps, 0, "No repurchases before V2");
            assertEq(routes.length, 0, "No configured revenue recipients at launch");
            uint256 treasuryBefore = asset.balanceOf(treasury);
            // All four assets have 18 decimals: 100e18 received, zero explicit allocations,
            // residual = 100e18 - 0 - 0 = 100e18, entirely to Treasury.
            deal(assets[i], address(distributor), 100e18);
            vm.prank(caller_);
            distributor.distribute(assets[i]);
            assertEq(
                asset.balanceOf(treasury) - treasuryBefore,
                100e18,
                "Treasury receives full receipt"
            );
            assertEq(asset.balanceOf(address(distributor)), 0, "No unallocated receipt remains");
        }
    }
}
