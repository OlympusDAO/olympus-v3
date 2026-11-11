// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, DEPOSIT_MANAGER_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

// Setup and revert-path calls deliberately ignore return values.
// forge-lint: disable-start(unused-return)

contract DepositManagerConfigTimelockQueueAddAssetPeriodTest is DepositManagerConfigTimelockTest {
    // ========== TESTS ========== //

    // when the caller is neither admin nor deposit_manager_admin
    //  [X] it reverts
    // Deposit operators and emergency are deliberately not permitted to queue route creation.
    // Scenarios: DMCT-A03.
    function test_whenCallerIsNotAuthorized_reverts(address caller_) public {
        vm.assume(caller_ != ADMIN);
        vm.assume(caller_ != DEPOSIT_MANAGER_ADMIN);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(caller_);
        _configTimelock.queueAddAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // given the caller is admin
    //  [X] the route creation is queued with the addAssetPeriod selector
    function test_whenAdmin_succeeds() public {
        vm.prank(ADMIN);
        uint64 actionId = _configTimelock.queueAddAssetPeriod(
            iAsset,
            SECOND_PERIOD,
            DEPOSIT_OPERATOR
        );

        (address target, bytes4 selector, ) = _configTimelock.getQueuedSubAction(actionId, 0);
        assertEq(target, address(depositManager), "target does not match deposit manager");
        assertEq(selector, IDepositManager.addAssetPeriod.selector, "selector mismatch");
    }

    // given the asset is zero
    //  [X] it reverts
    // Scenarios: DMCT-QUEUE-ADD-PERIOD-I01.
    function test_whenAssetIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_NotConfigured.selector));

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueAddAssetPeriod(IERC20(address(0)), DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // given the asset is not configured
    //  [X] it reverts
    // Scenarios: DMCT-QUEUE-ADD-PERIOD-I02.
    function test_whenAssetIsNotConfigured_reverts() public {
        MockERC20 unconfiguredAsset = new MockERC20("Unconfigured", "UNCFG", 18);

        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_NotConfigured.selector));

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueAddAssetPeriod(
            IERC20(address(unconfiguredAsset)),
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
    }

    // when the deposit period is zero
    //  [X] it reverts
    // Scenarios: DMCT-QUEUE-ADD-PERIOD-I03.
    function test_whenDepositPeriodIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_OutOfBounds.selector)
        );

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueAddAssetPeriod(iAsset, 0, DEPOSIT_OPERATOR);
    }

    // when the deposit period is one for a different approved operator
    //  [X] it queues successfully
    // Scenarios: DMCT-QUEUE-ADD-PERIOD-N01.
    function test_whenDepositPeriodIsOne_succeeds() public {
        address periodOneOperator = makeAddr("PeriodOneOperator");
        vm.startPrank(ADMIN);
        depositManager.setOperatorName(periodOneOperator, "one");
        rolesAdmin.grantRole("deposit_operator", periodOneOperator);
        vm.stopPrank();

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 actionId = _configTimelock.queueAddAssetPeriod(iAsset, 1, periodOneOperator);

        assertEq(actionId, 1, "one-month deposit period should queue successfully");
    }

    // when the deposit period is the maximum representable value
    //  [X] it queues successfully
    // Scenarios: DMCT-QUEUE-ADD-PERIOD-N01.
    function test_whenDepositPeriodIsMaximum_succeeds() public {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 actionId = _configTimelock.queueAddAssetPeriod(
            iAsset,
            type(uint8).max,
            DEPOSIT_OPERATOR
        );

        assertEq(actionId, 1, "maximum deposit period should queue successfully");
    }

    // when the operator is zero
    //  [X] it reverts with the zero-address error
    // Scenarios: DMCT-QUEUE-ADD-PERIOD-I04.
    function test_whenOperatorIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_ZeroAddress.selector)
        );

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueAddAssetPeriod(iAsset, SECOND_PERIOD, address(0));
    }

    // given the operator is not registered
    //  [X] it reverts with the unregistered-operator error
    // Scenarios: DMCT-QUEUE-ADD-PERIOD-I05.
    function test_whenOperatorIsUnregistered_reverts() public {
        address unregisteredOperator = makeAddr("UnregisteredOperator");

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_OperatorNameNotSet.selector,
                unregisteredOperator
            )
        );

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueAddAssetPeriod(iAsset, DEPOSIT_PERIOD, unregisteredOperator);
    }

    // given the operator is registered but does not hold deposit_operator
    //  [X] it reverts with the typed role error
    // Scenarios: DMCT-QUEUE-ADD-PERIOD-I06.
    function test_whenOperatorHoldsNoDepositOperatorRole_reverts() public {
        address operatorWithoutRole = makeAddr("OperatorWithoutRole");
        vm.prank(ADMIN);
        depositManager.setOperatorName(operatorWithoutRole, "opr");

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerV1_1.DepositManager_DepositOperatorRoleNotHeld.selector,
                operatorWithoutRole
            )
        );

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueAddAssetPeriod(iAsset, DEPOSIT_PERIOD, operatorWithoutRole);
    }

    // given the asset-period-operator route already exists
    //  [X] it reverts
    // Scenarios: DMCT-QUEUE-ADD-PERIOD-I07.
    function test_givenRouteExists_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_AssetPeriodExists.selector,
                address(iAsset),
                DEPOSIT_PERIOD,
                DEPOSIT_OPERATOR
            )
        );

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueAddAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // given a pending route creation
    //  [X] queueing another creation for the same tuple reverts on the reserved key
    // Scenarios: DMCT-QUEUE-ADD-PERIOD-P01.
    function test_givenPendingAdd_whenQueueingSameRouteAgain_reverts() public {
        // The queued route targets the currently unused period 2
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 actionId = _configTimelock.queueAddAssetPeriod(
            iAsset,
            SECOND_PERIOD,
            DEPOSIT_OPERATOR
        );

        _expectPendingKey(_periodKey(SECOND_PERIOD, DEPOSIT_OPERATOR), actionId);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueAddAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR);

        assertEq(
            _configTimelock.nextActionId(),
            actionId + 1,
            "failed queue should not consume an extra action ID"
        );
    }

    // given a pending route creation that was made valid by direct creation
    //  [X] queueing disablement for the same tuple reverts on the reserved key
    // Scenarios: DMCT-QUEUE-ADD-PERIOD-P02.
    function test_givenPendingAdd_whenQueueingDisableForSameRoute_reverts() public {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueAddAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR);

        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR);

        _expectPendingKey(_periodKey(SECOND_PERIOD, DEPOSIT_OPERATOR), 1);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueDisableAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR);
    }

    // given a pending route creation
    //  [X] queueing an unrelated route remains independent
    // Scenarios: DMCT-QUEUE-ADD-PERIOD-P03.
    function test_givenPendingAdd_whenQueueingDifferentRoute_succeeds() public {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 firstActionId = _configTimelock.queueAddAssetPeriod(
            iAsset,
            SECOND_PERIOD,
            DEPOSIT_OPERATOR
        );

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 secondActionId = _configTimelock.queueAddAssetPeriod(
            iAsset,
            SECOND_PERIOD + 1,
            DEPOSIT_OPERATOR
        );

        assertEq(
            secondActionId,
            firstActionId + 1,
            "unrelated asset-period tuples should have independent keys"
        );
    }

    // given an emergency caller
    //  [X] queueing route creation reverts
    // Scenarios: DMCT-A03.
    function test_givenEmergency_whenQueueingRouteCreation_reverts() public {
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(EMERGENCY);
        _configTimelock.queueAddAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // Scenarios: DMCT-QUEUE-ADD-PERIOD-A01.
    function test_givenAdminOnly_whenTypedActionQueued(address caller_) public {
        vm.assume(caller_ != DEPOSIT_MANAGER_ADMIN);
        _grantRole(ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(
                _configTimelock.queueAddAssetPeriod,
                (iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.addAssetPeriod.selector,
            abi.encode(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-ADD-PERIOD-A01.
    function test_givenManagerOnly_whenTypedActionQueued(address caller_) public {
        vm.assume(caller_ != ADMIN);
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(
                _configTimelock.queueAddAssetPeriod,
                (iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.addAssetPeriod.selector,
            abi.encode(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-ADD-PERIOD-A01.
    function test_givenBothRoles_whenTypedActionQueued(address caller_) public {
        _grantRole(ADMIN_ROLE, caller_);
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(
                _configTimelock.queueAddAssetPeriod,
                (iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.addAssetPeriod.selector,
            abi.encode(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-ADD-PERIOD-A02.
    function test_whenTypedActionCallerUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_MANAGER_ADMIN);
        _assertQueueRejected(
            caller_,
            abi.encodeCall(
                _configTimelock.queueAddAssetPeriod,
                (iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-ADD-PERIOD-L01.
    function test_givenTimelockPaused_whenTypedActionQueued_reverts() public {
        _pausePolicy(address(_configTimelock));
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueAddAssetPeriod,
                (iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-ADD-PERIOD-L02.
    function test_givenManagerPaused_whenTypedActionQueued_reverts() public {
        _pausePolicy(address(depositManager));
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueAddAssetPeriod,
                (iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-ADD-PERIOD-L03.
    function test_givenTimelockInactive_whenTypedActionQueued_reverts() public {
        _setPolicyActive(address(_configTimelock), false);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueAddAssetPeriod,
                (iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-ADD-PERIOD-L04.
    function test_givenManagerInactive_whenTypedActionQueued_reverts() public {
        _setPolicyActive(address(depositManager), false);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueAddAssetPeriod,
                (iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-ADD-PERIOD-D01.
    function test_givenOperatorRotated_whenTypedActionQueued_reverts() public {
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueAddAssetPeriod,
                (iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
            ),
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-ADD-PERIOD-L05.
    function test_givenReEnabled_whenTypedActionQueued() public {
        _pausePolicy(address(_configTimelock));
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueAddAssetPeriod,
                (iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.addAssetPeriod.selector,
            abi.encode(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-ADD-PERIOD-L05.
    function test_givenReactivated_whenTypedActionQueued() public {
        _setPolicyActive(address(_configTimelock), false);
        _setPolicyActive(address(depositManager), false);
        _setPolicyActive(address(depositManager), true);
        _setPolicyActive(address(_configTimelock), true);
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(
                _configTimelock.queueAddAssetPeriod,
                (iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
            ),
            IDepositManager.addAssetPeriod.selector,
            abi.encode(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-QUEUE-ADD-PERIOD-N01.
    function test_whenNewPeriodSpansFullRange(uint8 period_) public {
        uint8 period = SafeCast.toUint8(bound(period_, 1, type(uint8).max));
        address other = makeAddr("fullPeriodOperator");
        vm.startPrank(ADMIN);
        depositManager.setOperatorName(other, "all");
        rolesAdmin.grantRole("deposit_operator", other);
        vm.stopPrank();
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(_configTimelock.queueAddAssetPeriod, (iAsset, period, other)),
            IDepositManager.addAssetPeriod.selector,
            abi.encode(iAsset, period, other)
        );
    }
}

// forge-lint: disable-end(unused-return)
