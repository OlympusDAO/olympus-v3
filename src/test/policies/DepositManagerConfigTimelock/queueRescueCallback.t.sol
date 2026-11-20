// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {DepositManagerConfigTimelockRescueTest} from "./fixtures/DepositManagerConfigTimelockRescueTest.sol";
import {RescueCallbackToken} from "./fixtures/RescueCallbackToken.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";

contract DepositManagerConfigTimelockQueueRescueCallbackTest is
    DepositManagerConfigTimelockRescueTest
{
    // Scenarios: DMCT-RESCUE-C01.
    function test_givenTokenCatchesSameActionCallback_whenRescueExecuted(address executor_) public {
        RescueCallbackToken token = new RescueCallbackToken();
        token.mint(address(depositManager), 10);
        uint64 id = _queueRescue(ADMIN, address(token));
        token.setCallbackFrom(
            address(depositManager),
            address(_configTimelock),
            abi.encodeCall(_configTimelock.executeQueuedAction, (id))
        );
        _warpReady();

        _assertRescueExecuted(id, address(token), 10, executor_);

        assertFalse(token.callbackSucceeded(), "same action cannot execute twice");
        assertEq(
            token.callbackRevertData(),
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                id
            ),
            "same action callback exact terminal-state error"
        );
        assertEq(token.transferCallCount(), 1, "outer rescue transfers exactly once");
    }

    // Scenarios: DMCT-RESCUE-C02.
    function test_givenTokenPropagatesDistinctActionCallback_whenRescueExecuted_reverts(
        address executor_
    ) public {
        RescueCallbackToken token = new RescueCallbackToken();
        token.mint(address(depositManager), 10);
        _otherToken.mint(address(depositManager), 20);
        uint64 first = _queueRescue(ADMIN, address(token));
        uint64 second = _queueRescue(DEPOSIT_MANAGER_ADMIN, address(_otherToken));
        token.setCallbackFrom(
            address(depositManager),
            address(_configTimelock),
            abi.encodeCall(_configTimelock.executeQueuedAction, (second))
        );
        token.setBubbleCallbackFailure(true);
        _warpReady();
        bytes32 beforeState = _targetState();

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vm.prank(executor_);
        _configTimelock.executeQueuedAction(first);

        _assertPending(first);
        _assertPending(second);
        assertEq(token.balanceOf(address(depositManager)), 10, "first token custody rolled back");
        assertEq(
            _otherToken.balanceOf(address(depositManager)),
            20,
            "nested token custody unchanged"
        );
        assertEq(token.balanceOf(address(trsry)), 0, "first Treasury receipt rolled back");
        assertEq(_otherToken.balanceOf(address(trsry)), 0, "nested Treasury receipt rolled back");
        assertEq(token.transferCallCount(), 0, "token-side transfer count rolled back");
        assertTrue(token.callbackEnabled(), "token-side callback flag rolled back");
        assertEq(
            _targetState(),
            beforeState,
            "callback failure preserves managed custody and accounting"
        );

        // The nested action is mature, has its own free execution path, and succeeds without the outer DM guard.
        _assertRescueExecuted(second, address(_otherToken), 20, executor_);
        _assertPending(first);
    }
}
