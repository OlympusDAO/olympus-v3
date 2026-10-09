// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// Reverting queue calls intentionally leave their return values unused.
// forge-lint: disable-start(literal-instead-of-constant,unused-return)

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansConfigTimelockConfigGuardsTest} from "./BurnerLoansConfigTimelockConfigGuardsTest.sol";

contract BurnerLoansConfigTimelockQueueSetPriceCacheMaxAgeTest is
    BurnerLoansConfigTimelockConfigGuardsTest
{
    // when caller has no configuration role
    //  then the call reverts
    function test_whenCallerHasNoConfigurationRole_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BURNER_LOANS_ADMIN_ROLE)
        );
        vm.prank(caller_);
        configTimelock.queueSetPriceCacheMaxAge(1);
    }

    // given the caller is admin
    //  when PriceCache max age is zero
    //   then it queues the canonical payload
    function test_givenAdmin_whenPriceCacheMaxAgeIsZero_queuesCanonicalPayload() public {
        bytes memory payload = abi.encode(uint48(0));
        _expectSingleActionQueued(
            configTimelock.nextActionId(),
            admin,
            IBurnerLoansConfig.setPriceCacheMaxAge.selector,
            payload
        );

        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetPriceCacheMaxAge(0);

        (address target, bytes4 selector, bytes memory storedPayload) = configTimelock
            .getQueuedSubAction(actionId, 0);
        assertEq(target, address(burnerLoansConfig), "target");
        assertEq(selector, IBurnerLoansConfig.setPriceCacheMaxAge.selector, "selector");
        assertEq(storedPayload, payload, "canonical uint48 payload");
    }

    // given the caller is Burner Loans admin
    //  when PriceCache max age is maximum
    //   then it queues and executes the action
    function test_givenBurnerLoansAdmin_whenPriceCacheMaxAgeIsMaximum_queuesAndExecutes() public {
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetPriceCacheMaxAge(type(uint48).max);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        configTimelock.executeQueuedAction(actionId);

        assertEq(
            burnerLoans.priceCacheMaxAge(),
            type(uint48).max,
            "maximum cache age should accept uint48 maximum"
        );
    }

    // given an action is queued
    //  when executed before delay
    //   then the call reverts
    function test_givenActionQueued_whenExecutedBeforeDelay_reverts() public {
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetPriceCacheMaxAge(1);
        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                actionId,
                action.executableAt
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(burnerLoans.priceCacheMaxAge(), 0, "maximum cache age should remain unchanged");
    }

    // given an action is queued
    //  when executed after expiry
    //   then the call reverts
    function test_givenActionQueued_whenExecutedAfterExpiry_reverts() public {
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetPriceCacheMaxAge(1);
        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(actionId);
        vm.warp(uint256(action.expiresAt) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                actionId,
                action.expiresAt
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(burnerLoans.priceCacheMaxAge(), 0, "maximum cache age should remain unchanged");
    }

    // given an action is cancelled
    //  when executed
    //   then the call reverts
    function test_givenActionCancelled_whenExecuted_reverts() public {
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetPriceCacheMaxAge(1);
        vm.prank(emergency);
        configTimelock.cancelQueuedAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(burnerLoans.priceCacheMaxAge(), 0, "maximum cache age should remain unchanged");
    }

    // given a PriceCache max-age action is pending
    //  when a duplicate is queued
    //   then the call reverts
    function test_givenPriceCacheMaxAgeActionPending_whenDuplicateQueued_reverts() public {
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetPriceCacheMaxAge(1);
        bytes32 key = _scopedPriceCacheMaxAgeKey();

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                key,
                actionId
            )
        );
        vm.prank(burnerLoansAdmin);
        configTimelock.queueSetPriceCacheMaxAge(2);
    }

    // when payload is malformed
    //  then the call reverts
    function test_whenPayloadIsMalformed_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _singleAction(
            IBurnerLoansConfig.setPriceCacheMaxAge.selector,
            abi.encodePacked(uint48(1))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(burnerLoansConfig),
                IBurnerLoansConfig.setPriceCacheMaxAge.selector
            )
        );
        vm.prank(burnerLoansAdmin);
        configTimelock.queueBatch(actions);
    }

    // when uint48 payload is non-canonical
    //  then the call reverts
    function test_whenUint48PayloadIsNonCanonical_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _singleAction(
            IBurnerLoansConfig.setPriceCacheMaxAge.selector,
            abi.encode(uint256(type(uint48).max) + 1)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(burnerLoansConfig),
                IBurnerLoansConfig.setPriceCacheMaxAge.selector
            )
        );
        vm.prank(burnerLoansAdmin);
        configTimelock.queueBatch(actions);
    }

    // given the current PriceCache max age has changed after queuing
    //  when the queued action is processed
    //   then the call reverts
    function test_givenCurrentPriceCacheMaxAgeChangesAfterQueue_reverts() public {
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetPriceCacheMaxAge(2);
        (bytes32 key, bytes32 expectedHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);

        vm.prank(admin);
        burnerLoansConfig.setPriceCacheMaxAge(1);
        bytes32 currentHash = keccak256(abi.encode(address(burnerLoans), uint48(1)));
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId,
                uint256(0),
                key,
                expectedHash,
                currentHash
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(burnerLoans.priceCacheMaxAge(), 1, "direct configuration should remain active");
    }

    // when a batch combines max age and fee
    //  then it executes atomically
    function test_whenBatchCombinesMaxAgeAndFee_executesAtomically() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _feeAction(30);
        actions[1] = _singleAction(
            IBurnerLoansConfig.setPriceCacheMaxAge.selector,
            abi.encode(uint48(1))
        );

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueBatch(actions);
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        configTimelock.executeQueuedAction(actionId);

        assertEq(burnerLoans.priceCacheMaxAge(), 1, "maximum cache age");
        assertEq(burnerLoansConfig.getAssetFeeConfig(address(usds)).baseFeeBps, 30, "fee update");
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unused-return)
