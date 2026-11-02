// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {BurnerLoansPayoutConfigTimelockTest} from "./BurnerLoansPayoutConfigTimelockTest.sol";

contract BurnerLoansPayoutConfigTimelockQueueRescuePendingPayoutTest is
    BurnerLoansPayoutConfigTimelockTest
{
    // Scenarios: BLCTRP-A01, BLCTRP-D01, BLCTRP-D02, BLCTRP-D03, BLCTRP-D04, BLCTRP-L01, BLCTRP-P01.
    function test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards(
        address caller_,
        bool bl_,
        bool overlap_,
        address reader_,
        bool coreActive_,
        bool coreEnabled_,
        bool payoutEnabled_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _fundPending(20);
        _setState(_core, coreActive_, coreEnabled_);
        _setState(_payout, true, payoutEnabled_);
        bytes32 funds = _payoutDigest();
        ITimelockBatchQueue.BatchAction[] memory actions = _single(
            _action(
                IBurnerLoansPayout.rescuePendingPayout.selector,
                abi.encode(address(_asset), _recipient, _borrower, uint256(1))
            )
        );
        _expectQueueEvents(actions, caller_);
        vm.prank(caller_);
        uint64 id = _payoutTimelock.queueRescuePendingPayout(
            address(_asset),
            _recipient,
            _borrower,
            1
        );
        _assertQueued(id, actions, caller_, reader_);
        assertEq(_payoutDigest(), funds, "Queue changes no target state or funds");
    }

    // Scenarios: BLCTRP-D06.
    function test_givenInactivePayout_whenPermittedProposerQueues_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool coreActive_,
        bool coreEnabled_,
        bool payoutEnabled_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _fundPending(20);
        _setState(_core, coreActive_, coreEnabled_);
        _setState(_payout, false, payoutEnabled_);
        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueRescuePendingPayout,
                (address(_asset), _recipient, _borrower, uint256(1))
            ),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payout)
            ),
            caller_
        );
    }

    // Scenarios: BLCTRP-A02.
    function test_givenUnauthorizedCaller_whenQueued_reverts(address caller_) public {
        _excludeProposers(caller_);
        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueRescuePendingPayout,
                (address(_asset), _recipient, _borrower, 1)
            ),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );

        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueRescuePendingPayout,
                (address(0), address(0), address(0), uint256(0))
            ),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );
    }

    // Scenarios: BLCTRP-L02.
    function test_givenActiveDisabled_whenQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _fundPending(20);
        _setState(_payoutTimelock, true, false);
        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueRescuePendingPayout,
                (address(_asset), _recipient, _borrower, 1)
            ),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector),
            caller_
        );
    }

    // Scenarios: BLCTRP-L04.
    function test_givenInactiveDisabled_whenQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _fundPending(20);
        _setState(_payoutTimelock, false, false);
        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueRescuePendingPayout,
                (address(_asset), _recipient, _borrower, 1)
            ),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            caller_
        );
    }

    // Scenarios: BLCTRP-L03.
    function test_givenInactiveEnabled_whenQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _fundPending(20);
        _setState(_payoutTimelock, false, true);
        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueRescuePendingPayout,
                (address(_asset), _recipient, _borrower, 1)
            ),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            caller_
        );
    }

    // Scenarios: BLCTRP-D05.
    function test_givenControllerReplaced_whenQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool coreActive_,
        bool coreEnabled_,
        bool payoutActive_,
        bool payoutEnabled_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _fundPending(20);
        _payout.setConfigOperator(_recipient);
        _setState(_core, coreActive_, coreEnabled_);
        _setState(_payout, payoutActive_, payoutEnabled_);
        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueRescuePendingPayout,
                (address(_asset), _recipient, _borrower, 1)
            ),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );
    }

    // Scenarios: BLCTRP-I01.
    function test_givenKeyAlreadyOwned_whenQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool expired_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _fundPending(20);
        vm.prank(caller_);
        uint64 id = _payoutTimelock.queueRescuePendingPayout(
            address(_asset),
            _recipient,
            _borrower,
            1
        );
        bytes32 queued = _queueDigest(id);
        if (expired_) vm.warp(_payoutTimelock.getQueuedAction(id).expiresAt + 1);
        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueRescuePendingPayout,
                (address(_asset), _recipient, _borrower, 1)
            ),
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedKey(
                    _action(
                        IBurnerLoansPayout.rescuePendingPayout.selector,
                        abi.encode(address(_asset), _recipient, _borrower, uint256(1))
                    )
                ),
                id
            ),
            caller_
        );
        assertEq(_queueDigest(id), queued, "Original queue and expired key ownership unchanged");
    }

    // Scenarios: BLCTRP-I02, BLCTRP-I03.
    function test_whenTokenHasNoCode_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        address token_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        vm.assume(token_.code.length == 0);
        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueRescuePendingPayout,
                (token_, _recipient, _borrower, uint256(1))
            ),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidAsset.selector, token_),
            caller_
        );
    }

    // Scenarios: BLCTRP-I02.
    function test_whenTokenZero_reverts() public {
        test_whenTokenHasNoCode_reverts(address(0x111), false, false, address(0));
    }

    // Scenarios: BLCTRP-I05.
    function test_whenDestinationZero_reverts(address caller_, bool bl_, bool overlap_) public {
        _grantProposer(caller_, bl_, overlap_);
        _expectInvalidDestination(address(0), caller_);
    }

    // Scenarios: BLCTRP-I06.
    function test_whenDestinationCore_reverts(address caller_, bool bl_, bool overlap_) public {
        _grantProposer(caller_, bl_, overlap_);
        _expectInvalidDestination(address(_core), caller_);
    }

    // Scenarios: BLCTRP-I07.
    function test_whenDestinationPayout_reverts(address caller_, bool bl_, bool overlap_) public {
        _grantProposer(caller_, bl_, overlap_);
        _expectInvalidDestination(address(_payout), caller_);
    }

    // Scenarios: BLCTRP-I08.
    function test_whenDestinationToken_reverts(address caller_, bool bl_, bool overlap_) public {
        _grantProposer(caller_, bl_, overlap_);
        _expectInvalidDestination(address(_asset), caller_);
    }

    // Scenarios: BLCTRP-I09.
    function test_whenDestinationTimelock_reverts(address caller_, bool bl_, bool overlap_) public {
        _grantProposer(caller_, bl_, overlap_);
        _expectInvalidDestination(address(_payoutTimelock), caller_);
    }

    // Scenarios: BLCTRP-I10.
    function test_whenDestinationKernel_reverts(address caller_, bool bl_, bool overlap_) public {
        _grantProposer(caller_, bl_, overlap_);
        _expectInvalidDestination(address(_kernel), caller_);
    }

    // Scenarios: BLCTRP-I04.
    function test_whenRecipientZero_reverts(address caller_, bool bl_, bool overlap_) public {
        _grantProposer(caller_, bl_, overlap_);
        _fundPending(20);
        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueRescuePendingPayout,
                (address(_asset), address(0), _borrower, uint256(1))
            ),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector),
            caller_
        );
    }

    // Scenarios: BLCTRP-N01.
    function test_whenAmountZero_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool funded_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        if (funded_) _fundPending(20);
        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueRescuePendingPayout,
                (address(_asset), _recipient, _borrower, uint256(0))
            ),
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector),
            caller_
        );
    }

    // Scenarios: BLCTRP-N02.
    function test_givenNoEntitlement_whenPositiveAmountQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        uint256 amount_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        amount_ = bound(amount_, 1, type(uint256).max);
        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueRescuePendingPayout,
                (address(_asset), _recipient, _borrower, amount_)
            ),
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_InsufficientPendingPayout.selector,
                address(_asset),
                amount_,
                uint256(0)
            ),
            caller_
        );
    }

    // Scenarios: BLCTRP-N03.
    function test_givenInsufficientEntitlement_whenAmountQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        uint256 available_,
        uint256 amount_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        available_ = bound(available_, 1, type(uint256).max - 1);
        amount_ = bound(amount_, available_ + 1, type(uint256).max);
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansPayout.BurnerLoans_InsufficientPendingPayout.selector,
            address(_asset),
            amount_,
            available_
        );
        vm.mockCallRevert(
            address(_payout),
            abi.encodeCall(
                _payout.previewRescuePendingPayout,
                (address(_asset), _recipient, _borrower, amount_)
            ),
            reason
        );
        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueRescuePendingPayout,
                (address(_asset), _recipient, _borrower, amount_)
            ),
            reason,
            caller_
        );
    }

    // Scenarios: BLCTRP-N06.
    function test_whenMaximumAmountAcceptedByPreview_thenExactPayload(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        bytes memory preview = abi.encodeCall(
            _payout.previewRescuePendingPayout,
            (address(_asset), _recipient, _borrower, type(uint256).max)
        );
        vm.mockCall(address(_payout), preview, abi.encode(type(uint256).max));
        vm.expectCall(address(_payout), preview, uint64(1));
        ITimelockBatchQueue.BatchAction[] memory actions = _single(
            _action(
                IBurnerLoansPayout.rescuePendingPayout.selector,
                abi.encode(address(_asset), _recipient, _borrower, type(uint256).max)
            )
        );
        _expectQueueEvents(actions, caller_);
        vm.prank(caller_);
        uint64 id = _payoutTimelock.queueRescuePendingPayout(
            address(_asset),
            _recipient,
            _borrower,
            type(uint256).max
        );
        _assertQueued(id, actions, caller_, _borrower);
    }

    // Scenarios: BLCTRP-N01, BLCTRP-N02, BLCTRP-N03.
    function test_whenPendingAmountBoundarySeedsUsed_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenNoEntitlement_whenPositiveAmountQueued_reverts(address(0x111), false, false, 1);
        _restore(checkpoint);
        test_givenNoEntitlement_whenPositiveAmountQueued_reverts(
            address(0x112),
            true,
            false,
            type(uint256).max
        );
        _restore(checkpoint);
        test_givenInsufficientEntitlement_whenAmountQueued_reverts(
            address(0x113),
            false,
            true,
            1,
            2
        );
        _restore(checkpoint);
        test_givenInsufficientEntitlement_whenAmountQueued_reverts(
            address(0x111),
            false,
            false,
            type(uint256).max - 1,
            type(uint256).max
        );
        _restore(checkpoint);

        test_whenAmountZero_reverts(address(0x111), false, false, false);
        _restore(checkpoint);
        test_whenAmountZero_reverts(address(0x112), true, false, true);
        _restore(checkpoint);
    }

    // Scenarios: BLCTRP-A01, BLCTRP-D01, BLCTRP-D02, BLCTRP-D03, BLCTRP-D04, BLCTRP-L01, BLCTRP-P01.
    function test_whenProposerAndLifecycleSeedsUsed_thenExactQueue() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 ca; ca < 2; ++ca)
            for (uint256 ce; ce < 2; ++ce)
                for (uint256 pe; pe < 2; ++pe) {
                    test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards(
                        address(0x111),
                        false,
                        false,
                        address(0),
                        ca != 0,
                        ce != 0,
                        pe != 0
                    );
                    _restore(checkpoint);
                    test_givenInactivePayout_whenPermittedProposerQueues_reverts(
                        address(0x111),
                        false,
                        false,
                        ca != 0,
                        ce != 0,
                        pe != 0
                    );
                    _restore(checkpoint);
                    test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards(
                        address(0x112),
                        true,
                        false,
                        address(this),
                        ca != 0,
                        ce != 0,
                        pe != 0
                    );
                    _restore(checkpoint);
                    test_givenInactivePayout_whenPermittedProposerQueues_reverts(
                        address(0x112),
                        true,
                        false,
                        ca != 0,
                        ce != 0,
                        pe != 0
                    );
                    _restore(checkpoint);
                    test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards(
                        address(0x113),
                        false,
                        true,
                        _recipient,
                        ca != 0,
                        ce != 0,
                        pe != 0
                    );
                    _restore(checkpoint);
                    test_givenInactivePayout_whenPermittedProposerQueues_reverts(
                        address(0x113),
                        false,
                        true,
                        ca != 0,
                        ce != 0,
                        pe != 0
                    );
                    _restore(checkpoint);
                }
    }

    function _expectInvalidDestination(address destination_, address caller_) internal {
        _fundPending(20);
        _expectQueueRejected(
            abi.encodeCall(
                _payoutTimelock.queueRescuePendingPayout,
                (address(_asset), _recipient, destination_, uint256(1))
            ),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                destination_
            ),
            caller_
        );
    }
}
