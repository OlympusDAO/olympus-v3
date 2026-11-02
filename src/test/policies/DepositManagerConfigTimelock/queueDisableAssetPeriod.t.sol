// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, DEPOSIT_MANAGER_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";

// Setup and revert-path calls deliberately ignore return values.
// forge-lint: disable-start(unused-return)

contract DepositManagerConfigTimelockQueueDisableAssetPeriodTest is
    DepositManagerConfigTimelockTest
{
    function test_whenAssetIsZero_whenDisableIsQueued_reverts() public {
        _expectInvalidAssetPeriod(IERC20(address(0)), DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueDisableAssetPeriod(
            IERC20(address(0)),
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
    }

    function test_whenDepositPeriodIsZero_whenDisableIsQueued_reverts() public {
        _expectInvalidAssetPeriod(iAsset, 0, DEPOSIT_OPERATOR);

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueDisableAssetPeriod(iAsset, 0, DEPOSIT_OPERATOR);
    }

    function test_whenOperatorIsZero_whenDisableIsQueued_reverts() public {
        _expectInvalidAssetPeriod(iAsset, DEPOSIT_PERIOD, address(0));

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueDisableAssetPeriod(iAsset, DEPOSIT_PERIOD, address(0));
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-I02.
    function test_givenAssetPeriodIsDisabled_whenDisableIsQueued_reverts() public {
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_AssetPeriodDisabled.selector,
                address(iAsset),
                DEPOSIT_PERIOD,
                DEPOSIT_OPERATOR
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueDisableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-P01, DMCT-QUEUE-DISABLE-PERIOD-N01.
    function test_givenEnabledPeriod_queuesAndExecutesDisable(address executor_) public {
        uint64 actionId = _queueDisablePeriod();
        _warpReady();

        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);

        assertFalse(
            depositManager.isAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR).isEnabled,
            "timelock should disable period"
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-P02.
    function test_givenPendingDisable_whenSamePeriodChangeIsQueued_reverts() public {
        _queueDisablePeriod();

        _expectPendingKey(_periodKey(DEPOSIT_PERIOD, DEPOSIT_OPERATOR), 1);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueDisableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-P03.
    function test_givenPendingDisable_whenDifferentPeriodIsQueued_succeeds() public {
        uint8 secondPeriod = DEPOSIT_PERIOD + 1;
        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, secondPeriod, DEPOSIT_OPERATOR);
        uint64 firstActionId = _queueDisablePeriod();

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 secondActionId = _configTimelock.queueDisableAssetPeriod(
            iAsset,
            secondPeriod,
            DEPOSIT_OPERATOR
        );

        assertEq(
            secondActionId,
            firstActionId + 1,
            "different asset periods should have independent keys"
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-P04.
    function test_givenPendingDisable_whenDifferentAssetIsQueued_executesBoth() public {
        MockERC20 secondAsset = new MockERC20("Second", "SECOND", 18);
        MockERC4626 secondVault = new MockERC4626(secondAsset, "Second Vault", "svSECOND");
        vm.startPrank(ADMIN);
        depositManager.addAsset(
            IERC20(address(secondAsset)),
            IERC4626(address(secondVault)),
            type(uint256).max,
            0
        );
        depositManager.addAssetPeriod(
            IERC20(address(secondAsset)),
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        vm.stopPrank();

        uint64 firstActionId = _queueDisablePeriod();
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 secondActionId = _configTimelock.queueDisableAssetPeriod(
            IERC20(address(secondAsset)),
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        _warpReady();

        _configTimelock.executeQueuedAction(firstActionId);
        _configTimelock.executeQueuedAction(secondActionId);

        assertFalse(
            depositManager.isAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR).isEnabled,
            "first asset period should be disabled"
        );
        assertFalse(
            depositManager
                .isAssetPeriod(IERC20(address(secondAsset)), DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
                .isEnabled,
            "second asset period should be disabled"
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-P04.
    function test_givenPendingDisable_whenDifferentOperatorIsQueued_executesBoth() public {
        address secondOperator = makeAddr("secondOperator");
        vm.startPrank(ADMIN);
        depositManager.setOperatorName(secondOperator, "op2");
        rolesAdmin.grantRole("deposit_operator", secondOperator);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, secondOperator);
        vm.stopPrank();

        uint64 firstActionId = _queueDisablePeriod();
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 secondActionId = _configTimelock.queueDisableAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD,
            secondOperator
        );
        _warpReady();

        _configTimelock.executeQueuedAction(firstActionId);
        _configTimelock.executeQueuedAction(secondActionId);

        assertFalse(
            depositManager.isAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR).isEnabled,
            "first operator period should be disabled"
        );
        assertFalse(
            depositManager.isAssetPeriod(iAsset, DEPOSIT_PERIOD, secondOperator).isEnabled,
            "second operator period should be disabled"
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-N02.
    function test_whenDepositPeriodIsUint8Max_whenConfigured_executesDisable() public {
        uint8 maximumPeriod = type(uint8).max;
        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, maximumPeriod, DEPOSIT_OPERATOR);

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 actionId = _configTimelock.queueDisableAssetPeriod(
            iAsset,
            maximumPeriod,
            DEPOSIT_OPERATOR
        );
        _warpReady();
        _configTimelock.executeQueuedAction(actionId);

        assertFalse(
            depositManager.isAssetPeriod(iAsset, maximumPeriod, DEPOSIT_OPERATOR).isEnabled,
            "maximum deposit period should be disabled"
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-D02.
    function test_givenQueuedDisable_whenPeriodChanges_executionRevertsAsStale() public {
        uint64 actionId = _queueDisablePeriod();
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        _warpReady();

        _expectStale(actionId, 0, keccak256(abi.encode(true, false)));
        _configTimelock.executeQueuedAction(actionId);
        _assertPending(actionId);
    }

    function _expectInvalidAssetPeriod(IERC20 asset_, uint8 period_, address operator_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_InvalidAssetPeriod.selector,
                address(asset_),
                period_,
                operator_
            )
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-A01.
    function test_givenAdminOnly_whenTypedActionQueued(address caller_) public {
        vm.assume(caller_ != DEPOSIT_MANAGER_ADMIN);
        _grantRole(ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(
                _configTimelock.queueDisableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.disableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-A01.
    function test_givenManagerOnly_whenTypedActionQueued(address caller_) public {
        vm.assume(caller_ != ADMIN);
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(
                _configTimelock.queueDisableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.disableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-A01.
    function test_givenBothRoles_whenTypedActionQueued(address caller_) public {
        _grantRole(ADMIN_ROLE, caller_);
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(
                _configTimelock.queueDisableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.disableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-A02.
    function test_whenTypedActionCallerUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_MANAGER_ADMIN);
        _assertQueueRejected(
            caller_,
            abi.encodeCall(
                _configTimelock.queueDisableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-L01.
    function test_givenTimelockPaused_whenTypedActionQueued_reverts() public {
        _pausePolicy(address(_configTimelock));
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueDisableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-L02.
    function test_givenManagerPaused_whenTypedActionQueued_reverts() public {
        _pausePolicy(address(depositManager));
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueDisableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-L03.
    function test_givenTimelockInactive_whenTypedActionQueued_reverts() public {
        _setPolicyActive(address(_configTimelock), false);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueDisableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-L04.
    function test_givenManagerInactive_whenTypedActionQueued_reverts() public {
        _setPolicyActive(address(depositManager), false);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueDisableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-D01.
    function test_givenOperatorRotated_whenTypedActionQueued_reverts() public {
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueDisableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-L05.
    function test_givenReEnabled_whenTypedActionQueued() public {
        _pausePolicy(address(_configTimelock));
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueDisableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.disableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-L05.
    function test_givenReactivated_whenTypedActionQueued() public {
        _setPolicyActive(address(_configTimelock), false);
        _setPolicyActive(address(depositManager), false);
        _setPolicyActive(address(depositManager), true);
        _setPolicyActive(address(_configTimelock), true);
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueDisableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.disableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-N01.
    function test_whenConfiguredPeriodSpansFullRange(uint8 period_) public {
        uint8 period = SafeCast.toUint8(bound(period_, 1, type(uint8).max));
        address other = makeAddr("fullPeriodOperator");
        vm.startPrank(ADMIN);
        depositManager.setOperatorName(other, "all");
        rolesAdmin.grantRole("deposit_operator", other);
        depositManager.addAssetPeriod(iAsset, period, other);

        vm.stopPrank();
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(_configTimelock.queueDisableAssetPeriod, (iAsset, period, other)),
            IDepositManager.disableAssetPeriod.selector,
            abi.encode(iAsset, period, other)
        );
    }

    // Scenarios: DMCT-QUEUE-DISABLE-PERIOD-I01.
    function test_whenRouteAbsent_reverts(address operator_, uint8 period_) public {
        vm.assume(operator_ != DEPOSIT_OPERATOR || period_ != DEPOSIT_PERIOD);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueDisableAssetPeriod, (iAsset, period_, operator_)),
            abi.encodeWithSelector(
                IDepositManager.DepositManager_InvalidAssetPeriod.selector,
                address(iAsset),
                period_,
                operator_
            )
        );
    }
}

// forge-lint: disable-end(unused-return)
