// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {Actions} from "src/Kernel.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockExecuteTest is DepositManagerConfigTimelockTest {
    function test_givenBeforeDelay_reverts(uint48 elapsed_) public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(actionId);
        uint256 elapsed = bound(elapsed_, 0, _configTimelock.timelockDelay() - 1);
        vm.warp(uint256(action.queuedAt) + elapsed);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                actionId,
                action.executableAt
            )
        );
        _configTimelock.executeQueuedAction(actionId);
    }

    function test_givenWithinExecutionWindow_executes(address executor_, uint48 elapsed_) public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(actionId);
        uint256 elapsed = bound(
            elapsed_,
            _configTimelock.timelockDelay(),
            _configTimelock.timelockDelay() + _configTimelock.EXECUTION_WINDOW()
        );
        vm.warp(uint256(action.queuedAt) + elapsed);

        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            100e18,
            "execution should update deposit cap"
        );
    }

    function test_givenExecutionWindowExpired_reverts(uint48 elapsedAfterExpiry_) public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(actionId);
        uint256 elapsedAfterExpiry = bound(elapsedAfterExpiry_, 1, 365 days);
        vm.warp(uint256(action.expiresAt) + elapsedAfterExpiry);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                actionId,
                action.expiresAt
            )
        );
        _configTimelock.executeQueuedAction(actionId);
    }

    function test_givenDepositManagerIsDisabled_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(EMERGENCY);
        depositManager.disable("");
        _warpReady();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        _configTimelock.executeQueuedAction(actionId);
    }

    function test_givenTimelockIsDisabled_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(EMERGENCY);
        _configTimelock.disable("");
        _warpReady();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        _configTimelock.executeQueuedAction(actionId);
    }

    function test_givenTimelockPolicyIsInactive_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(_configTimelock));
        _warpReady();

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
        _configTimelock.executeQueuedAction(actionId);
    }

    function test_givenDepositManagerPolicyIsInactive_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        _warpReady();

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(depositManager)
            )
        );
        _configTimelock.executeQueuedAction(actionId);
    }

    function test_givenPoliciesAreReactivated_executes() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(_configTimelock));
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(_configTimelock));
        vm.stopPrank();
        _warpReady();

        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            100e18,
            "reactivated policies should permit queued execution"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
