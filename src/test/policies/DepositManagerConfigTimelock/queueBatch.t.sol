// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// Revert-path calls deliberately ignore return values.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

contract DepositManagerConfigTimelockQueueBatchTest is DepositManagerConfigTimelockTest {
    /// @notice Governance retains direct queue authority alongside its delegated manager role.
    // Scenarios: DMCT-A01.
    function test_whenAdminQueues() public {
        _assertAuthorizedProposer(ADMIN);
    }

    /// @notice Deposit Manager Admin has the same queue permission as governance.
    // Scenarios: DMCT-A01.
    function test_whenDepositManagerAdminQueues() public {
        _assertAuthorizedProposer(DEPOSIT_MANAGER_ADMIN);
    }

    /// @notice The exact unauthorized caller set is rejected before product input validation.
    // Scenarios: DMCT-A02.
    function test_whenCallerIsUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_MANAGER_ADMIN);
        _assertUnauthorizedBatch(caller_, iAsset);
    }

    // Scenarios: DMCT-A02.
    function test_whenCallerIsUnauthorized_whenAssetIsZero_reverts(address caller_) public {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_MANAGER_ADMIN);
        _assertUnauthorizedBatch(caller_, IERC20(address(0)));
    }

    /// @notice Guarantee identities that random address generation rarely exercises.
    // Scenarios: DMCT-A02.
    function test_whenUnauthorizedIdentitiesAreSeeded_reverts() public {
        _assertUnauthorizedBatch(address(0), iAsset);
        _assertUnauthorizedBatch(address(0), IERC20(address(0)));
        _assertUnauthorizedBatch(EMERGENCY, iAsset);
        _assertUnauthorizedBatch(EMERGENCY, IERC20(address(0)));
        _assertUnauthorizedBatch(DEPOSIT_OPERATOR, iAsset);
        _assertUnauthorizedBatch(DEPOSIT_OPERATOR, IERC20(address(0)));
        _assertUnauthorizedBatch(CONFIG_OPERATOR, iAsset);
        _assertUnauthorizedBatch(CONFIG_OPERATOR, IERC20(address(0)));
    }

    /// @dev Queue one valid cap action and check authority without executing the configuration.
    function _assertAuthorizedProposer(address caller_) internal {
        uint256 initialCap = depositManager.getAssetConfiguration(iAsset).depositCap;
        uint64 expectedId = _configTimelock.nextActionId();
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _singleAction(
            IDepositManager.setAssetDepositCap.selector,
            abi.encode(iAsset, uint256(100e18))
        );
        vm.prank(caller_);
        uint64 actionId = _configTimelock.queueBatch(actions);

        assertEq(actionId, expectedId, "queue returns the reserved action ID");
        assertEq(_configTimelock.nextActionId(), expectedId + 1, "queue consumes one ID");
        ITimelockBatchQueue.QueuedAction memory queued = _configTimelock.getQueuedAction(actionId);
        assertEq(queued.proposer, caller_, "queue stores the authorized proposer");
        assertEq(queued.actions.length, 1, "queue stores one action");
        assertEq(
            queued.actions[0].target,
            address(depositManager),
            "queue targets Deposit Manager"
        );
        assertEq(queued.actions[0].selector, actions[0].selector, "queue stores the cap selector");
        assertEq(queued.actions[0].payload, actions[0].payload, "queue preserves exact parameters");
        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            initialCap,
            "queue leaves cap unchanged"
        );
    }

    /// @dev Exercise valid and zero-asset requests; both must fail at the shared caller guard.
    function _assertUnauthorizedBatch(address caller_, IERC20 asset_) internal {
        uint64 nextId = _configTimelock.nextActionId();
        uint256 initialCap = depositManager.getAssetConfiguration(iAsset).depositCap;
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _singleAction(
            IDepositManager.setAssetDepositCap.selector,
            abi.encode(asset_, uint256(100e18))
        );
        vm.recordLogs();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _configTimelock.queueBatch(actions);

        assertEq(_configTimelock.nextActionId(), nextId, "rejection consumes no action ID");
        // An absent action is reported by its exact getter error, rather than a zero length.
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                nextId
            )
        );
        _configTimelock.getQueuedActionLength(nextId);
        assertEq(
            _configTimelock.getQueuedConfigStateCount(nextId, 0),
            0,
            "rejection stores no guards"
        );
        assertEq(vm.getRecordedLogs().length, 0, "rejection emits no events");
        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            initialCap,
            "rejection preserves cap"
        );
        assertEq(
            depositManager.configOperator(),
            address(_configTimelock),
            "rejection preserves operator"
        );
    }

    // Scenarios: DMCT-BATCH-I05.
    function test_whenRouteCreationPayloadLengthIsInvalid_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _singleAction(
            IDepositManager.addAssetPeriod.selector,
            abi.encode(iAsset, SECOND_PERIOD)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(depositManager),
                IDepositManager.addAssetPeriod.selector
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueBatch(actions);
    }

    // Scenarios: DMCT-BATCH-P01.
    function test_givenConflictingRouteCreations_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _singleAction(
            IDepositManager.addAssetPeriod.selector,
            abi.encode(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
        );
        actions[1] = _singleAction(
            IDepositManager.addAssetPeriod.selector,
            abi.encode(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
        );

        _expectPendingKey(_periodKey(SECOND_PERIOD, DEPOSIT_OPERATOR), 1);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueBatch(actions);
    }

    // Scenarios: DMCT-BATCH-I06.
    function test_givenRouteCreationThenEnablementOfSameTuple_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _singleAction(
            IDepositManager.addAssetPeriod.selector,
            abi.encode(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
        );
        actions[1] = _singleAction(
            IDepositManager.enableAssetPeriod.selector,
            abi.encode(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_InvalidAssetPeriod.selector,
                address(iAsset),
                SECOND_PERIOD,
                DEPOSIT_OPERATOR
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueBatch(actions);
    }

    // Scenarios: DMCT-BATCH-N01.
    function test_whenBatchIsAtMaximum_queues() public {
        uint256 maximum = 15;
        ITimelockBatchQueue.BatchAction[] memory actions = _buildIndependentPeriodBatch(maximum);

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 actionId = _configTimelock.queueBatch(actions);

        assertEq(
            _configTimelock.getQueuedActionLength(actionId),
            maximum,
            "maximum-size batch length"
        );
    }

    // Scenarios: DMCT-BATCH-N02.
    function test_whenBatchIsAboveMaximum_reverts() public {
        uint256 maximum = 15;
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](
            maximum + 1
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_BatchTooLarge.selector,
                maximum + 1,
                maximum
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueBatch(actions);

        assertEq(_configTimelock.nextActionId(), 1, "failed batch should not consume action ID");
    }

    // Scenarios: DMCT-BATCH-I01.
    function test_whenBatchIsEmpty_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](0);

        vm.expectRevert(ITimelockBatchQueue.ITimelockBatchQueue_BatchEmpty.selector);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueBatch(actions);
    }

    // Scenarios: DMCT-BATCH-I02.
    function test_whenTargetIsInvalid_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = ITimelockBatchQueue.BatchAction({
            target: makeAddr("wrongTarget"),
            selector: IDepositManager.setAssetDepositCap.selector,
            payload: abi.encode(iAsset, uint256(100e18))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                actions[0].target,
                actions[0].selector
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueBatch(actions);
    }

    // Scenarios: DMCT-BATCH-I03.
    function test_whenSelectorIsInvalid_reverts() public {
        bytes4 invalidSelector = 0xdeadbeef;
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _singleAction(invalidSelector, bytes(""));

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(depositManager),
                invalidSelector
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueBatch(actions);
    }

    // Scenarios: DMCT-BATCH-I04.
    function test_whenPayloadLengthIsInvalid_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _singleAction(IDepositManager.setAssetDepositCap.selector, abi.encode(iAsset));

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(depositManager),
                IDepositManager.setAssetDepositCap.selector
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueBatch(actions);
    }

    // Scenarios: DMCT-BATCH-P02.
    function test_givenSameAssetCapAndMinimum_whenQueuedTogether_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _singleAction(
            IDepositManager.setAssetDepositCap.selector,
            abi.encode(iAsset, uint256(100e18))
        );
        actions[1] = _singleAction(
            IDepositManager.setAssetMinimumDeposit.selector,
            abi.encode(iAsset, uint256(1e18))
        );

        _expectPendingKey(_limitsKey(iAsset), 1);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueBatch(actions);

        assertEq(_configTimelock.nextActionId(), 1, "failed batch should not consume action ID");
    }

    // Scenarios: DMCT-BATCH-P03.
    function test_givenIndependentActions_queuesAndExecutesAtomically(address executor_) public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _singleAction(
            IDepositManager.setAssetDepositCap.selector,
            abi.encode(iAsset, uint256(100e18))
        );
        actions[1] = _singleAction(
            IDepositManager.disableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );

        vm.prank(ADMIN);
        uint64 actionId = _configTimelock.queueBatch(actions);
        _warpReady();

        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            100e18,
            "batch should update deposit cap"
        );
        assertFalse(
            depositManager.isAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR).isEnabled,
            "batch should disable asset period"
        );
    }

    // Scenarios: DMCT-BATCH-T01.
    function test_givenLaterActionStateIsStale_executionRollsBackEarlierAction() public {
        uint256 initialCap = depositManager.getAssetConfiguration(iAsset).depositCap;
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _singleAction(
            IDepositManager.setAssetDepositCap.selector,
            abi.encode(iAsset, uint256(100e18))
        );
        actions[1] = _singleAction(
            IDepositManager.disableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 actionId = _configTimelock.queueBatch(actions);
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        _warpReady();

        _expectStale(actionId, 1, keccak256(abi.encode(true, false)));
        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            initialCap,
            "failed batch should roll back earlier cap update"
        );
        _assertPending(actionId);
    }

    function _buildIndependentPeriodBatch(
        uint256 length_
    ) internal returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](length_);
        vm.startPrank(ADMIN);
        for (uint256 i = 0; i < length_; ++i) {
            // The helper is used only for the 15- and 16-action boundary cases, so 100 + i fits
            // safely in uint8.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 depositPeriod = uint8(100 + i);
            // This loop intentionally configures each independent period needed by the batch.
            // forge-lint: disable-next-line(calls-loop)
            depositManager.addAssetPeriod(iAsset, depositPeriod, DEPOSIT_OPERATOR);
            actions[i] = _singleAction(
                IDepositManager.disableAssetPeriod.selector,
                abi.encode(iAsset, depositPeriod, DEPOSIT_OPERATOR)
            );
        }
        vm.stopPrank();
    }

    // Scenarios: DMCT-BATCH-N03.
    function test_whenBatchLengthSpansValidRange(uint8 length_) public {
        uint256 length = bound(length_, 1, 15);
        ITimelockBatchQueue.BatchAction[] memory actions = _buildIndependentPeriodBatch(length);
        vm.prank(ADMIN);
        uint64 id = _configTimelock.queueBatch(actions);
        assertEq(_configTimelock.getQueuedActionLength(id), length, "full valid batch domain");
        assertEq(_configTimelock.maxConfigKeysPerBatch(), 15, "batch key bound");
        assertEq(_configTimelock.nextActionId(), id + 1, "batch consumes one ID");
    }

    // Scenarios: DMCT-BATCH-I07.
    function test_whenAssetWordNoncanonical_reverts() public {
        _malformedBatch(
            IDepositManager.setAssetDepositCap.selector,
            abi.encode(type(uint256).max, uint256(1))
        );
    }

    // Scenarios: DMCT-BATCH-I08.
    function test_whenPeriodWordNoncanonical_reverts() public {
        _malformedBatch(
            IDepositManager.addAssetPeriod.selector,
            abi.encode(iAsset, uint256(256), DEPOSIT_OPERATOR)
        );
    }

    // Scenarios: DMCT-BATCH-I09.
    function test_whenBooleanWordNoncanonical_reverts() public {
        _malformedBatch(
            IDepositManagerV1_1.setAssetShareWithdrawalRequired.selector,
            abi.encode(iAsset, uint256(2))
        );
    }

    function _malformedBatch(bytes4 selector_, bytes memory payload_) private {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _singleAction(selector_, payload_);
        // Solidity's ABI decoder supplies no typed error for noncanonical narrow values.
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueBatch, (actions)),
            bytes("")
        );
    }

    // Scenarios: DMCT-BATCH-L01.
    function test_givenPolicyInactive_givenBrokenRoles_whenQueueRequested_reverts(
        address caller_,
        bool enabled_
    ) public {
        if (!enabled_) _pausePolicy(address(_configTimelock));
        _setPolicyActive(address(_configTimelock), false);
        vm.etch(address(_configTimelock.ROLES()), hex"fe");
        uint64 next = _configTimelock.nextActionId();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
        vm.prank(caller_);
        _configTimelock.queueBatch(new ITimelockBatchQueue.BatchAction[](0));
        assertEq(_configTimelock.nextActionId(), next, "Rejected local admission consumes no ID");
        assertEq(
            _configTimelock.getQueuedConfigStateCount(next, 0),
            0,
            "Rejected admission stores no payload"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected local admission commits no logs");
    }

    // Scenarios: DMCT-BATCH-L02.
    function test_givenActiveDisabled_givenBrokenRoles_whenQueueRequested_reverts(
        address caller_
    ) public {
        _pausePolicy(address(_configTimelock));
        vm.etch(address(_configTimelock.ROLES()), hex"fe");
        uint64 next = _configTimelock.nextActionId();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _configTimelock.queueBatch(new ITimelockBatchQueue.BatchAction[](0));
        assertEq(_configTimelock.nextActionId(), next, "Disabled admission consumes no ID");
        assertEq(
            _configTimelock.getQueuedConfigStateCount(next, 0),
            0,
            "Disabled admission stores no payload"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Disabled admission commits no logs");
    }

    // Scenarios: DMCT-BATCH-A01.
    function test_givenUnauthorizedCaller_givenBrokenTarget_whenQueueRequested_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_MANAGER_ADMIN);
        _setPolicyActive(address(depositManager), false);
        uint64 next = _configTimelock.nextActionId();
        vm.recordLogs();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _configTimelock.queueBatch(new ITimelockBatchQueue.BatchAction[](0));
        assertEq(_configTimelock.nextActionId(), next, "Unauthorized admission consumes no ID");
        assertEq(
            _configTimelock.getQueuedConfigStateCount(next, 0),
            0,
            "Unauthorized admission stores no payload"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Unauthorized admission commits no logs");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
