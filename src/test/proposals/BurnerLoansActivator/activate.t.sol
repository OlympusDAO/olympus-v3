// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IBurnerLoansActivator} from "src/proposals/helpers/interfaces/IBurnerLoansActivator.sol";

import {IBurnerLoansAuthTarget} from "src/policies/interfaces/burnerloans/IBurnerLoansAuthTarget.sol";

// Libraries
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE, BL_LIQUIDATION_POLICY_ROLE, BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE, DEPOSIT_OPERATOR_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansActivatorTest} from "./fixtures/BurnerLoansActivatorTest.sol";
import {Actions, Policy} from "src/Kernel.sol";
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";
import {BurnerLoansActivator} from "src/proposals/helpers/BurnerLoansActivator.sol";
import {MockPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockPeriodicTask.sol";

contract BurnerLoansActivatorActivateTest is BurnerLoansActivatorTest {
    error DepositManagerQueueNotSelected();
    error LateFailure();

    // Scenarios: BLAUNCH-A01.
    function test_whenCallerIsNotTimelock_reverts(address caller_) public {
        vm.assume(caller_ != _timelock);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_NotTimelock.selector,
                caller_
            )
        );
        vm.prank(caller_);
        _activator.activate();
        assertFalse(_activator.isActivated(), "Unauthorized launch preserves one-use state");
    }

    // Scenarios: BLAUNCH-P01.
    function test_givenPreparedStack_whenTimelockActivates() public {
        assertLe(address(_activator).code.length, 24_576, "Activator fits EIP-170");
        _activate();
        _assertLaunchedHeartTasks();
        assertEq(
            IBurnerLoansRisk(_graph.risk).priceCache(),
            _graph.priceCache,
            "Risk uses deployed cache"
        );
        assertEq(
            IBurnerLoansRisk(_graph.risk).priceCacheMaxAge(),
            300,
            "Cache freshness is five minutes"
        );
        assertTrue(IEnabler(_graph.priceCache).isEnabled(), "Cache enabled by governance");
        assertTrue(
            IEnabler(_graph.revenueDistributor).isEnabled(),
            "Distributor enabled by governance"
        );
        assertEq(
            IConfigOperator(_graph.revenueDistributor).configOperator(),
            _graph.revenueDistributorTimelock,
            "Distributor uses its configuration queue"
        );
        assertTrue(
            IEnabler(_graph.revenueDistributorTimelock).isEnabled(),
            "Distributor queue enabled"
        );
        assertTrue(_activator.isActivated(), "Launch completes");
        (address selectedAuth, uint256 authEpoch) = IBurnerLoansCore(_graph.core).authConfig();
        assertEq(
            selectedAuth,
            _deployer.resolve("olympus.periphery.BurnerLoansAuth"),
            "Launch selects the deployed Core-bound Auth"
        );
        assertEq(authEpoch, 1, "Launch installs Auth exactly once");
        IBurnerLoansCore.AssetConfig memory usds = IBurnerLoansConfig(_graph.config).getAssetConfig(
            _graph.usds
        );
        IBurnerLoansCore.AssetConfig memory usde = IBurnerLoansConfig(_graph.config).getAssetConfig(
            _graph.usde
        );
        // OHM caps use 9 decimals; collateral keeper caps use 18 decimals.
        assertTrue(usds.originationsEnabled, "USDS originations start enabled");
        assertTrue(usde.originationsEnabled, "USDe originations start enabled");
        assertEq(
            uint256(IRevenueDistributor(_graph.revenueDistributor).assetState(_graph.susds)),
            uint256(IRevenueDistributor.AssetState.Active),
            "sUSDS revenue routing is active at launch"
        );
        (
            uint16 repurchaseBps,
            IRevenueDistributor.AssetRoute[] memory routes
        ) = IRevenueDistributor(_graph.revenueDistributor).getAssetDistribution(_graph.susds);
        assertEq(repurchaseBps, 0, "sUSDS allocates nothing to repurchases");
        assertEq(routes.length, 0, "sUSDS receipts all accrue to Treasury");
        assertEq(usds.debtCap, 50_000e9, "USDS market debt cap");
        assertEq(usde.debtCap, 50_000e9, "USDe market debt cap");
        assertEq(usds.maxKeeperReward, 100e18, "USDS keeper reward cap");
        assertEq(usde.maxKeeperReward, 100e18, "USDe keeper reward cap");
        assertEq(usds.termLength, 30 days, "Initial loan term");
        assertEq(usde.maxMaturityHorizon, 90 days, "Extension horizon");
        assertEq(usds.maxLtvBps, 8500, "Maximum LTV");
        assertEq(usde.backingMultiplierBps, 12500, "Backing multiplier");
        assertFalse(usds.withdrawAsShares, "USDS exits use underlying");
        assertTrue(usde.withdrawAsShares, "USDe exits use vault shares");
        assertEq(
            IBurnerLoansInventory(_graph.inventory).globalDebtCapOhm(),
            100_000e9,
            "Global OHM debt cap"
        );
        (address retained, bytes4 selector) = _heart.getPeriodicTaskAtIndex(0);
        assertEq(retained, address(_existingTask), "Existing task order is retained");
        assertEq(selector, bytes4(0), "Existing task selector is retained");
        (address seizer, ) = _heart.getPeriodicTaskAtIndex(3);
        (address yieldClaimer, ) = _heart.getPeriodicTaskAtIndex(4);
        (address distributor, ) = _heart.getPeriodicTaskAtIndex(5);
        assertEq(seizer, _graph.seizerTask, "Seizer follows existing preparation tasks");
        assertEq(yieldClaimer, _graph.yieldClaimerTask, "Yield collection follows seizure");
        assertEq(
            distributor,
            _graph.revenueDistributorTask,
            "Distribution immediately precedes Operator"
        );

        IRevenueDistributor revenueDistributor = IRevenueDistributor(_graph.revenueDistributor);
        assertEq(revenueDistributor.yieldRecipient(), address(0), "YRF V2 awaits its own OCG");
        address[4] memory assets = [_graph.usds, _graph.susds, _graph.usde, _graph.susde];
        for (uint256 i; i < assets.length; ++i) {
            (uint16 bps, IRevenueDistributor.AssetRoute[] memory assetRoutes) = revenueDistributor
                .getAssetDistribution(assets[i]);
            assertEq(bps, 0, "Launch allocates no repurchase share");
            assertEq(assetRoutes.length, 0, "Launch allocates every receipt to Treasury");
            assertEq(
                uint256(revenueDistributor.assetState(assets[i])),
                uint256(IRevenueDistributor.AssetState.Active),
                "Launch asset route is active"
            );
        }

        assertEq(
            IBurnerLoansCoreBound(_graph.lens).core(),
            _graph.core,
            "Lens is constructor-bound to launch Core"
        );
        assertEq(
            BurnerLoansSeizerTask(_graph.seizerTask).lens(),
            _graph.lens,
            "Seizer uses the deployed Lens"
        );
        IDepositManagerConfigTimelock queue = _selectedDepositQueue();
        assertEq(
            address(queue.depositManager()),
            _graph.depositManager,
            "Queue binds exact manager"
        );
        assertEq(
            address(Policy(address(queue)).kernel()),
            _graph.kernel,
            "Queue uses launch Kernel"
        );
        assertTrue(_kernel.isPolicyActive(Policy(address(queue))), "Queue is Kernel-active");
        assertTrue(IEnabler(address(queue)).isEnabled(), "Selected queue is enabled");
        assertTrue(
            IEnabler(_graph.depositManager).isEnabled(),
            "Manager initialized before selection"
        );
    }

    // Scenarios: BLAUNCH-H01.
    function test_givenMissingHeartTask_whenTimelockActivates_reverts(uint8 index_) public {
        vm.prank(_launchAdmin);
        _heart.removePeriodicTaskAtIndex(bound(index_, 0, 5));
        _assertHeartDriftRejected();
    }

    // Scenarios: BLAUNCH-H01.
    function test_givenEmptyHeartTasks_whenTimelockActivates_reverts() public {
        vm.startPrank(_launchAdmin);
        for (uint256 i; i < 6; ++i) _heart.removePeriodicTaskAtIndex(0);
        vm.stopPrank();
        _assertHeartDriftRejected();
    }

    // Scenarios: BLAUNCH-H02.
    function test_givenExtraHeartTask_whenTimelockActivates_reverts(uint8 index_) public {
        address extraTask = address(new MockPeriodicTask());
        vm.prank(_launchAdmin);
        _heart.addPeriodicTaskAtIndex(extraTask, bytes4(0), bound(index_, 0, 6));
        _assertHeartDriftRejected();
    }

    // Scenarios: BLAUNCH-H03.
    function test_givenReorderedHeartTasks_whenTimelockActivates_reverts(uint8 index_) public {
        uint256 index = bound(index_, 0, 4);
        address task = _reviewedHeartTasks[index];
        vm.prank(_launchAdmin);
        _heart.removePeriodicTask(task);
        vm.prank(_launchAdmin);
        _heart.addPeriodicTaskAtIndex(task, _reviewedSelector(index), index + 1);
        _assertHeartDriftRejected();
    }

    // Scenarios: BLAUNCH-H04.
    function test_givenReplacedHeartTask_whenTimelockActivates_reverts(uint8 index_) public {
        uint256 index = bound(index_, 0, 5);
        vm.prank(_launchAdmin);
        _heart.removePeriodicTaskAtIndex(index);
        address extraTask = address(new MockPeriodicTask());
        vm.prank(_launchAdmin);
        _heart.addPeriodicTaskAtIndex(extraTask, _reviewedSelector(index), index);
        _assertHeartDriftRejected();
    }

    // Scenarios: BLAUNCH-H05.
    function test_givenChangedHeartSelector_whenTimelockActivates_reverts(
        uint8 index_,
        bytes4 selector_
    ) public {
        uint256 index = bound(index_, 0, 5);
        vm.assume(selector_ != _reviewedSelector(index));
        vm.prank(_launchAdmin);
        _heart.removePeriodicTaskAtIndex(index);
        vm.prank(_launchAdmin);
        _heart.addPeriodicTaskAtIndex(_reviewedHeartTasks[index], selector_, index);
        _assertHeartDriftRejected();
    }

    // Scenarios: BLAUNCH-H06.
    function test_givenLaunchTaskReplacesOperator_whenTimelockActivates_reverts(
        uint8 task_
    ) public {
        address[3] memory tasks = [
            _graph.seizerTask,
            _graph.yieldClaimerTask,
            _graph.revenueDistributorTask
        ];
        vm.prank(_launchAdmin);
        _heart.removePeriodicTaskAtIndex(3);
        vm.prank(_launchAdmin);
        _heart.addPeriodicTaskAtIndex(tasks[bound(task_, 0, 2)], bytes4(0), 3);
        _assertHeartDriftRejected();
    }

    // Scenarios: BLAUNCH-H06.
    function test_givenPreinsertedLaunchTask_whenTimelockActivates_reverts(uint8 task_) public {
        address[3] memory tasks = [
            _graph.seizerTask,
            _graph.yieldClaimerTask,
            _graph.revenueDistributorTask
        ];
        uint256 index = bound(task_, 0, 2);
        vm.prank(_launchAdmin);
        _heart.addPeriodicTaskAtIndex(tasks[index], bytes4(0), index + 3);
        _assertHeartDriftRejected();
    }

    // Scenarios: BLAUNCH-H10.
    function test_givenHeartReadFails_whenTimelockActivates_reverts() public {
        vm.mockCallRevert(
            _graph.heart,
            abi.encodeCall(IPeriodicTaskManager.getPeriodicTasks, ()),
            abi.encodeWithSelector(LateFailure.selector)
        );
        _expectHeartPrerequisite();
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-H10.
    function test_givenMalformedHeartRead_whenTimelockActivates_reverts() public {
        vm.mockCall(
            _graph.heart,
            abi.encodeCall(IPeriodicTaskManager.getPeriodicTasks, ()),
            hex"00"
        );
        _expectHeartPrerequisite();
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-H10.
    function test_givenHeartReadHasTrailingData_whenTimelockActivates_reverts() public {
        (address[] memory tasks, bytes4[] memory selectors) = _heart.getPeriodicTasks();
        vm.mockCall(
            _graph.heart,
            abi.encodeCall(IPeriodicTaskManager.getPeriodicTasks, ()),
            bytes.concat(abi.encode(tasks, selectors), hex"00")
        );
        _expectHeartPrerequisite();
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-H07.
    function test_givenHeartDriftBeforeDeployment_whenTimelockActivates_reverts() public {
        vm.prank(_launchAdmin);
        _heart.removePeriodicTaskAtIndex(3);
        vm.prank(_launchAdmin);
        _heart.addPeriodicTaskAtIndex(_reviewedHeartTasks[3], bytes4(0x12345678), 3);
        _activator = new BurnerLoansActivator(_timelock, _graph);
        vm.prank(_launchRolesAdministrator);
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_activator));
        _assertHeartDriftRejected();
    }

    // Scenarios: BLAUNCH-H08.
    function test_givenRestoredHeartBaseline_whenTimelockActivates() public {
        vm.prank(_launchAdmin);
        _heart.removePeriodicTaskAtIndex(3);
        _assertHeartDriftRejected();
        vm.prank(_launchAdmin);
        _heart.addPeriodicTaskAtIndex(_reviewedHeartTasks[3], _reviewedSelector(3), 3);
        _activate();
        _assertLaunchedHeartTasks();
    }

    function _assertHeartDriftRejected() internal {
        (address[] memory tasksBefore, bytes4[] memory selectorsBefore) = _heart.getPeriodicTasks();
        _expectHeartPrerequisite();
        _activate();
        _assertUnlaunched();
        (address[] memory tasksAfter, bytes4[] memory selectorsAfter) = _heart.getPeriodicTasks();
        assertEq(
            abi.encode(tasksAfter, selectorsAfter),
            abi.encode(tasksBefore, selectorsBefore),
            "Failed launch preserves the drifted Heart list"
        );
        assertTrue(_roles.hasRole(address(_activator), ADMIN_ROLE), "Existing ADMIN is retained");
        assertTrue(_roles.hasRole(_graph.core, DEPOSIT_OPERATOR_ROLE), "Custody role is retained");
        assertTrue(
            _roles.hasRole(_graph.seizerTask, BURNER_LOANS_SEIZER_ROLE),
            "Seizer role is retained"
        );
        assertFalse(_oracle.isEnabled(), "Oracle remains disabled");
        assertEq(_oracle.backing(), 0, "Backing remains uninitialized");
        assertEq(_oracle.configOperator(), address(0), "Oracle operator remains unset");
        assertFalse(_oracleQueue.isEnabled(), "Oracle queue remains disabled");
        assertFalse(IEnabler(_graph.seizerTask).isEnabled(), "Seizer remains disabled");
        assertFalse(IEnabler(_graph.yieldClaimerTask).isEnabled(), "Yield task remains disabled");
        assertFalse(
            IEnabler(_graph.revenueDistributorTask).isEnabled(),
            "Distributor task remains disabled"
        );
    }

    function _expectHeartPrerequisite() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                _graph.heart
            )
        );
    }

    function _assertLaunchedHeartTasks() internal view {
        assertEq(_heart.getPeriodicTaskCount(), 9, "Launch inserts exactly three tasks");
        for (uint256 i; i < 6; ++i) {
            (address task, bytes4 selector) = _heart.getPeriodicTaskAtIndex(i < 3 ? i : i + 3);
            assertEq(task, _reviewedHeartTasks[i], "Every reviewed task retains relative order");
            assertEq(selector, _reviewedSelector(i), "Every reviewed selector is retained");
        }
    }

    // Scenarios: BLAUNCH-S01.
    function test_givenAlreadyActivated_whenTimelockActivates_reverts() public {
        _activate();
        vm.expectRevert(IBurnerLoansActivator.BurnerLoansActivator_AlreadyActivated.selector);
        _activate();
        assertEq(IBurnerLoansCore(_graph.core).getAssetCount(), 2, "Replay creates no market");
    }

    // Scenarios: BLAUNCH-S02.
    function test_givenInactivePolicy_whenTimelockActivates_reverts(uint8 index_) public {
        address[] memory targets = _deployer.policies();
        address target = targets[bound(index_, 0, targets.length - 1)];
        _executeLaunchKernelAction(Actions.DeactivatePolicy, target);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                target
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-A02.
    function test_givenMissingRole_whenTimelockActivates_reverts(uint8 index_) public {
        address[8] memory holders = [
            address(_activator),
            _graph.core,
            _graph.collateral,
            _graph.debt,
            _graph.seize,
            _graph.yieldClaimerTask,
            _graph.seizerTask,
            _graph.heart
        ];
        bytes32[8] memory roles = [
            ADMIN_ROLE,
            DEPOSIT_OPERATOR_ROLE,
            BL_COLLATERAL_POLICY_ROLE,
            BL_DEBT_POLICY_ROLE,
            BL_LIQUIDATION_POLICY_ROLE,
            BL_YIELD_CLAIMER_ROLE,
            BURNER_LOANS_SEIZER_ROLE,
            HEART_ROLE
        ];
        uint256 index = bound(index_, 0, holders.length - 1);
        vm.prank(_launchRolesAdministrator);
        _rolesAdmin.revokeRole(roles[index], holders[index]);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                holders[index]
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-C05.
    function test_givenWrongTimelockTarget_whenTimelockActivates_reverts(uint8 index_) public {
        address[5] memory queues = [
            _graph.configTimelock,
            _graph.riskTimelock,
            _graph.payoutTimelock,
            _graph.inventoryTimelock,
            _graph.revenueDistributorTimelock
        ];
        bytes[5] memory getters = [
            abi.encodeWithSignature("burnerLoans()"),
            abi.encodeWithSignature("risk()"),
            abi.encodeWithSignature("payout()"),
            abi.encodeWithSignature("inventory()"),
            abi.encodeWithSignature("distributor()")
        ];
        uint256 index = bound(index_, 0, queues.length - 1);
        vm.mockCall(queues[index], getters[index], abi.encode(address(0)));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidDeployment.selector,
                queues[index]
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-C06.
    function test_whenAuthHasNoCode_reverts() public {
        _graph.auth = address(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidDeployment.selector,
                address(0)
            )
        );
        new BurnerLoansActivator(_timelock, _graph);
    }

    // Scenarios: BLAUNCH-C07.
    function test_whenComponentBoundToDifferentCore_reverts(uint8 index_) public {
        address[10] memory components = [
            _graph.auth,
            _graph.config,
            _graph.inventory,
            _graph.payout,
            _graph.risk,
            _graph.collateral,
            _graph.debt,
            _graph.seize,
            _graph.lens,
            _graph.yieldClaimerTask
        ];
        address target = components[bound(index_, 0, components.length - 1)];
        vm.mockCall(
            target,
            abi.encodeCall(IBurnerLoansCoreBound.core, ()),
            abi.encode(_graph.config)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidDeployment.selector,
                target
            )
        );
        new BurnerLoansActivator(_timelock, _graph);
    }

    // Scenarios: BLAUNCH-C04.
    function test_whenRevenueTaskBoundToDifferentDistributor_reverts() public {
        vm.mockCall(
            _graph.revenueDistributorTask,
            abi.encodeWithSignature("distributor()"),
            abi.encode(_graph.core)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidDeployment.selector,
                _graph.revenueDistributorTask
            )
        );
        new BurnerLoansActivator(_timelock, _graph);
    }

    // Scenarios: BLAUNCH-O01.
    function test_givenFreshBackingOracle_whenTimelockActivates() public {
        assertFalse(_oracle.isEnabled(), "Oracle starts disabled");
        assertEq(_oracle.backing(), 0, "Oracle starts without backing");
        _activate();
        assertTrue(_oracle.isEnabled(), "Governance enables the oracle");
        assertEq(_oracle.backing(), 1199e16, "Governance initializes backing to $11.99 per OHM");
        assertEq(
            _oracle.configOperator(),
            address(_oracleQueue),
            "Governance selects the backing queue"
        );
        assertTrue(_oracleQueue.isEnabled(), "Governance enables the backing queue");
    }

    // Scenarios: BLAUNCH-O02.
    function test_givenBackingOracleInactive_whenPreparationValidated_reverts() public {
        _executeLaunchKernelAction(Actions.DeactivatePolicy, _graph.backingOracle);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                _graph.backingOracle
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-S03.
    function test_givenRiskPreviouslyEnabled_givenReferrerAllowed_whenTimelockActivates_reverts()
        public
    {
        vm.prank(_launchAdmin);
        _oracle.enable(abi.encode(uint256(1199e16)));
        vm.prank(_launchAdmin);
        IEnabler(_graph.risk).enable("");
        vm.prank(_launchAdmin);
        IBurnerLoansRisk(_graph.risk).setReferrerAllowed(address(0xFEE), true);
        vm.prank(_launchAdmin);
        IEnabler(_graph.risk).disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                _graph.risk
            )
        );
        _activate();
        _assertUnlaunched();
        assertTrue(
            IBurnerLoansRisk(_graph.risk).isReferrerAllowed(address(0xFEE)),
            "Failed launch preserves existing whitelist"
        );
    }

    // Scenarios: BLAUNCH-S04.
    function test_givenLateTaskFailure_whenTimelockActivates_reverts() public {
        vm.mockCallRevert(
            _graph.heart,
            abi.encodeCall(
                IPeriodicTaskManager.addPeriodicTaskAtIndex,
                (_graph.yieldClaimerTask, bytes4(0), 4)
            ),
            abi.encodeWithSelector(LateFailure.selector)
        );
        vm.expectRevert(LateFailure.selector);
        _activate();
        _assertUnlaunched();
        assertEq(_heart.getPeriodicTaskCount(), 6, "Earlier task insertion rolls back");
        assertFalse(_heart.hasPeriodicTask(_graph.seizerTask), "Seizer insertion rolls back");
        assertFalse(_oracle.isEnabled(), "Oracle initialization rolls back");
        assertEq(_oracle.backing(), 0, "Initial backing rolls back");
        assertEq(_oracle.configOperator(), address(0), "Oracle controller selection rolls back");
        assertFalse(
            IEnabler(_graph.depositManagerTimelock).isEnabled(),
            "Custody queue enablement rolls back"
        );
        assertFalse(_oracleQueue.isEnabled(), "Backing queue enablement rolls back");

        assertEq(
            IConfigOperator(_graph.depositManager).configOperator(),
            address(0),
            "Manager controller selection rolls back"
        );
        assertEq(
            IDepositManager(_graph.depositManager).getConfiguredAssets().length,
            0,
            "Custody registration rolls back"
        );
        vm.clearMockedCalls();
        _activate();
        assertTrue(_activator.isActivated(), "Restored prerequisites permit launch retry");
    }

    // Scenarios: BLAUNCH-S05.
    function test_givenPriceSupportMissing_whenTimelockActivates_reverts(uint8 index_) public {
        address[2] memory assets = [_graph.ohm, _graph.usds];
        address asset = assets[bound(index_, 0, assets.length - 1)];
        vm.mockCall(
            address(_price),
            abi.encodeCall(IPRICEv2.isAssetApproved, (asset)),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                address(_price)
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-S06.
    function test_givenBackingOraclePreviouslyEnabled_whenTimelockActivates_reverts() public {
        vm.prank(_launchAdmin);
        _oracle.enable(abi.encode(uint256(12e18)));
        vm.prank(_launchAdmin);
        _oracle.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                _graph.backingOracle
            )
        );
        _activate();
        _assertUnlaunched();
        assertEq(_oracle.backing(), 12e18, "Failed launch preserves existing backing");
    }

    // Scenarios: BLAUNCH-S07.
    function test_givenPriceConfigInactive_whenTimelockActivates_reverts() public {
        _executeLaunchKernelAction(Actions.DeactivatePolicy, _graph.priceConfig);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                _graph.priceConfig
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-O03.
    function test_givenBackingQueueInactive_whenTimelockActivates_reverts() public {
        _executeLaunchKernelAction(Actions.DeactivatePolicy, _graph.backingOracleTimelock);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                _graph.backingOracleTimelock
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-S08.
    function test_givenPriceConfigDisabled_whenTimelockActivates_reverts() public {
        vm.prank(_launchAdmin);
        IEnabler(_graph.priceConfig).disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                _graph.priceConfig
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-C01.
    function test_whenTimelockIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidDeployment.selector,
                address(0)
            )
        );
        new BurnerLoansActivator(address(0), _graph);
    }

    // Scenarios: BLAUNCH-C02.
    function test_whenComponentHasNoCode_reverts(address candidate_) public {
        vm.assume(candidate_.code.length == 0);
        _graph.core = candidate_;
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidDeployment.selector,
                candidate_
            )
        );
        new BurnerLoansActivator(_timelock, _graph);
    }

    // Scenarios: BLAUNCH-C03.
    function test_whenCreatedByAnyCaller(address caller_) public {
        vm.prank(caller_);
        BurnerLoansActivator subject = new BurnerLoansActivator(_timelock, _graph);
        assertEq(subject.timelock(), _timelock, "Constructor caller gains no authority");
    }

    function _assertUnlaunched() internal view {
        assertFalse(_activator.isActivated(), "Failed launch restores one-use state");
        assertFalse(IEnabler(_graph.priceCache).isEnabled(), "Cache enablement rolls back");
        assertFalse(
            IEnabler(_graph.revenueDistributor).isEnabled(),
            "Distributor enablement rolls back"
        );
        assertEq(
            IBurnerLoansRisk(_graph.risk).priceCache(),
            address(0),
            "Risk cache binding rolls back"
        );
        assertFalse(IEnabler(_graph.depositManager).isEnabled(), "Custody enablement rolls back");
        assertFalse(IEnabler(_graph.core).isEnabled(), "Core enablement rolls back");
        assertEq(IBurnerLoansCore(_graph.core).getAssetCount(), 0, "Market creation rolls back");
        assertEq(
            IBurnerLoansInventory(_graph.inventory).globalDebtCapOhm(),
            0,
            "Global cap rolls back"
        );
    }

    // Scenarios: BLAUNCH-C02, BLAUNCH-C05.
    function test_givenInvalidManagerQueue_whenConstructed_reverts(uint8 fault_) public {
        uint256 fault = bound(fault_, 0, 2);
        address queue = _graph.depositManagerTimelock;
        if (fault == 0) vm.etch(queue, "");
        else if (fault == 1)
            vm.mockCall(
                queue,
                abi.encodeCall(IDepositManagerConfigTimelock.depositManager, ()),
                abi.encode(_graph.core)
            );
        else _mockForeignQueueKernel(queue);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidDeployment.selector,
                queue
            )
        );
        new BurnerLoansActivator(_timelock, _graph);
    }

    // Scenarios: BLAUNCH-C05.
    function test_givenManagerQueueBindingDrift_whenActivated_revertsAndRetries(
        bool foreignKernel_
    ) public {
        address queue = _graph.depositManagerTimelock;
        if (foreignKernel_) _mockForeignQueueKernel(queue);
        else
            vm.mockCall(
                queue,
                abi.encodeCall(IDepositManagerConfigTimelock.depositManager, ()),
                abi.encode(_graph.core)
            );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidDeployment.selector,
                queue
            )
        );
        _activate();
        _assertUnlaunched();
        vm.clearMockedCalls();
        _activate();
        assertTrue(_activator.isActivated(), "Restored binding permits retry");
    }

    function _mockForeignQueueKernel(address queue_) internal {
        vm.prank(_launchExecutor);
        Kernel foreignKernel = new Kernel();
        vm.mockCall(
            queue_,
            abi.encodeCall(IBurnerLoansAuthTarget.kernel, ()),
            abi.encode(address(foreignKernel))
        );
    }

    // Scenarios: BLAUNCH-S02.
    function test_givenManagerQueueNotFresh_whenActivated_reverts(bool currentlyEnabled_) public {
        address queue = _graph.depositManagerTimelock;
        vm.prank(_launchAdmin);
        IEnabler(_graph.depositManager).enable("");
        vm.prank(_launchAdmin);
        IConfigOperator(_graph.depositManager).setConfigOperator(queue);
        vm.prank(_launchAdmin);
        IEnabler(queue).enable("");
        if (!currentlyEnabled_) {
            vm.prank(_launchAdmin);
            IEnabler(queue).disable("");
        }
        // Remove the earlier manager prerequisite fault without changing queue history.
        vm.mockCall(
            _graph.depositManager,
            abi.encodeCall(IEnabler.isEnabled, ()),
            abi.encode(false)
        );
        vm.mockCall(
            _graph.depositManager,
            abi.encodeCall(IEnablerV2.lastTransitionAt, ()),
            abi.encode(uint48(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                queue
            )
        );
        _activate();
        assertFalse(_activator.isActivated(), "Non-fresh queue rejects without consuming launch");
        assertEq(
            IConfigOperator(_graph.depositManager).configOperator(),
            queue,
            "Prior selection retained"
        );
    }

    // Scenarios: BLAUNCH-S02.
    function test_givenManagerQueueInactive_whenActivated_reverts() public {
        _executeLaunchKernelAction(Actions.DeactivatePolicy, _graph.depositManagerTimelock);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                _graph.depositManagerTimelock
            )
        );
        _activate();
        _assertUnlaunched();
    }

    function _selectedDepositQueue() private view returns (IDepositManagerConfigTimelock queue) {
        address selected = IConfigOperator(_graph.depositManager).configOperator();
        assertTrue(selected != address(0), "Launch must select DepositManager configuration queue");
        // Legacy assertions record failure without halting; stop here so a missing controller
        // cannot be obscured by the dispatcher's fallback JSON lookup or a call to address zero.
        if (selected == address(0)) revert DepositManagerQueueNotSelected();
        assertGt(selected.code.length, 0, "Selected queue must have deployed code");
        assertEq(
            selected,
            _policy("DepositManagerConfigTimelock"),
            "Select the production sequence queue"
        );
        queue = IDepositManagerConfigTimelock(selected);
    }
}
