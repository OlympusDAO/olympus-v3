// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Setup and revert-path calls deliberately ignore return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

// Libraries
import {DEPOSIT_MANAGER_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockQueueAddAssetPeriodTest is DepositManagerConfigTimelockTest {
    // ========== TESTS ========== //

    // when the caller is neither admin nor deposit_manager_admin
    //  [X] it reverts
    // Deposit operators and emergency are deliberately not permitted to queue route creation.
    function test_whenCallerIsNotAuthorized_reverts(address caller_) public {
        vm.assume(caller_ != ADMIN);
        vm.assume(caller_ != DEPOSIT_MANAGER_ADMIN);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, DEPOSIT_MANAGER_ADMIN_ROLE)
        );

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
    function test_whenAssetIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_NotConfigured.selector));

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueAddAssetPeriod(IERC20(address(0)), DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // given the asset is not configured
    //  [X] it reverts
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
    function test_whenDepositPeriodIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_OutOfBounds.selector)
        );

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueAddAssetPeriod(iAsset, 0, DEPOSIT_OPERATOR);
    }

    // when the deposit period is one for a different approved operator
    //  [X] it queues successfully
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
    function test_whenOperatorIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_ZeroAddress.selector)
        );

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueAddAssetPeriod(iAsset, SECOND_PERIOD, address(0));
    }

    // given the operator is not registered
    //  [X] it reverts with the unregistered-operator error
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
    function test_givenPendingAdd_whenQueueingSameRouteAgain_reverts() public {
        // The queued route targets the currently unused period 2
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 actionId = _configTimelock.queueAddAssetPeriod(
            iAsset,
            SECOND_PERIOD,
            DEPOSIT_OPERATOR
        );

        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector
        );
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
    function test_givenPendingAdd_whenQueueingDisableForSameRoute_reverts() public {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueAddAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR);

        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR);

        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueDisableAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR);
    }

    // given a pending route creation
    //  [X] queueing an unrelated route remains independent
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
    function test_givenEmergency_whenQueueingRouteCreation_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, DEPOSIT_MANAGER_ADMIN_ROLE)
        );

        vm.prank(EMERGENCY);
        _configTimelock.queueAddAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }
}

// forge-lint: disable-end(unused-return)
