// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {RevenueDistributorExecutionCallbackTest} from "./fixtures/RevenueDistributorExecutionCallbackTest.sol";

contract RevenueDistributorExecuteQueuedActionCallbackTest is
    RevenueDistributorExecutionCallbackTest
{
    // Scenarios: EXEC-C01.
    function test_givenSameActionCallback_whenNestedFailureCaught(address executor_) public {
        _sameActionCallback(false);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(_outerId);
        assertEq(
            _callbackAsset.callbackRevertSelector(),
            ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
            "Same action is already executed during callback"
        );
        _assertOuterCompleted();
    }

    // Scenarios: EXEC-C02.
    function test_givenIndependentActionCallback_whenNestedFailureCaught(address executor_) public {
        _independentActionCallback(false);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(_outerId);
        assertEq(
            _callbackAsset.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Independent write reaches distributor reentrancy guard"
        );
        _assertOuterCompleted();
        _assertNestedRetained();
    }

    // Scenarios: EXEC-C03.
    function test_givenSameActionCallback_whenNestedFailurePropagated_reverts(
        address executor_
    ) public {
        _sameActionCallback(true);
        vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(_outerId);
        _assertOuterRetained();
    }

    // Scenarios: EXEC-C04.
    function test_givenIndependentActionCallback_whenNestedFailurePropagated_reverts(
        address executor_
    ) public {
        _independentActionCallback(true);
        vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(_outerId);
        _assertOuterRetained();
        _assertNestedRetained();
    }
}
