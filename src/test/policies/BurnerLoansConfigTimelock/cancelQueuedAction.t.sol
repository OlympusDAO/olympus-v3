// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";
import {BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract BurnerLoansConfigTimelockCancelQueuedActionTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLCT-CANCEL-L01.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_thenCleared(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, true, false);
        _setPolicyLifecycle(_timelock, true, true);
        _cancelAndAssert(id, caller_);
    }

    // Scenarios: BLCT-CANCEL-L02.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_thenCleared(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, false, true);
        _setPolicyLifecycle(_timelock, true, true);
        _cancelAndAssert(id, caller_);
    }

    // Scenarios: BLCT-CANCEL-L03.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_thenCleared(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, false, false);
        _setPolicyLifecycle(_timelock, true, true);
        _cancelAndAssert(id, caller_);
    }

    // Scenarios: BLCT-CANCEL-L04.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_thenCleared(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, true, true);
        _setPolicyLifecycle(_timelock, true, false);
        _cancelAndAssert(id, caller_);
    }

    // Scenarios: BLCT-CANCEL-L05.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_thenCleared(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, true, false);
        _setPolicyLifecycle(_timelock, true, false);
        _cancelAndAssert(id, caller_);
    }

    // Scenarios: BLCT-CANCEL-L06.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_thenCleared(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, false, true);
        _setPolicyLifecycle(_timelock, true, false);
        _cancelAndAssert(id, caller_);
    }

    // Scenarios: BLCT-CANCEL-L07.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_thenCleared(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, false, false);
        _setPolicyLifecycle(_timelock, true, false);
        _cancelAndAssert(id, caller_);
    }

    // Scenarios: BLCT-CANCEL-L08.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, true, true);
        _setPolicyLifecycle(_timelock, false, true);
        _cancelReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-CANCEL-L09.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, true, false);
        _setPolicyLifecycle(_timelock, false, true);
        _cancelReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-CANCEL-L10.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, false, true);
        _setPolicyLifecycle(_timelock, false, true);
        _cancelReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-CANCEL-L11.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, false, false);
        _setPolicyLifecycle(_timelock, false, true);
        _cancelReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-CANCEL-L12.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, true, true);
        _setPolicyLifecycle(_timelock, false, false);
        _cancelReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-CANCEL-L13.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, true, false);
        _setPolicyLifecycle(_timelock, false, false);
        _cancelReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-CANCEL-L14.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, false, true);
        _setPolicyLifecycle(_timelock, false, false);
        _cancelReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-CANCEL-L15.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts(
        address caller_
    ) public {
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.assume(caller_ != address(0));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setPolicyLifecycle(_config, false, false);
        _setPolicyLifecycle(_timelock, false, false);
        _cancelReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-CANCEL-I01.
    function test_givenMissingZeroId_whenCancel_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                uint64(0)
            )
        );
        vm.prank(caller_);
        _timelock.cancelQueuedAction(uint64(0));
    }

    // Scenarios: BLCT-CANCEL-N01.
    function test_givenMissingNonzeroId_whenCancel_reverts(address caller_, uint64 id_) public {
        id_ = uint64(bound(id_, 1, type(uint64).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                id_
            )
        );
        vm.prank(caller_);
        _timelock.cancelQueuedAction(id_);
    }

    // Scenarios: BLCT-CANCEL-A01.
    function test_givenReadyAction_whenCancel_thenComplete(address caller_) public {
        vm.assume(caller_ != address(0));
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _cancelAndAssert(id, caller_);
    }

    // Scenarios: BLCT-CANCEL-P01.
    function test_givenAlreadyCancelled_whenCancelled_reverts(address caller_) public {
        vm.assume(caller_ != address(0));
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        vm.prank(_fixtureAdmin);
        _timelock.cancelQueuedAction(id);
        _cancelReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                id
            )
        );
    }

    // Scenarios: BLCT-CANCEL-P03.
    function test_givenAlreadyExecuted_whenCancelled_reverts(address caller_) public {
        vm.assume(caller_ != address(0));
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _executeAndAssert(id, address(this));
        _cancelReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                id
            )
        );
    }

    // Scenarios: BLCT-CANCEL-P02.
    function test_givenPendingExpired_whenCancelled_thenAllKeysReleased(address caller_) public {
        vm.assume(caller_ != address(0));
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(
            _pair(_capAction(address(_asset), 200000e9), _feeAction(address(_asset), _fees()))
        );
        vm.warp(uint256(_timelock.getQueuedAction(id).expiresAt) + 1);
        assertEq(
            _timelock.pendingActionId(_key(_capAction(address(_asset), 200000e9))),
            id,
            "Unresolved key remains held even after expiry"
        );
        _cancelAndAssert(id, caller_);
    }

    // Scenarios: BLCT-CANCEL-P04.
    function test_givenPendingBeforeReady_whenCancelled_thenAllKeysReleased(
        address caller_
    ) public {
        vm.assume(caller_ != address(0));
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(
            _pair(_capAction(address(_asset), 200000e9), _feeAction(address(_asset), _fees()))
        );
        assertEq(
            _timelock.pendingActionId(_key(_capAction(address(_asset), 200000e9))),
            id,
            "Unresolved key remains held even after expiry"
        );
        _cancelAndAssert(id, caller_);
    }

    // Scenarios: BLCT-CANCEL-P05.
    function test_givenPendingWithinWindow_whenCancelled_thenAllKeysReleased(
        address caller_,
        uint48 now_
    ) public {
        vm.assume(caller_ != address(0));
        _grantRoleIfMissing(EMERGENCY_ROLE, caller_);
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(
            _pair(_capAction(address(_asset), 200000e9), _feeAction(address(_asset), _fees()))
        );
        vm.warp(
            bound(
                now_,
                _timelock.getQueuedAction(id).executableAt,
                _timelock.getQueuedAction(id).expiresAt
            )
        );
        assertEq(
            _timelock.pendingActionId(_key(_capAction(address(_asset), 200000e9))),
            id,
            "Unresolved key remains held even after expiry"
        );
        _cancelAndAssert(id, caller_);
    }

    // Scenarios: BLCT-CANCEL-A01.
    function test_givenExistingEmergency_whenReadyActionCancelled_thenComplete() public {
        address emergency = makeAddr("configTimelockEmergency");
        _grantFixtureRole(EMERGENCY_ROLE, emergency);
        test_givenReadyAction_whenCancel_thenComplete(emergency);
    }

    // Scenarios: BLCT-CANCEL-A02.
    function test_givenPending_whenProposerCancelsAtTimeBoundaries() public {
        address proposer = makeAddr("proposer");
        _grantFixtureRole(BURNER_LOANS_ADMIN_ROLE, proposer);
        ITimelockBatchQueue.BatchAction[] memory actions = _pair(
            _capAction(address(_asset), 200000e9),
            _feeAction(address(_asset), _fees())
        );
        vm.prank(proposer);
        uint64 id = _timelock.queueBatch(actions);
        ITimelockBatchQueue.QueuedAction memory queued = _timelock.getQueuedAction(id);
        uint256 checkpoint = vm.snapshotState();

        vm.warp(queued.executableAt - 1);
        _cancelAndAssert(id, proposer);
        _restore(checkpoint);

        vm.warp(queued.executableAt);
        _cancelAndAssert(id, proposer);
        _restore(checkpoint);

        vm.warp(queued.expiresAt);
        _cancelAndAssert(id, proposer);
        _restore(checkpoint);

        vm.warp(uint256(queued.expiresAt) + 1);
        _cancelAndAssert(id, proposer);
    }

    // Scenarios: BLCT-CANCEL-A03.
    function test_givenExpiredBatch_whenAnotherProposerCancels_reverts() public {
        address otherProposer = makeAddr("otherProposer");
        _grantFixtureRole(BURNER_LOANS_ADMIN_ROLE, otherProposer);
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        vm.warp(uint256(_timelock.getQueuedAction(id).expiresAt) + 1);

        _cancelReverts(
            id,
            otherProposer,
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }
}
