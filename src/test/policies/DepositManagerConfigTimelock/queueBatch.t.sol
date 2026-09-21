// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// Revert-path calls deliberately ignore return values.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Interfaces
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockQueueBatchTest is DepositManagerConfigTimelockTest {
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

    function test_whenBatchIsEmpty_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](0);

        vm.expectRevert(ITimelockBatchQueue.ITimelockBatchQueue_BatchEmpty.selector);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueBatch(actions);
    }

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

        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueBatch(actions);

        assertEq(_configTimelock.nextActionId(), 1, "failed batch should not consume action ID");
    }

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

        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector
        );
        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            initialCap,
            "failed batch should roll back earlier cap update"
        );
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
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
