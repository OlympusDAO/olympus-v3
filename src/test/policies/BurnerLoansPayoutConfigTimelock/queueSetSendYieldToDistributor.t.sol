// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {BurnerLoansPayoutConfigTimelockTest} from "./BurnerLoansPayoutConfigTimelockTest.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";

contract BurnerLoansPayoutConfigTimelockQueueSetSendYieldToDistributorTest is
    BurnerLoansPayoutConfigTimelockTest
{
    // Scenarios: BLCTY-A01, BLCTY-D01, BLCTY-D02, BLCTY-D03, BLCTY-D04, BLCTY-L01, BLCTY-P01.
    function test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards(
        address caller_,
        bool bl_,
        bool overlap_,
        address reader_,
        bool coreActive_,
        bool coreEnabled_,
        bool payoutActive_,
        bool payoutEnabled_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _setState(_core, coreActive_, coreEnabled_);
        _setState(_payout, payoutActive_, payoutEnabled_);
        bytes32 funds = _payoutDigest();
        ITimelockBatchQueue.BatchAction[] memory actions = _single(
            _action(IBurnerLoansPayout.setSendYieldToDistributor.selector, abi.encode(false))
        );
        _expectQueueEvents(actions, caller_);
        vm.prank(caller_);
        uint64 id = _payoutTimelock.queueSetSendYieldToDistributor(false);
        _assertQueued(id, actions, caller_, reader_);
        assertEq(_payoutDigest(), funds, "Queue changes no target state or funds");
    }

    // Scenarios: BLCTY-A02.
    function test_givenUnauthorizedCaller_whenQueued_reverts(address caller_) public {
        _excludeProposers(caller_);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueSetSendYieldToDistributor, (false)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );

        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueSetSendYieldToDistributor, (true)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );
    }

    // Scenarios: BLCTY-L02.
    function test_givenActiveDisabled_whenQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _setState(_payoutTimelock, true, false);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueSetSendYieldToDistributor, (false)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector),
            caller_
        );
    }

    // Scenarios: BLCTY-L04.
    function test_givenInactiveDisabled_whenQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _setState(_payoutTimelock, false, false);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueSetSendYieldToDistributor, (false)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            caller_
        );
    }

    // Scenarios: BLCTY-L03.
    function test_givenInactiveEnabled_whenQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        _setState(_payoutTimelock, false, true);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueSetSendYieldToDistributor, (false)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            caller_
        );
    }

    // Scenarios: BLCTY-D05.
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
            abi.encodeCall(_payoutTimelock.queueSetSendYieldToDistributor, (false)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );
    }

    // Scenarios: BLCTY-I01.
    function test_givenKeyAlreadyOwned_whenQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool expired_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        vm.prank(caller_);
        uint64 id = _payoutTimelock.queueSetSendYieldToDistributor(false);
        bytes32 queued = _queueDigest(id);
        if (expired_) vm.warp(_payoutTimelock.getQueuedAction(id).expiresAt + 1);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueSetSendYieldToDistributor, (false)),
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedKey(
                    _action(
                        IBurnerLoansPayout.setSendYieldToDistributor.selector,
                        abi.encode(false)
                    )
                ),
                id
            ),
            caller_
        );
        assertEq(_queueDigest(id), queued, "Original queue and expired key ownership unchanged");
    }

    // Scenarios: BLCTY-I02, BLCTY-I03.
    function test_whenTrueQueued_thenDistributorRevalidated(
        address caller_,
        bool bl_,
        bool overlap_,
        bool old_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        RevenueDistributor rd = _distributor();
        _payout.setSendYieldToDistributor(old_);
        bytes32 funds = _payoutDigest();
        vm.expectCall(
            address(_payout),
            abi.encodeCall(_payout.validateRevenueDistributor, (address(rd))),
            uint64(1)
        );
        ITimelockBatchQueue.BatchAction[] memory actions = _single(
            _action(IBurnerLoansPayout.setSendYieldToDistributor.selector, abi.encode(true))
        );
        _expectQueueEvents(actions, caller_);
        vm.prank(caller_);
        uint64 id = _payoutTimelock.queueSetSendYieldToDistributor(true);
        _assertQueued(id, actions, caller_, _borrower);
        assertEq(_payoutDigest(), funds, "Flag is not set at queue time");
    }

    // Scenarios: BLCTY-I04.
    function test_givenNoDistributor_whenTrueQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool old_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        if (old_) {
            _distributor();
            _payout.setSendYieldToDistributor(true);
            vm.mockCall(
                address(_payout),
                abi.encodeWithSignature("revenueDistributor()"),
                abi.encode(address(0))
            );
        }
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueSetSendYieldToDistributor, (true)),
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_RevenueDistributorRequired.selector
            ),
            caller_
        );
    }

    // Scenarios: BLCTY-I05, BLCTY-I06, BLCTY-I07.
    function test_givenUnavailableDistributor_whenTrueQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool old_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        _grantProposer(caller_, bl_, overlap_);
        RevenueDistributor rd = _distributor();
        _payout.setSendYieldToDistributor(old_);
        _setState(rd, active_, enabled_);
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueSetSendYieldToDistributor, (true)),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(rd)
            ),
            caller_
        );
    }

    // Scenarios: BLCTY-I08.
    function test_givenDistributorKernelChanged_whenTrueQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool old_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        RevenueDistributor rd = _distributor();
        _payout.setSendYieldToDistributor(old_);
        vm.mockCall(address(rd), abi.encodeWithSignature("kernel()"), abi.encode(address(0x1234)));
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueSetSendYieldToDistributor, (true)),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(rd),
                address(_kernel),
                address(0x1234)
            ),
            caller_
        );
    }

    // Scenarios: BLCTY-I09.
    function test_givenValidatorRejects_whenTrueQueued_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        bool old_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        RevenueDistributor rd = _distributor();
        _payout.setSendYieldToDistributor(old_);
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansPayout.BurnerLoans_InvalidRevenueDistributor.selector,
            address(rd)
        );
        vm.mockCallRevert(
            address(_payout),
            abi.encodeCall(_payout.validateRevenueDistributor, (address(rd))),
            reason
        );
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueSetSendYieldToDistributor, (true)),
            reason,
            caller_
        );
    }

    // Scenarios: BLCTY-P02, BLCTY-P03.
    function test_whenFalseQueued_thenNoDistributorValidation(
        address caller_,
        bool bl_,
        bool overlap_,
        bool old_,
        bool configured_,
        bool active_,
        bool enabled_
    ) public {
        _grantProposer(caller_, bl_, overlap_);
        if (configured_ || old_) {
            RevenueDistributor rd = _distributor();
            _payout.setSendYieldToDistributor(old_);
            _setState(rd, active_, enabled_);
        }
        vm.mockCallRevert(
            address(_payout),
            abi.encodeWithSignature("validateRevenueDistributor(address)"),
            hex"deadbeef"
        );
        bytes32 funds = _payoutDigest();
        vm.prank(caller_);
        uint64 id = _payoutTimelock.queueSetSendYieldToDistributor(false);
        _assertQueued(
            id,
            _single(
                _action(IBurnerLoansPayout.setSendYieldToDistributor.selector, abi.encode(false))
            ),
            caller_,
            _borrower
        );
        assertEq(_payoutDigest(), funds, "False queue neither validates nor mutates routing");
    }

    // Scenarios: BLCTY-A01, BLCTY-D01, BLCTY-D02, BLCTY-D03, BLCTY-D04, BLCTY-L01, BLCTY-P01.
    function test_whenProposerAndLifecycleSeedsUsed_thenExactQueue() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 ca; ca < 2; ++ca)
            for (uint256 ce; ce < 2; ++ce)
                for (uint256 pa; pa < 2; ++pa)
                    for (uint256 pe; pe < 2; ++pe) {
                        test_givenPermittedProposer_whenQueued_thenExactPayloadAndGuards(
                            address(0x111),
                            false,
                            false,
                            address(0),
                            ca != 0,
                            ce != 0,
                            pa != 0,
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
                            pa != 0,
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
                            pa != 0,
                            pe != 0
                        );
                        _restore(checkpoint);
                    }
    }
}
