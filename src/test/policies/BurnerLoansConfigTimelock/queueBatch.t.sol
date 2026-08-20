// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansConfigTimelockConfigGuardsTest} from "./BurnerLoansConfigTimelockConfigGuardsTest.sol";

contract BurnerLoansConfigTimelockQueueBatchTest is BurnerLoansConfigTimelockConfigGuardsTest {
    // queueBatch
    // given caller has neither admin nor burner_loans_admin
    //  when queueing a valid batch
    //   then it reverts before validating sub-actions
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BURNER_LOANS_ADMIN_ROLE)
        );
        configTimelock.queueBatch(actions);
    }

    // queueBatch
    // given caller has admin role
    //  when queueing a valid mixed batch
    //   then it stores every sub-action and emits batch queue events
    function test_givenAdminCaller_whenBatchIsValid_queuesBatch() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();
        uint64 nextActionId = configTimelock.nextActionId();
        _expectBatchQueued(nextActionId, admin, actions);

        vm.prank(admin);
        uint64 actionId = configTimelock.queueBatch(actions);

        assertEq(actionId, nextActionId, "action id");
        assertEq(
            configTimelock.getQueuedActionLength(actionId),
            actions.length,
            "sub-action length"
        );
        _assertQueuedSubAction(actionId, 0, actions[0]);
        _assertQueuedSubAction(actionId, 1, actions[1]);
    }

    // queueBatch
    // given caller has burner_loans_admin role
    //  when queueing a valid mixed batch
    //   then it stores every sub-action
    function test_givenBurnerLoansAdminCaller_whenBatchIsValid_queuesBatch() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueBatch(actions);

        assertEq(actionId, 1, "action id");
        assertEq(
            configTimelock.getQueuedActionLength(actionId),
            actions.length,
            "sub-action length"
        );
    }

    function test_givenEverySupportedAction_queuesDocumentedConfigKeysAndStateHashes() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](4);
        actions[0] = _feeAction(30);
        actions[1] = _riskAction(9_500);
        actions[2] = _singleAction(
            IBurnerLoansConfig.setAssetDebtCap.selector,
            abi.encode(address(usds), uint128(90_000e9))
        );
        actions[3] = _singleAction(
            IBurnerLoansConfig.setAssetOriginationsEnabled.selector,
            abi.encode(address(usds), false)
        );

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueBatch(actions);

        address facility = burnerLoansConfig.facility();
        IBurnerLoans.AssetConfig memory config = burnerLoansConfig.getAssetConfig(address(usds));
        _assertGuard(
            actionId,
            0,
            _FEE_DOMAIN,
            keccak256(
                abi.encode(
                    facility,
                    address(usds),
                    burnerLoansConfig.getAssetFeeConfig(address(usds))
                )
            )
        );
        _assertGuard(
            actionId,
            1,
            _RISK_DOMAIN,
            keccak256(abi.encode(facility, address(usds), _assetRiskConfigInputFromConfig(config)))
        );
        _assertGuard(
            actionId,
            2,
            _DEBT_CAP_DOMAIN,
            keccak256(abi.encode(facility, address(usds), config.debtCap))
        );
        _assertGuard(
            actionId,
            3,
            _ORIGINATIONS_DOMAIN,
            keccak256(abi.encode(facility, address(usds), config.originationsEnabled))
        );
    }

    function test_givenDifferentFeeFieldsForSameAsset_revertsWithSameBatchOwner() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _feeAction(30);

        IBurnerLoans.AssetFeeConfig memory kinkUpdate;
        kinkUpdate.kinkBps = 7_500;
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory kinkSelection;
        kinkSelection.kinkBps = true;
        actions[1] = _singleAction(
            IBurnerLoansConfig.setAssetFeeConfig.selector,
            abi.encode(address(usds), kinkUpdate, kinkSelection)
        );

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedConfigKey(_FEE_DOMAIN),
                uint64(1)
            )
        );
        configTimelock.queueBatch(actions);

        assertEq(
            configTimelock.pendingActionId(_scopedConfigKey(_FEE_DOMAIN)),
            0,
            "fee key not leaked"
        );
        assertEq(configTimelock.getQueuedConfigStateCount(1, 0), 0, "fee guard rolled back");
        assertEq(configTimelock.nextActionId(), 1, "action id not consumed");
    }

    function test_givenDifferentRiskFieldsForSameAsset_revertsWithSameBatchOwner() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _riskAction(9_500);

        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory ratioUpdate;
        ratioUpdate.minCollateralRatioBps = 12_000;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory ratioSelection;
        ratioSelection.minCollateralRatioBps = true;
        actions[1] = _singleAction(
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            abi.encode(address(usds), ratioUpdate, ratioSelection)
        );

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedConfigKey(_RISK_DOMAIN),
                uint64(1)
            )
        );
        configTimelock.queueBatch(actions);

        assertEq(
            configTimelock.pendingActionId(_scopedConfigKey(_RISK_DOMAIN)),
            0,
            "risk key not leaked"
        );
        assertEq(configTimelock.getQueuedConfigStateCount(1, 0), 0, "risk guard rolled back");
        assertEq(configTimelock.nextActionId(), 1, "action id not consumed");
    }

    // queueBatch
    // given timelock policy is disabled
    //  when queueing a valid mixed batch
    //   then it reverts before storing an action
    function test_givenTimelockDisabled_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();

        vm.prank(emergency);
        configTimelock.disable("");

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueBatch
    // given BurnerLoansConfig is disabled
    //  when queueing a valid mixed batch
    //   then it reverts before storing an action
    function test_givenBurnerLoansConfigDisabled_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();
        vm.prank(emergency);
        burnerLoansConfig.disable("");

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueBatch
    // given the configured config operator has been rotated away
    //  when queueing a valid mixed batch
    //   then it reverts before storing an action
    function test_givenConfigOperatorRotated_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(address(burnerLoans));

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                address(configTimelock)
            )
        );
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueBatch
    // given batch is empty
    //  when queueing the batch
    //   then it reverts before storing an action
    function test_givenBatchIsEmpty_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](0);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(ITimelockBatchQueue.ITimelockBatchQueue_BatchEmpty.selector);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueBatch
    // given batch exceeds the configured maximum length
    //  when queueing the batch
    //   then it reverts before validating sub-actions
    function test_givenBatchTooLarge_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](
            16
        );

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_BatchTooLarge.selector,
                16,
                15
            )
        );
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueBatch
    // given one sub-action has an invalid target
    //  when queueing the batch
    //   then the whole batch reverts and no action ID is consumed
    function test_givenSubActionWrongTarget_revertsWholeQueue() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();
        actions[1].target = makeAddr("wrongTarget");

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                actions[1].target,
                actions[1].selector
            )
        );
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueBatch
    // given one sub-action has an unsupported selector
    //  when queueing the batch
    //   then the whole batch reverts and no action ID is consumed
    function test_givenSubActionUnsupportedSelector_revertsWholeQueue() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();
        actions[1].selector = bytes4(keccak256("setGlobalDebtCap(uint256)"));
        actions[1].payload = abi.encode(1_000_000e9);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                actions[1].target,
                actions[1].selector
            )
        );
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueBatch
    // given one sub-action fails config validation
    //  when queueing the batch
    //   then the whole batch reverts and no action ID is consumed
    function test_givenSubActionConfigInvalid_revertsWholeQueue() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();
        IBurnerLoans.AssetFeeConfig memory feeUpdate;
        feeUpdate.baseFeeBps = 10_001;
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory feeSelection;
        feeSelection.baseFeeBps = true;
        actions[1].payload = abi.encode(address(usds), feeUpdate, feeSelection);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, 10_001)
        );
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                uint64(1)
            )
        );
        configTimelock.getQueuedAction(1);
    }

    // queueBatch
    // given a later sub-action references an unconfigured asset
    //  when queueing a mixed batch
    //   then the whole batch reverts and no action ID is consumed
    function test_givenSubActionAssetUnconfigured_revertsWholeQueue(address asset_) public {
        vm.assume(asset_ != address(usds));
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();
        IBurnerLoans.AssetFeeConfig memory feeUpdate;
        feeUpdate.baseFeeBps = 30;
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory feeSelection;
        feeSelection.baseFeeBps = true;
        actions[1].payload = abi.encode(asset_, feeUpdate, feeSelection);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, asset_)
        );
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    function _mixedBatch()
        internal
        view
        returns (ITimelockBatchQueue.BatchAction[] memory actions)
    {
        actions = new ITimelockBatchQueue.BatchAction[](2);

        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory riskUpdate;
        riskUpdate.collateralFactorBps = 9_500;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory riskSelection;
        riskSelection.collateralFactorBps = true;
        actions[0] = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.setAssetRiskConfig.selector,
            payload: abi.encode(address(usds), riskUpdate, riskSelection)
        });

        IBurnerLoans.AssetFeeConfig memory feeUpdate;
        feeUpdate.baseFeeBps = 30;
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory feeSelection;
        feeSelection.baseFeeBps = true;
        actions[1] = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.setAssetFeeConfig.selector,
            payload: abi.encode(address(usds), feeUpdate, feeSelection)
        });
    }

    function _expectBatchQueued(
        uint64 actionId_,
        address proposer_,
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) internal {
        uint48 executableAt = uint48(block.timestamp + configTimelock.timelockDelay());
        uint48 expiresAt = executableAt + configTimelock.EXECUTION_WINDOW();

        for (uint256 i; i < actions_.length; ++i) {
            vm.expectEmit(true, true, true, true, address(configTimelock));
            emit TimelockSubActionQueued(
                actionId_,
                actions_[i].target,
                actions_[i].selector,
                i,
                keccak256(actions_[i].payload)
            );
        }
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit TimelockActionQueued(
            actionId_,
            proposer_,
            keccak256(abi.encode(actions_)),
            executableAt,
            expiresAt
        );
    }

    function _assertQueuedSubAction(
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory expected_
    ) internal view {
        (address target, bytes4 selector, bytes memory payload) = configTimelock.getQueuedSubAction(
            actionId_,
            index_
        );
        assertEq(target, expected_.target, "target");
        assertEq(selector, expected_.selector, "selector");
        assertEq(payload, expected_.payload, "payload");
    }
}
