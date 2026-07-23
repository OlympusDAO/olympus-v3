// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockQueueActionTest is BurnerLoansConfigTimelockTest {
    // queueAction
    // given target is not BurnerLoans
    //  when queueing through the raw harness
    //   then validation rejects the action
    function test_givenWrongTarget_reverts(address target_) public {
        vm.assume(target_ != address(burnerLoansConfig));
        (
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update,
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection
        ) = _collateralFactorUpdate();
        _authorizeHarness();

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                target_,
                IBurnerLoansConfig.setAssetRiskConfig.selector
            )
        );
        configTimelockHarness.queueAction(
            target_,
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            abi.encode(address(usds), update, selection)
        );
    }

    // queueAction
    // given selector is not a supported Burner Loans configuration setter
    //  when queueing through the raw harness
    //   then validation rejects the action
    function test_givenUnsupportedSelector_reverts() public {
        bytes4 unsupportedSelector = bytes4(keccak256("setGlobalDebtCap(uint256)"));
        _authorizeHarness();

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(burnerLoansConfig),
                unsupportedSelector
            )
        );
        configTimelockHarness.queueAction(
            address(burnerLoansConfig),
            unsupportedSelector,
            abi.encode(1_000_000e9)
        );
    }

    // queueAction
    // given payload length does not match the asset risk setter ABI
    //  when queueing through the raw harness
    //   then validation rejects the action
    function test_givenMalformedAssetRiskConfigPayload_reverts() public {
        _authorizeHarness();

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(0),
                IBurnerLoansConfig.setAssetRiskConfig.selector
            )
        );
        configTimelockHarness.queueAction(
            address(burnerLoansConfig),
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            abi.encode(address(usds))
        );
    }

    // queueAction
    // given payload length does not match the fee config setter ABI
    //  when queueing through the raw harness
    //   then validation rejects the action
    function test_givenMalformedFeeConfigPayload_reverts() public {
        _authorizeHarness();

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(0),
                IBurnerLoansConfig.setAssetFeeConfig.selector
            )
        );
        configTimelockHarness.queueAction(
            address(burnerLoansConfig),
            IBurnerLoansConfig.setAssetFeeConfig.selector,
            abi.encode(address(usds))
        );
    }

    // queueBatch
    // given a later asset-risk sub-action depends on an earlier sub-action in the same batch
    //  when queueing through the raw harness
    //   then validation uses the projected batch-local risk state and queues the batch
    function test_givenRiskSubActionDependsOnEarlierRiskSubAction_queuesBatch() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _riskAction(_termUpdate(14 days), _termSelection());
        actions[1] = _riskAction(_horizonUpdate(21 days), _horizonSelection());
        _authorizeHarness();

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelockHarness.queueBatch(actions);

        assertEq(actionId, 1, "action id");
        assertEq(configTimelockHarness.getQueuedActionLength(actionId), 2, "sub-action length");
    }

    // queueBatch
    // given a later asset-risk sub-action is invalid only after an earlier sub-action projection
    //  when queueing through the raw harness
    //   then validation uses the projected batch-local risk state and reverts
    function test_givenRiskSubActionInvalidAgainstEarlierRiskSubAction_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _riskAction(_termUpdate(60 days), _termSelection());
        actions[1] = _riskAction(_horizonUpdate(45 days), _horizonSelection());
        _authorizeHarness();

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        configTimelockHarness.queueBatch(actions);
    }

    // queueBatch
    // given a later fee sub-action depends on an earlier sub-action in the same batch
    //  when queueing through the raw harness
    //   then validation uses the projected batch-local fee state and queues the batch
    function test_givenFeeSubActionDependsOnEarlierFeeSubAction_queuesBatch() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _feeAction(
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 0,
                kinkBps: 0,
                preKinkSlopeBps: 0,
                postKinkSlopeBps: 0
            }),
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection({
                baseFeeBps: true,
                kinkBps: true,
                preKinkSlopeBps: true,
                postKinkSlopeBps: true
            })
        );
        actions[1] = _feeAction(
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 0,
                kinkBps: 5_000,
                preKinkSlopeBps: 10_000,
                postKinkSlopeBps: 0
            }),
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection({
                baseFeeBps: false,
                kinkBps: true,
                preKinkSlopeBps: true,
                postKinkSlopeBps: false
            })
        );
        _authorizeHarness();

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelockHarness.queueBatch(actions);

        assertEq(actionId, 1, "action id");
        assertEq(configTimelockHarness.getQueuedActionLength(actionId), 2, "sub-action length");
    }

    // queueBatch
    // given a later fee sub-action is invalid only after an earlier sub-action projection
    //  when queueing through the raw harness
    //   then validation uses the projected batch-local fee state and reverts
    function test_givenFeeSubActionInvalidAgainstEarlierFeeSubAction_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _feeAction(
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 0,
                kinkBps: 0,
                preKinkSlopeBps: 0,
                postKinkSlopeBps: 0
            }),
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection({
                baseFeeBps: false,
                kinkBps: true,
                preKinkSlopeBps: true,
                postKinkSlopeBps: true
            })
        );
        actions[1] = _feeAction(
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 0,
                kinkBps: 0,
                preKinkSlopeBps: 0,
                postKinkSlopeBps: 100
            }),
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection({
                baseFeeBps: false,
                kinkBps: false,
                preKinkSlopeBps: false,
                postKinkSlopeBps: true
            })
        );
        _authorizeHarness();

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        configTimelockHarness.queueBatch(actions);
    }

    function _authorizeHarness() internal {
        vm.prank(admin);
        burnerLoansConfig.setConfigurator(address(configTimelockHarness));
    }

    function _riskAction(
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update_,
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory action) {
        action = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.setAssetRiskConfig.selector,
            payload: abi.encode(address(usds), update_, selection_)
        });
    }

    function _feeAction(
        IBurnerLoans.AssetFeeConfig memory update_,
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory action) {
        action = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.setAssetFeeConfig.selector,
            payload: abi.encode(address(usds), update_, selection_)
        });
    }

    function _termUpdate(
        uint48 termLength_
    ) internal pure returns (IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update) {
        update.termLength = termLength_;
    }

    function _horizonUpdate(
        uint48 maxMaturityHorizon_
    ) internal pure returns (IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update) {
        update.maxMaturityHorizon = maxMaturityHorizon_;
    }

    function _termSelection()
        internal
        pure
        returns (IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection)
    {
        selection.termLength = true;
    }

    function _horizonSelection()
        internal
        pure
        returns (IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection)
    {
        selection.maxMaturityHorizon = true;
    }
}
