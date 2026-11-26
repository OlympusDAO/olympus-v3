// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";

contract BurnerLoansRiskConfigTimelockCancelQueuedActionTest is BurnerLoansRiskConfigTimelockTest {
    // Scenarios: BLRCT-CANCEL-A01, BLRCT-CANCEL-P01.
    function test_givenPending_whenEmergencyCancels(
        address caller_,
        bool enabled_,
        uint48 now_
    ) public {
        vm.assume(caller_ != address(0) && caller_ != _fixtureAdmin);
        _grantFixtureRole(EMERGENCY_ROLE, caller_);
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_threeActions());
        _setPolicyLifecycle(_timelock, true, enabled_);
        vm.warp(bound(now_, vm.getBlockTimestamp(), type(uint48).max));
        vm.mockCallRevert(address(_risk), abi.encodeWithSignature("kernel()"), hex"ff");
        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockActionCancelled(id, caller_);
        vm.prank(caller_);
        _timelock.cancelQueuedAction(id);
        assertTrue(_timelock.getQueuedAction(id).cancelled, "cancelled marker");
        _assertCleared(id, _threeActions());
        assertEq(_risk.referralFeeBps(), 0, "cancellation no target mutation");
    }

    // Scenarios: BLRCT-CANCEL-A02.
    function test_whenUnauthorized_reverts(address caller_, bool enabled_) public {
        vm.assume(caller_ != _fixtureAdmin && !_roles.hasRole(caller_, EMERGENCY_ROLE));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        bytes32 queued = _queueDigest(id);
        _setPolicyLifecycle(_timelock, true, enabled_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _timelock.cancelQueuedAction(id);
        assertEq(_queueDigest(id), queued, "failed cancellation keeps complete intent");
    }

    // Scenarios: BLRCT-CANCEL-L01.
    function test_givenInactive_whenCancelled_reverts(bool enabled_) public {
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _setPolicyLifecycle(_timelock, false, enabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.cancelQueuedAction(id);
        assertEq(
            _timelock.pendingActionId(_key(_bpsAction(2500))),
            id,
            "failed cancellation retains key"
        );
    }

    // Scenarios: BLRCT-CANCEL-A03.
    function test_givenPending_whenProposerCancels() public {
        _assertProposerCancellation(false);
    }

    // Scenarios: BLRCT-CANCEL-A04.
    function test_givenRevokedProposer_whenProposerCancels() public {
        _assertProposerCancellation(true);
    }

    function _assertProposerCancellation(bool revokeRole_) private {
        address proposer = makeAddr("proposer");
        _grantFixtureRole(BURNER_LOANS_ADMIN_ROLE, proposer);
        ITimelockBatchQueue.BatchAction[] memory actions = _threeActions();
        vm.prank(proposer);
        uint64 id = _timelock.queueBatch(actions);
        if (revokeRole_) _revokeFixtureRole(BURNER_LOANS_ADMIN_ROLE, proposer);

        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockActionCancelled(id, proposer);
        vm.prank(proposer);
        _timelock.cancelQueuedAction(id);

        assertTrue(_timelock.getQueuedAction(id).cancelled, "proposer cancellation recorded");
        _assertCleared(id, actions);
        assertEq(_risk.referralFeeBps(), 0, "cancellation preserves referral fee");
    }

    // Scenarios: BLRCT-CANCEL-I01.
    function test_whenUnknownID_reverts(uint64 id_, address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                id_
            )
        );
        vm.prank(caller_);
        _timelock.cancelQueuedAction(id_);
    }

    // Scenarios: BLRCT-CANCEL-I02.
    function test_givenExecuted_whenCancelled_reverts() public {
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _makeReady(id);
        _timelock.executeQueuedAction(id);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                id
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.cancelQueuedAction(id);
    }

    // Scenarios: BLRCT-CANCEL-I03.
    function test_givenCancelled_whenRepeated_reverts() public {
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        vm.prank(_fixtureAdmin);
        _timelock.cancelQueuedAction(id);
        vm.prank(_fixtureAdmin);
        _timelock.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                id
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.cancelQueuedAction(id);
    }

    // Scenarios: BLRCT-CANCEL-P01.
    function test_givenExpired_whenCancelledAndRequeued() public {
        vm.prank(_fixtureAdmin);
        uint64 old = _timelock.queueSetReferralFeeBps(2500);
        vm.warp(uint256(_timelock.getQueuedAction(old).expiresAt) + 1);
        vm.prank(_fixtureAdmin);
        _timelock.cancelQueuedAction(old);
        vm.prank(_fixtureAdmin);
        uint64 fresh = _timelock.queueSetReferralFeeBps(2500);
        assertEq(fresh, old + 1, "new intent ID");
        assertEq(
            _timelock.getQueuedAction(fresh).executableAt,
            vm.getBlockTimestamp() + 1 days,
            "fresh full delay"
        );
    }
}
