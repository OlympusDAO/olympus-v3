// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {BurnerLoansPayoutConfigTimelockTest} from "./BurnerLoansPayoutConfigTimelockTest.sol";

contract BurnerLoansPayoutConfigTimelockQueueRescueTest is BurnerLoansPayoutConfigTimelockTest {
    // Scenarios: BLCTR-A01, BLCTR-D01, BLCTR-D02, BLCTR-D03, BLCTR-D04, BLCTR-L01, BLCTR-P01.
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
        _setState(_core, coreActive_, coreEnabled_);
        _setState(_payout, true, payoutEnabled_);
        bytes32 funds = _payoutDigest();
        ITimelockBatchQueue.BatchAction[] memory actions = _single(
            _action(IBurnerLoansPayout.rescue.selector, abi.encode(address(_asset), _borrower))
        );
        _expectQueueEvents(actions, caller_);
        vm.prank(caller_);
        uint64 id = _payoutTimelock.queueRescue(address(_asset), _borrower);
        _assertQueued(id, actions, caller_, reader_);
        assertEq(_payoutDigest(), funds, "Queue changes no target state or funds");
    }

    // Scenarios: BLCTR-D06.
    function test_givenInactivePayout_whenPermittedProposerQueues_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool coreActive_,
        bool coreEnabled_,
        bool payoutEnabled_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _setState(_core, coreActive_, coreEnabled_);
        _setState(_payout, false, payoutEnabled_);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueRescue, (address(_asset), _borrower)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payout)
            ),
            caller_
        );
    }

    // Scenarios: BLCTR-A02.
    function test_givenUnauthorizedCaller_whenQueued_reverts(address caller_) public {
        _excludeProposers(caller_);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueRescue, (address(_asset), _borrower)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );

        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueRescue, (address(0), address(0))),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );
    }

    // Scenarios: BLCTR-L02.
    function test_givenActiveDisabled_whenQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _setState(_payoutTimelock, true, false);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueRescue, (address(_asset), _borrower)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector),
            caller_
        );
    }

    // Scenarios: BLCTR-L04.
    function test_givenInactiveDisabled_whenQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _setState(_payoutTimelock, false, false);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueRescue, (address(_asset), _borrower)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            caller_
        );
    }

    // Scenarios: BLCTR-L03.
    function test_givenInactiveEnabled_whenQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _setState(_payoutTimelock, false, true);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueRescue, (address(_asset), _borrower)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            caller_
        );
    }

    // Scenarios: BLCTR-D05.
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
        _payout.setConfigOperator(_recipient);
        _setState(_core, coreActive_, coreEnabled_);
        _setState(_payout, payoutActive_, payoutEnabled_);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueRescue, (address(_asset), _borrower)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );
    }

    // Scenarios: BLCTR-I01.
    function test_givenKeyAlreadyOwned_whenQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool expired_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        vm.prank(caller_);
        uint64 id = _payoutTimelock.queueRescue(address(_asset), _borrower);
        bytes32 queued = _queueDigest(id);
        if (expired_) vm.warp(_payoutTimelock.getQueuedAction(id).expiresAt + 1);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueRescue, (address(_asset), _borrower)),
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedKey(
                    _action(
                        IBurnerLoansPayout.rescue.selector,
                        abi.encode(address(_asset), _borrower)
                    )
                ),
                id
            ),
            caller_
        );
        assertEq(_queueDigest(id), queued, "Original queue and expired key ownership unchanged");
    }

    // Scenarios: BLCTR-I02, BLCTR-I03.
    function test_whenTokenHasNoCode_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        address token_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        vm.assume(token_.code.length == 0);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueRescue, (token_, _borrower)),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidAsset.selector, token_),
            caller_
        );
    }

    // Scenarios: BLCTR-I02.
    function test_whenTokenZero_reverts() public {
        test_whenTokenHasNoCode_reverts(address(0x111), false, false, address(0));
    }

    // Scenarios: BLCTR-I04.
    function test_whenDestinationZero_reverts(address caller_, bool bl_, bool overlap_) public {
        _grantProposer(caller_, bl_, overlap_);
        _expectInvalidDestination(address(0), caller_);
    }

    // Scenarios: BLCTR-I05.
    function test_whenDestinationCore_reverts(address caller_, bool bl_, bool overlap_) public {
        _grantProposer(caller_, bl_, overlap_);
        _expectInvalidDestination(address(_core), caller_);
    }

    // Scenarios: BLCTR-I06.
    function test_whenDestinationPayout_reverts(address caller_, bool bl_, bool overlap_) public {
        _grantProposer(caller_, bl_, overlap_);
        _expectInvalidDestination(address(_payout), caller_);
    }

    // Scenarios: BLCTR-I07.
    function test_whenDestinationToken_reverts(address caller_, bool bl_, bool overlap_) public {
        _grantProposer(caller_, bl_, overlap_);
        _expectInvalidDestination(address(_asset), caller_);
    }

    // Scenarios: BLCTR-I08.
    function test_whenDestinationTimelock_reverts(address caller_, bool bl_, bool overlap_) public {
        _grantProposer(caller_, bl_, overlap_);
        _expectInvalidDestination(address(_payoutTimelock), caller_);
    }

    // Scenarios: BLCTR-I09.
    function test_whenDestinationKernel_reverts(address caller_, bool bl_, bool overlap_) public {
        _grantProposer(caller_, bl_, overlap_);
        _expectInvalidDestination(address(_kernel), caller_);
    }

    // Scenarios: BLCTR-A01, BLCTR-D01, BLCTR-D02, BLCTR-D03, BLCTR-D04, BLCTR-L01, BLCTR-P01.
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
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueRescue, (address(_asset), destination_)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                destination_
            ),
            caller_
        );
    }
}
