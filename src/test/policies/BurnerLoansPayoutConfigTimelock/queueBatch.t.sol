// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {Actions} from "src/Kernel.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansPayoutConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansPayoutConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {stdError} from "@forge-std-1.16.2/StdError.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansPayoutConfigTimelockTest} from "./BurnerLoansPayoutConfigTimelockTest.sol";
import {BurnerLoansPayout} from "src/policies/burnerloans/BurnerLoansPayout.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract BurnerLoansPayoutConfigTimelockQueueBatchTest is BurnerLoansPayoutConfigTimelockTest {
    // Scenarios: BLCUCT-BATCH-P03.
    function test_whenFeeAndYieldFlagsAreDisabledInOneBatch_thenKeysAreIndependent() public {
        _distributor();
        _payout.setSendFeesToDistributor(true);
        _payout.setSendYieldToDistributor(true);
        vm.expectRevert(IBurnerLoansPayout.BurnerLoans_RevenueDistributorRequired.selector);
        _payout.setRevenueDistributor(address(0));

        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _action(
            IBurnerLoansPayout.setSendFeesToDistributor.selector,
            abi.encode(false)
        );
        actions[1] = _action(
            IBurnerLoansPayout.setSendYieldToDistributor.selector,
            abi.encode(false)
        );
        vm.prank(_recipient);
        uint64 id = _payoutTimelock.queueBatch(actions);
        _makeReady(id);
        _payoutTimelock.executeQueuedAction(id);
        assertFalse(_payout.sendFeesToDistributor(), "Fee flag remains false");
        assertFalse(_payout.sendYieldToDistributor(), "Yield flag changes to false");
        _payout.setRevenueDistributor(address(0));
        assertEq(
            _payout.revenueDistributor(),
            address(0),
            "ADMIN clears distributor after both flags are disabled"
        );
    }

    // Scenarios: BLCUCT-BATCH-D04.
    function test_givenInactivePayout_whenRoutingBatchQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool payoutEnabled_,
        bool flag_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _distributor();
        _setState(_payout, false, payoutEnabled_);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _action(
            IBurnerLoansPayout.setSendFeesToDistributor.selector,
            abi.encode(flag_)
        );
        actions[1] = _action(
            IBurnerLoansPayout.setSendYieldToDistributor.selector,
            abi.encode(flag_)
        );
        vm.recordLogs();
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (actions)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payout)
            ),
            caller_
        );
        assertEq(_payoutTimelock.pendingActionId(_scopedKey(actions[0])), 0, "No fee key reserved");
        assertEq(
            _payoutTimelock.pendingActionId(_scopedKey(actions[1])),
            0,
            "No yield key reserved"
        );
        assertEq(_timelockLogCount(), 0, "Rejected batch commits no queue events");
    }

    // Scenarios: BLCUCT-BATCH-N01.
    function test_whenBatchEmpty_reverts(address caller_) public {
        _grantProposer(caller_, false, false);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (new ITimelockBatchQueue.BatchAction[](0))),
            abi.encodeWithSelector(ITimelockBatchQueue.ITimelockBatchQueue_BatchEmpty.selector),
            caller_
        );
    }

    // Scenarios: BLCUCT-BATCH-N02.
    function test_whenBatchOversized_reverts(address caller_, uint8 length_) public {
        _grantProposer(caller_, false, false);
        length_ = uint8(bound(length_, 16, 64));
        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueBatch,
                (new ITimelockBatchQueue.BatchAction[](length_))
            ),
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_BatchTooLarge.selector,
                uint256(length_),
                uint256(15)
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-BATCH-A04, BLCUCT-BATCH-L01, BLCUCT-BATCH-N03.
    function test_whenValidBatchQueued_thenExactState(
        address caller_,
        bool bl_,
        bool overlap_,
        uint8 length_,
        address reader_,
        uint256 invalidIndex_,
        uint256 stateIndex_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        length_ = uint8(bound(length_, 1, 15));
        ITimelockBatchQueue.BatchAction[] memory actions = _distinctRescues(length_);
        bytes32 funds = _payoutDigest();
        _expectQueueEvents(actions, caller_);
        vm.recordLogs();
        vm.prank(caller_);
        uint64 id = _payoutTimelock.queueBatch(actions);
        assertEq(
            _timelockLogCount(),
            uint256(length_) * 2 + 1,
            "Exact guard, sub-action and closing event counts"
        );
        _assertQueued(id, actions, caller_, reader_);
        assertEq(_payoutDigest(), funds, "Queue is read-only toward Payout");
        invalidIndex_ = bound(invalidIndex_, length_, type(uint256).max);
        stateIndex_ = bound(stateIndex_, 1, type(uint256).max);
        _assertBounds(id, invalidIndex_, stateIndex_, length_, reader_);
        _assertBounds(id, length_, 1, length_, reader_);
        _assertBounds(id, type(uint256).max, type(uint256).max, length_, reader_);
        _setState(_payoutTimelock, false, false);
        _setState(_core, false, false);
        _setState(_payout, false, false);
        _rejectTargetReads();
        vm.prank(reader_);
        assertEq(
            _payoutTimelock.getQueuedActionLength(id),
            length_,
            "Stored getters ignore lifecycle and target reads"
        );
        vm.prank(reader_);
        (address target, bytes4 selector, bytes memory payload) = _payoutTimelock
            .getQueuedSubAction(id, length_ - 1);
        assertEq(target, address(_payout), "Last stored target");
        assertEq(selector, actions[length_ - 1].selector, "Last stored selector");
        assertEq(payload, actions[length_ - 1].payload, "Last stored payload");
    }

    function _distinctRescues(
        uint256 length_
    ) internal returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](length_);
        for (uint256 i; i < length_; ++i) {
            MockERC20 token = new MockERC20("Rescue", "R", 18);
            actions[i] = _action(
                IBurnerLoansPayout.rescue.selector,
                abi.encode(address(token), _borrower)
            );
        }
    }

    function _assertBounds(
        uint64 id_,
        uint256 bad_,
        uint256 state_,
        uint256 length_,
        address reader_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_SubActionIndexOutOfBounds.selector,
                id_,
                bad_,
                length_
            )
        );
        vm.prank(reader_);
        _payoutTimelock.getQueuedSubAction(id_, bad_);
        assertEq(
            _payoutTimelock.getQueuedConfigDestination(id_, bad_),
            address(0),
            "Invalid destination zero"
        );
        assertEq(_payoutTimelock.getQueuedConfigStateCount(id_, bad_), 0, "Invalid count zero");
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue
                    .IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds
                    .selector,
                id_,
                bad_,
                state_,
                uint256(0)
            )
        );
        vm.prank(reader_);
        _payoutTimelock.getQueuedConfigState(id_, bad_, state_);
        for (uint256 i; i < length_; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IConfigTimelockBatchQueue
                        .IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds
                        .selector,
                    id_,
                    i,
                    state_,
                    uint256(1)
                )
            );
            vm.prank(reader_);
            _payoutTimelock.getQueuedConfigState(id_, i, state_);
        }
    }

    // Scenarios: BLCUCT-BATCH-L02.
    function test_givenActiveDisabled_whenBatchQueued_reverts(address caller_) public {
        _setState(_payoutTimelock, true, false);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (_single(_rescueAction()))),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector),
            caller_
        );
    }

    // Scenarios: BLCUCT-BATCH-L04.
    function test_givenInactiveDisabled_whenBatchQueued_reverts(address caller_) public {
        _setState(_payoutTimelock, false, false);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (_single(_rescueAction()))),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-BATCH-L03.
    function test_givenInactive_whenBatchQueued_reverts(address caller_) public {
        _setState(_payoutTimelock, false, true);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (_single(_rescueAction()))),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-BATCH-A01.
    function test_givenUnauthorized_whenBatchQueued_reverts(
        address caller_,
        bool malformed_
    ) public {
        _excludeProposers(caller_);
        ITimelockBatchQueue.BatchAction memory action = _rescueAction();
        if (malformed_) action.payload = "";
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (_single(action))),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );
    }

    // Scenarios: BLCUCT-BATCH-A02.
    function test_givenOtherController_whenBatchQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _payout.setConfigOperator(_recipient);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (_single(_rescueAction()))),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );
    }

    // Scenarios: BLCUCT-BATCH-D01.
    function test_givenOtherKernel_whenBatchQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _mockPayoutKernel(address(0x1234));
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (_single(_rescueAction()))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_payout),
                address(_kernel),
                address(0x1234)
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-BATCH-D02.
    function test_givenDeselectedActiveTarget_whenBatchQueued_thenOriginalTarget(
        address caller_,
        bool bl_,
        bool overlap_,
        bool coreActive_,
        bool coreEnabled_,
        bool payoutEnabled_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        BurnerLoansPayout replacement = new BurnerLoansPayout(_kernel, address(_core));
        _kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        replacement.enable("");
        _core.setPayout(address(replacement));
        _setState(_core, coreActive_, coreEnabled_);
        _setState(_payout, true, payoutEnabled_);
        vm.prank(caller_);
        uint64 id = _payoutTimelock.queueBatch(_single(_rescueAction()));
        _assertQueued(id, _single(_rescueAction()), caller_, _borrower);
    }

    // Scenarios: BLCUCT-BATCH-I01, BLCUCT-BATCH-I02, BLCUCT-BATCH-I03.
    function test_whenWrongTarget_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        address target_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        vm.assume(target_ != address(_payout));
        ITimelockBatchQueue.BatchAction memory action = _rescueAction();
        action.target = target_;
        _expectInvalid(action, caller_);
    }

    // Scenarios: BLCUCT-BATCH-A03, BLCUCT-BATCH-I04.
    function test_whenSelectorNotAllowed_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bytes4 selector_
    ) public {
        vm.assume(
            selector_ != IBurnerLoansPayout.rescue.selector &&
                selector_ != IBurnerLoansPayout.rescuePendingPayout.selector &&
                selector_ != IBurnerLoansPayout.setSendFeesToDistributor.selector &&
                selector_ != IBurnerLoansPayout.setSendYieldToDistributor.selector
        );
        _grantProposer(caller_, bl_, overlap_);
        _expectInvalid(_action(selector_, ""), caller_);
    }

    // Scenarios: BLCUCT-BATCH-I05.
    function test_whenEachPayloadLengthInvalid_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        bytes4[4] memory selectors = [
            IBurnerLoansPayout.setSendFeesToDistributor.selector,
            IBurnerLoansPayout.setSendYieldToDistributor.selector,
            IBurnerLoansPayout.rescue.selector,
            IBurnerLoansPayout.rescuePendingPayout.selector
        ];
        uint256[4] memory lengths = [uint256(32), 32, 64, 128];
        for (uint256 i; i < 4; ++i) {
            _expectInvalid(_action(selectors[i], ""), caller_);
            _expectInvalid(_action(selectors[i], new bytes(lengths[i] - 1)), caller_);
            _expectInvalid(_action(selectors[i], new bytes(lengths[i] + 1)), caller_);
        }
    }

    // Scenarios: BLCUCT-BATCH-I06.
    function test_whenBooleanNoncanonical_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        uint256 word_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        word_ = bound(word_, 2, type(uint256).max);
        _expectInvalid(
            _action(IBurnerLoansPayout.setSendFeesToDistributor.selector, abi.encode(word_)),
            caller_
        );
        _expectInvalid(
            _action(IBurnerLoansPayout.setSendYieldToDistributor.selector, abi.encode(word_)),
            caller_
        );
    }

    // Scenarios: BLCUCT-BATCH-I08, BLCUCT-BATCH-I09, BLCUCT-BATCH-I10, BLCUCT-BATCH-I11, BLCUCT-BATCH-I12.
    function test_whenAddressWordNoncanonical_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        uint256 word_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        word_ = bound(word_, uint256(type(uint160).max) + 1, type(uint256).max);
        _expectInvalid(
            _action(IBurnerLoansPayout.rescue.selector, abi.encode(word_, _borrower)),
            caller_
        );
        _expectInvalid(
            _action(IBurnerLoansPayout.rescue.selector, abi.encode(address(_asset), word_)),
            caller_
        );
        _expectInvalid(
            _action(
                IBurnerLoansPayout.rescuePendingPayout.selector,
                abi.encode(word_, _recipient, _borrower, uint256(1))
            ),
            caller_
        );
        _expectInvalid(
            _action(
                IBurnerLoansPayout.rescuePendingPayout.selector,
                abi.encode(address(_asset), word_, _borrower, uint256(1))
            ),
            caller_
        );
        _expectInvalid(
            _action(
                IBurnerLoansPayout.rescuePendingPayout.selector,
                abi.encode(address(_asset), _recipient, word_, uint256(1))
            ),
            caller_
        );
    }

    function _expectInvalid(
        ITimelockBatchQueue.BatchAction memory action_,
        address caller_
    ) internal {
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (_single(action_))),
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                action_.target,
                action_.selector
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-BATCH-P01.
    function test_whenDuplicateKeysInBatch_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool different_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _rescueAction();
        actions[1] = _rescueAction();
        if (different_) actions[1].payload = abi.encode(address(_asset), _recipient);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (actions)),
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedKey(actions[0]),
                _payoutTimelock.nextActionId()
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-BATCH-P02.
    function test_givenExistingKey_whenBatchQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool expired_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        uint64 id = _payoutTimelock.queueRescue(address(_asset), _borrower);
        bytes32 queue = _queueDigest(id);
        if (expired_) vm.warp(_payoutTimelock.getQueuedAction(id).expiresAt + 1);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (_single(_rescueAction()))),
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedKey(_rescueAction()),
                id
            ),
            caller_
        );
        assertEq(_queueDigest(id), queue, "Existing owner retained");
    }

    // Scenarios: BLCUCT-BATCH-A04, BLCUCT-BATCH-P05.
    function test_whenMixedRecoveryAndFlagsQueued_thenIndependentKeys(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        bool forwardingAdmin = _roles.hasRole(address(_payoutTimelock), ADMIN_ROLE);
        _fundPending(20);
        bytes32 funds = _payoutDigest();
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](4);
        actions[0] = _action(
            IBurnerLoansPayout.setSendFeesToDistributor.selector,
            abi.encode(false)
        );
        actions[1] = _action(
            IBurnerLoansPayout.setSendYieldToDistributor.selector,
            abi.encode(false)
        );
        actions[2] = _rescueAction();
        actions[3] = _action(
            IBurnerLoansPayout.rescuePendingPayout.selector,
            abi.encode(address(_asset), _recipient, _borrower, uint256(5))
        );
        _expectQueueEvents(actions, caller_);
        vm.prank(caller_);
        uint64 id = _payoutTimelock.queueBatch(actions);
        _assertQueued(id, actions, caller_, _recipient);
        assertEq(_payoutDigest(), funds, "No entitlement debit or transfer at queue time");
        assertEq(
            _roles.hasRole(address(_payoutTimelock), ADMIN_ROLE),
            forwardingAdmin,
            "No implicit authority grant"
        );
    }

    // Scenarios: BLCUCT-BATCH-P03.
    function test_whenDisableFlagsQueuedInEitherOrder_thenIndependentKeys(
        address caller_,
        bool bl_,
        bool overlap_,
        bool reverse_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _distributor();
        _payout.setSendFeesToDistributor(true);
        _payout.setSendYieldToDistributor(true);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[reverse_ ? 1 : 0] = _action(
            IBurnerLoansPayout.setSendFeesToDistributor.selector,
            abi.encode(false)
        );
        actions[reverse_ ? 0 : 1] = _action(
            IBurnerLoansPayout.setSendYieldToDistributor.selector,
            abi.encode(false)
        );
        bytes32 funds = _payoutDigest();
        _expectQueueEvents(actions, caller_);
        vm.prank(caller_);
        uint64 id = _payoutTimelock.queueBatch(actions);
        _assertQueued(id, actions, caller_, _borrower);
        assertEq(_payoutDigest(), funds, "Queue preserves both true flags");
    }

    // Scenarios: BLCUCT-BATCH-A03, BLCUCT-BATCH-P04.
    function test_whenFlagDisableThenDistributorClearBatched_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](3);
        actions[0] = _action(
            IBurnerLoansPayout.setSendFeesToDistributor.selector,
            abi.encode(false)
        );
        actions[1] = _action(
            IBurnerLoansPayout.setSendYieldToDistributor.selector,
            abi.encode(false)
        );
        actions[2] = _action(
            IBurnerLoansPayout.setRevenueDistributor.selector,
            abi.encode(address(0))
        );
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (actions)),
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(_payout),
                IBurnerLoansPayout.setRevenueDistributor.selector
            ),
            caller_
        );
        assertEq(
            _payoutTimelock.pendingActionId(_scopedKey(actions[0])),
            0,
            "Earlier provisional key rolled back"
        );
    }

    // Scenarios: BLCUCT-BATCH-N04.
    function test_givenFinalUsableId_whenQueued_thenNoWrap(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _setNextId(type(uint64).max - 1);
        vm.prank(caller_);
        uint64 id = _payoutTimelock.queueBatch(_single(_rescueAction()));
        _assertQueued(id, _single(_rescueAction()), caller_, _borrower);
        assertEq(id, type(uint64).max - 1, "Last usable ID");
        _assertBounds(id, 1, type(uint256).max, 1, _borrower);
    }

    // Scenarios: BLCUCT-BATCH-N05.
    function test_givenExhaustedId_whenQueued_reverts(address caller_) public {
        _grantProposer(caller_, false, false);
        _setNextId(type(uint64).max);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (_single(_rescueAction()))),
            stdError.arithmeticError,
            caller_
        );
    }

    // Scenarios: BLCUCT-BATCH-N06.
    function test_givenTimestampOverflow_whenQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool expiry_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        vm.warp(uint256(type(uint48).max) - (expiry_ ? 1 days : 0));
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (_single(_rescueAction()))),
            stdError.arithmeticError,
            caller_
        );
    }

    // Scenarios: BLCUCT-BATCH-I01, BLCUCT-BATCH-I02, BLCUCT-BATCH-I03, BLCUCT-BATCH-I04, BLCUCT-BATCH-I06, BLCUCT-BATCH-I08, BLCUCT-BATCH-I09, BLCUCT-BATCH-I10, BLCUCT-BATCH-I11, BLCUCT-BATCH-I12, BLCUCT-BATCH-N02, BLCUCT-BATCH-N03.
    function test_whenBatchBoundarySeedsUsed() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenBatchOversized_reverts(address(0x111), 16);
        _restore(checkpoint);
        test_whenBatchOversized_reverts(_borrower, 64);
        _restore(checkpoint);
        test_whenValidBatchQueued_thenExactState(address(0x111), false, false, 1, address(0), 1, 1);
        _restore(checkpoint);
        test_whenValidBatchQueued_thenExactState(
            address(0x112),
            true,
            false,
            15,
            _recipient,
            type(uint256).max,
            type(uint256).max
        );
        _restore(checkpoint);
        test_whenWrongTarget_reverts(address(0x111), false, false, address(0));
        _restore(checkpoint);
        test_whenWrongTarget_reverts(address(0x112), true, false, _borrower);
        _restore(checkpoint);
        test_whenWrongTarget_reverts(
            address(0x113),
            false,
            true,
            address(new BurnerLoansPayout(_kernel, address(_core)))
        );
        _restore(checkpoint);
        test_whenSelectorNotAllowed_reverts(
            address(0x111),
            false,
            false,
            IBurnerLoansPayout.setRevenueDistributor.selector
        );
        _restore(checkpoint);
        test_whenBooleanNoncanonical_reverts(address(0x112), true, false, 2);
        _restore(checkpoint);
        test_whenBooleanNoncanonical_reverts(address(0x113), false, true, type(uint256).max);
        _restore(checkpoint);
        test_whenAddressWordNoncanonical_reverts(
            address(0x111),
            false,
            false,
            uint256(type(uint160).max) + 1
        );
        _restore(checkpoint);
        test_whenAddressWordNoncanonical_reverts(address(0x112), true, false, type(uint256).max);
        _restore(checkpoint);
    }

    // Scenarios: BLCUCT-BATCH-L05.
    function test_givenPolicyInactive_givenBrokenRoles_whenQueueRequested_reverts(
        address caller_,
        bool enabled_
    ) public {
        _setState(_payoutTimelock, false, enabled_);
        vm.etch(address(_payoutTimelock.ROLES()), hex"fe");
        uint64 next = _payoutTimelock.nextActionId();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            )
        );
        vm.prank(caller_);
        _payoutTimelock.queueBatch(new ITimelockBatchQueue.BatchAction[](0));
        assertEq(_payoutTimelock.nextActionId(), next, "Rejected local admission consumes no ID");
        assertEq(
            _payoutTimelock.getQueuedConfigStateCount(next, 0),
            0,
            "Rejected admission stores no payload"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected local admission commits no logs");
    }

    // Scenarios: BLCUCT-BATCH-L06.
    function test_givenActiveDisabled_givenBrokenRoles_whenQueueRequested_reverts(
        address caller_
    ) public {
        _setState(_payoutTimelock, true, false);
        vm.etch(address(_payoutTimelock.ROLES()), hex"fe");
        uint64 next = _payoutTimelock.nextActionId();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _payoutTimelock.queueBatch(new ITimelockBatchQueue.BatchAction[](0));
        assertEq(_payoutTimelock.nextActionId(), next, "Disabled admission consumes no ID");
        assertEq(
            _payoutTimelock.getQueuedConfigStateCount(next, 0),
            0,
            "Disabled admission stores no payload"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Disabled admission commits no logs");
    }

    // Scenarios: BLCUCT-BATCH-A05.
    function test_givenUnauthorizedCaller_givenBrokenTarget_whenQueueRequested_reverts(
        address caller_
    ) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        vm.mockCallRevert(
            address(_payout),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSignature("Unavailable()")
        );
        uint64 next = _payoutTimelock.nextActionId();
        vm.recordLogs();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _payoutTimelock.queueBatch(_single(_rescueAction()));
        assertEq(_payoutTimelock.nextActionId(), next, "Unauthorized admission consumes no ID");
        assertEq(
            _payoutTimelock.getQueuedConfigStateCount(next, 0),
            0,
            "Unauthorized admission stores no payload"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Unauthorized admission commits no logs");
    }

    // Scenarios: BLCUCT-BATCH-D03.
    function test_givenInactivePayout_whenRescueBatchQueued_reverts(
        address caller_,
        bool payoutEnabled_
    ) public {
        _grantProposer(caller_, false, false);
        _setState(_payout, false, payoutEnabled_);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueBatch, (_single(_rescueAction()))),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payout)
            ),
            caller_
        );
    }
}
