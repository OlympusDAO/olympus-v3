// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
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

// Setup and revert-path calls deliberately ignore return values.
// forge-lint: disable-start(unused-return)

contract DepositManagerConfigTimelockQueueEnableAssetPeriodTest is
    DepositManagerConfigTimelockTest
{
    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-I02.
    function test_givenAssetPeriodIsEnabled_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_AssetPeriodEnabled.selector,
                address(iAsset),
                DEPOSIT_PERIOD,
                DEPOSIT_OPERATOR
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueEnableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-P01, DMCT-QUEUE-ENABLE-PERIOD-N01.
    function test_givenAssetPeriodIsDisabled_queuesAndExecutesEnable(address executor_) public {
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        uint64 actionId = _queueEnablePeriod();
        _warpReady();

        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);

        assertTrue(
            depositManager.isAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR).isEnabled,
            "timelock should enable period"
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-A01.
    function test_givenAdminOnly_whenTypedActionQueued(
        address caller_
    ) public givenAssetPeriodIsDisabled {
        vm.assume(caller_ != DEPOSIT_MANAGER_ADMIN);
        _grantRole(ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(
                _configTimelock.queueEnableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.enableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-A01.
    function test_givenManagerOnly_whenTypedActionQueued(
        address caller_
    ) public givenAssetPeriodIsDisabled {
        vm.assume(caller_ != ADMIN);
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(
                _configTimelock.queueEnableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.enableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-A01.
    function test_givenBothRoles_whenTypedActionQueued(
        address caller_
    ) public givenAssetPeriodIsDisabled {
        _grantRole(ADMIN_ROLE, caller_);
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(
                _configTimelock.queueEnableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.enableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-A02.
    function test_whenTypedActionCallerUnauthorized_reverts(
        address caller_
    ) public givenAssetPeriodIsDisabled {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_MANAGER_ADMIN);
        _assertQueueRejected(
            caller_,
            abi.encodeCall(
                _configTimelock.queueEnableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-L01.
    function test_givenTimelockPaused_whenTypedActionQueued_reverts()
        public
        givenAssetPeriodIsDisabled
    {
        _pausePolicy(address(_configTimelock));
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueEnableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-L02.
    function test_givenManagerPaused_whenTypedActionQueued_reverts()
        public
        givenAssetPeriodIsDisabled
    {
        _pausePolicy(address(depositManager));
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueEnableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-L03.
    function test_givenTimelockInactive_whenTypedActionQueued_reverts()
        public
        givenAssetPeriodIsDisabled
    {
        _setPolicyActive(address(_configTimelock), false);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueEnableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-L04.
    function test_givenManagerInactive_whenTypedActionQueued_reverts()
        public
        givenAssetPeriodIsDisabled
    {
        _setPolicyActive(address(depositManager), false);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueEnableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-D01.
    function test_givenOperatorRotated_whenTypedActionQueued_reverts()
        public
        givenAssetPeriodIsDisabled
    {
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueEnableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-L05.
    function test_givenReEnabled_whenTypedActionQueued() public givenAssetPeriodIsDisabled {
        _pausePolicy(address(_configTimelock));
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueEnableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.enableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-L05.
    function test_givenReactivated_whenTypedActionQueued() public givenAssetPeriodIsDisabled {
        _setPolicyActive(address(_configTimelock), false);
        _setPolicyActive(address(depositManager), false);
        _setPolicyActive(address(depositManager), true);
        _setPolicyActive(address(_configTimelock), true);
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueEnableAssetPeriod,
                (iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.enableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-N01.
    function test_whenConfiguredPeriodSpansFullRange(uint8 period_) public {
        uint8 period = SafeCast.toUint8(bound(period_, 1, type(uint8).max));
        address other = makeAddr("fullPeriodOperator");
        vm.startPrank(ADMIN);
        depositManager.setOperatorName(other, "all");
        rolesAdmin.grantRole("deposit_operator", other);
        depositManager.addAssetPeriod(iAsset, period, other);
        depositManager.disableAssetPeriod(iAsset, period, other);
        vm.stopPrank();
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(_configTimelock.queueEnableAssetPeriod, (iAsset, period, other)),
            IDepositManager.enableAssetPeriod.selector,
            abi.encode(iAsset, period, other)
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-I01.
    function test_whenRouteAbsent_reverts(address operator_, uint8 period_) public {
        vm.assume(operator_ != DEPOSIT_OPERATOR || period_ != DEPOSIT_PERIOD);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueEnableAssetPeriod, (iAsset, period_, operator_)),
            abi.encodeWithSelector(
                IDepositManager.DepositManager_InvalidAssetPeriod.selector,
                address(iAsset),
                period_,
                operator_
            )
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-I01.
    function test_whenPeriodZero_reverts() public {
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueEnableAssetPeriod, (iAsset, 0, DEPOSIT_OPERATOR)),
            abi.encodeWithSelector(
                IDepositManager.DepositManager_InvalidAssetPeriod.selector,
                address(iAsset),
                uint8(0),
                DEPOSIT_OPERATOR
            )
        );
    }

    // Scenarios: DMCT-QUEUE-ENABLE-PERIOD-N01.
    function test_whenConfiguredMaximumPeriod() public {
        vm.startPrank(ADMIN);
        depositManager.addAssetPeriod(iAsset, type(uint8).max, DEPOSIT_OPERATOR);
        depositManager.disableAssetPeriod(iAsset, type(uint8).max, DEPOSIT_OPERATOR);
        vm.stopPrank();
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueEnableAssetPeriod,
                (iAsset, type(uint8).max, DEPOSIT_OPERATOR)
            ),
            IDepositManager.enableAssetPeriod.selector,
            abi.encode(iAsset, type(uint8).max, DEPOSIT_OPERATOR)
        );
    }
}

// forge-lint: disable-end(unused-return)
