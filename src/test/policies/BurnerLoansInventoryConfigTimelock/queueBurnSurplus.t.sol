// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Bounded seed loops intentionally repeat isolated contract calls.
// Literal amounts, delays and timestamps are independent expected test values.
// Expected-revert calls and repeated configuration probes discard their return values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, unused-return)

// Interfaces
import {Vm} from "forge-std/Vm.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansInventoryConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryConfigTimelockTest} from "./BurnerLoansInventoryConfigTimelockTest.sol";

contract BurnerLoansInventoryConfigTimelockQueueBurnSurplusTest is
    BurnerLoansInventoryConfigTimelockTest
{
    // Scenarios: BLINCT-BURN-A01.
    function test_givenBurnerLoansAdmin_whenBurnQueued_thenNoticePrecedesBurn() public {
        _supplyInventory(_borrower, 50e9);
        _ohm.mint(address(_inventory), 1e9);
        vm.prank(_recipient);
        uint64 id = _timelock.queueBurnSurplus();
        assertEq(_inventory.surplusOhm(), 1e9, "Queue does not burn tokens");
        uint256 supply = _ohm.totalSupply();
        _makeReady(id);
        _timelock.executeQueuedAction(id);
        assertEq(_ohm.totalSupply(), supply - 1e9, "Only surplus is burned");
        assertEq(_ohm.balanceOf(address(_inventory)), 50e9, "Idle remains backed");
        assertEq(_inventory.suppliedOhm(), 50e9, "Provider claims unchanged");
    }

    // Scenarios: BLINCT-BURN-L01.
    function test_givenDisabledInventory_whenBurnQueued_reverts() public {
        _inventory.disable("");
        _expectQueueRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_inventory)
            ),
            address(this)
        );
    }

    // Scenarios: BLINCT-BURN-A01, BLINCT-BURN-P07.
    function test_givenPermittedProposer_whenQueued_thenExactMetadataAndEvents(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public givenProviderSurplus {
        _grantRecoveryAdmin(caller_, blAdmin_, overlap_);
        _assertRecoveryQueued(
            _timelock.queueBurnSurplus,
            IBurnerLoansInventory.burnSurplus.selector,
            caller_
        );
    }

    // Scenarios: BLINCT-BURN-A01.
    function test_givenEachPermittedRole_whenQueued_thenExactMetadata() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPermittedProposer_whenQueued_thenExactMetadataAndEvents(
            address(0xabc1),
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore for BL-admin-only proposer");
        test_givenPermittedProposer_whenQueued_thenExactMetadataAndEvents(
            address(0xabc2),
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore for overlapping proposer");
        test_givenPermittedProposer_whenQueued_thenExactMetadataAndEvents(
            address(0xabc3),
            false,
            true
        );
    }

    // Scenarios: BLINCT-BURN-A02.
    function test_whenUnauthorizedProposer_reverts(address caller_) public givenProviderSurplus {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        _expectQueueRejected(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector), caller_);
    }

    // Scenarios: BLINCT-BURN-A03.
    function test_givenAnotherController_whenQueued_reverts() public {
        _inventory.setConfigOperator(_inventoryConfigurator);
        _expectQueueRejected(
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            address(this)
        );
    }

    // Scenarios: BLINCT-BURN-A04.
    function test_givenClearedController_whenQueued_reverts() public {
        _inventory.setConfigOperator(address(0));
        _expectQueueRejected(
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            address(this)
        );
    }

    // Scenarios: BLINCT-BURN-L03.
    function test_givenActiveDisabledTimelock_whenQueued_reverts() public {
        _setState(_timelock, true, false);
        _expectQueueRejected(abi.encodeWithSelector(IEnabler.NotEnabled.selector), address(this));
    }

    // Scenarios: BLINCT-BURN-L04.
    function test_givenInactiveDisabledTimelock_whenQueued_reverts() public {
        _setState(_timelock, false, false);
        _expectQueueRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            ),
            address(this)
        );
    }

    // Scenarios: BLINCT-BURN-L05.
    function test_givenInactiveTimelock_whenQueued_reverts() public {
        _setState(_timelock, false, true);
        _expectQueueRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            ),
            address(this)
        );
    }

    // Scenarios: BLINCT-BURN-L06, BLINCT-BURN-L07.
    function test_givenInactiveTarget_whenQueued_reverts(bool enabled_) public {
        _setState(_inventory, false, enabled_);
        _expectQueueRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_inventory)
            ),
            address(this)
        );
    }

    // Scenarios: BLINCT-BURN-D01.
    function test_givenTargetKernelDrift_whenQueued_reverts() public {
        _mockInventoryKernel(address(0xbeef));
        _expectQueueRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_inventory),
                address(_kernel),
                address(0xbeef)
            ),
            address(this)
        );
    }

    // Scenarios: BLINCT-BURN-L08.
    function test_givenReEnabled_whenQueued_thenOneAction() public {
        _timelock.disable("");
        _timelock.reEnable();
        uint64 id = _timelock.queueBurnSurplus();
        _assertQueued(id, IBurnerLoansInventory.burnSurplus.selector, address(this));
    }

    // Scenarios: BLINCT-BURN-P03.
    function test_givenSameActionPending_whenQueued_reverts() public {
        uint64 id = _timelock.queueBurnSurplus();
        _expectQueueRejected(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _key(),
                id
            ),
            address(this)
        );
    }

    // Scenarios: BLINCT-BURN-P02, BLINCT-RESCUE-P02.
    function test_givenRescuePending_whenBurnQueued_reverts() public {
        uint64 id = _timelock.queueRescueSurplus();
        _expectQueueRejected(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _key(),
                id
            ),
            address(this)
        );
    }

    // Scenarios: BLINCT-BURN-P04.
    function test_givenAnyCoreLifecycle_whenQueued_thenIndependent(
        bool active_,
        bool enabled_
    ) public {
        _setState(_core, active_, enabled_);
        uint64 id = _timelock.queueBurnSurplus();
        _assertQueued(id, IBurnerLoansInventory.burnSurplus.selector, address(this));
    }

    // Scenarios: BLINCT-BURN-P04.
    function test_givenEachCoreLifecyclePair_whenQueued_thenIndependent() public {
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                uint256 checkpoint = vm.snapshotState();
                test_givenAnyCoreLifecycle_whenQueued_thenIndependent(active != 0, enabled != 0);
                assertTrue(vm.revertToState(checkpoint), "Restore Core and queue for next state");
            }
        }
    }

    // Scenarios: BLINCT-BURN-P05.
    function test_givenNoSurplus_whenExecuted_thenNoInventoryEventAndKeyReleased() public {
        uint64 id = _timelock.queueBurnSurplus();
        _makeReady(id);
        bytes32 beforeFunds = _inventoryDigest();
        vm.recordLogs();
        _timelock.executeQueuedAction(id);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i)
            assertTrue(
                logs[i].emitter != address(_inventory),
                "No Inventory event for zero surplus"
            );
        assertEq(_inventoryDigest(), beforeFunds, "No-op preserves all Inventory state");
        _assertCleared(id);
    }

    // Scenarios: BLINCT-BURN-P06.
    function test_givenSurplusArrivesDuringNotice_whenExecuted_thenLiveAmount()
        public
        givenProviderSurplus
    {
        uint64 id = _timelock.queueBurnSurplus();
        _ohm.mint(address(_inventory), 2e9);
        uint256 beforeSupply = _ohm.totalSupply();
        uint256 beforeTreasury = _ohm.balanceOf(_treasury());
        _makeReady(id);
        _timelock.executeQueuedAction(id);
        _assertBacking(50e9);
        _assertCleared(id);
        assertEq(
            _ohm.totalSupply(),
            beforeSupply - 3e9,
            "Burn live surplus, not the queued balance"
        );
        assertEq(_ohm.balanceOf(_treasury()), beforeTreasury, "Burn does not transfer to Treasury");
    }

    // Scenarios: BLINCT-BURN-N01.
    function test_givenExhaustedCounter_whenQueued_revertsWithoutPartialState() public {
        _setNextId(type(uint64).max);
        _expectQueueRejected(
            abi.encodeWithSignature("Panic(uint256)", uint256(0x11)),
            address(this)
        );
    }

    // Scenarios: BLINCT-BURN-N04.
    function test_givenLastAvailableId_whenQueued_thenMaximumCounter() public {
        _setNextId(type(uint64).max - 1);
        uint64 id = _timelock.queueBurnSurplus();
        assertEq(id, type(uint64).max - 1, "Final representable action ID");
        _assertQueued(id, IBurnerLoansInventory.burnSurplus.selector, address(this));
    }

    // Scenarios: BLINCT-BURN-N02.
    function test_givenMaximumExpiry_whenQueued_thenNoTruncation() public {
        vm.warp(uint256(type(uint48).max) - 4 days);
        uint64 id = _timelock.queueBurnSurplus();
        _assertQueued(id, IBurnerLoansInventory.burnSurplus.selector, address(this));
        assertEq(
            _timelock.getQueuedAction(id).expiresAt,
            type(uint48).max,
            "Maximum inclusive expiry"
        );
    }

    // Scenarios: BLINCT-BURN-N03.
    function test_givenExpiryAdditionOverflows_whenQueued_revertsWithoutPartialState() public {
        vm.warp(uint256(type(uint48).max) - 4 days + 1);
        _expectQueueRejected(
            abi.encodeWithSignature("Panic(uint256)", uint256(0x11)),
            address(this)
        );
    }

    function _expectQueueRejected(bytes memory reason_, address caller_) internal {
        _expectRejectedRecoveryQueue(_timelock.queueBurnSurplus, reason_, caller_);
    }

    // Scenarios: BLINCT-BURN-I01.
    function test_whenSubActionIndexOutOfBounds_reverts(
        uint256 index_,
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        index_ = bound(index_, 1, type(uint256).max);
        uint64 id = _timelock.queueBurnSurplus();
        _setState(_timelock, active_, enabled_);
        _expectSubActionIndexRejected(id, index_, caller_);
    }

    // Scenarios: BLINCT-BURN-I01.
    function test_whenSubActionIndexAtBounds_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                test_whenSubActionIndexOutOfBounds_reverts(
                    1,
                    address(0),
                    active != 0,
                    enabled != 0
                );
                _restore(checkpoint);
                test_whenSubActionIndexOutOfBounds_reverts(
                    type(uint256).max,
                    address(0),
                    active != 0,
                    enabled != 0
                );
                _restore(checkpoint);
            }
        }
    }

    // Scenarios: BLINCT-BURN-I02.
    function test_whenConfigStateIndexOutOfBounds_reverts(
        uint256 index_,
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        index_ = bound(index_, 1, type(uint256).max);
        uint64 id = _timelock.queueBurnSurplus();
        _setState(_timelock, active_, enabled_);
        _expectConfigStateIndexRejected(id, index_, caller_);
    }

    // Scenarios: BLINCT-BURN-I02.
    function test_whenConfigStateIndexAtBounds_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                test_whenConfigStateIndexOutOfBounds_reverts(
                    1,
                    address(0),
                    active != 0,
                    enabled != 0
                );
                _restore(checkpoint);
                test_whenConfigStateIndexOutOfBounds_reverts(
                    type(uint256).max,
                    address(0),
                    active != 0,
                    enabled != 0
                );
                _restore(checkpoint);
            }
        }
    }

    // Scenarios: BLINCT-BURN-I03.
    function test_whenSubActionStateIndexOutOfBounds_reverts(
        uint256 index_,
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        index_ = bound(index_, 1, type(uint256).max);
        uint64 id = _timelock.queueBurnSurplus();
        _setState(_timelock, active_, enabled_);
        _expectSubActionStateIndexRejected(id, index_, caller_);
    }

    // Scenarios: BLINCT-BURN-I03.
    function test_whenSubActionStateIndexAtBounds_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                test_whenSubActionStateIndexOutOfBounds_reverts(
                    1,
                    address(0),
                    active != 0,
                    enabled != 0
                );
                _restore(checkpoint);
                test_whenSubActionStateIndexOutOfBounds_reverts(
                    type(uint256).max,
                    address(0),
                    active != 0,
                    enabled != 0
                );
                _restore(checkpoint);
            }
        }
    }

    // Scenarios: BLINCT-BURN-L09.
    function test_givenPolicyInactive_givenBrokenRoles_whenQueueRequested_reverts(
        address caller_,
        bool enabled_
    ) public {
        _setState(_timelock, false, enabled_);
        vm.etch(address(_timelock.ROLES()), hex"fe");
        uint64 next = _timelock.nextActionId();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
        vm.prank(caller_);
        _timelock.queueBurnSurplus();
        assertEq(_timelock.nextActionId(), next, "Rejected local admission consumes no ID");
        assertEq(
            _timelock.getQueuedConfigStateCount(next, 0),
            0,
            "Rejected admission stores no payload"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected local admission commits no logs");
    }

    // Scenarios: BLINCT-BURN-L10.
    function test_givenActiveDisabled_givenBrokenRoles_whenQueueRequested_reverts(
        address caller_
    ) public {
        _setState(_timelock, true, false);
        vm.etch(address(_timelock.ROLES()), hex"fe");
        uint64 next = _timelock.nextActionId();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _timelock.queueBurnSurplus();
        assertEq(_timelock.nextActionId(), next, "Disabled admission consumes no ID");
        assertEq(
            _timelock.getQueuedConfigStateCount(next, 0),
            0,
            "Disabled admission stores no payload"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Disabled admission commits no logs");
    }

    // Scenarios: BLINCT-BURN-A05.
    function test_givenUnauthorizedCaller_givenBrokenTarget_whenQueueRequested_reverts(
        address caller_
    ) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        _setState(_inventory, false, true);
        uint64 next = _timelock.nextActionId();
        vm.recordLogs();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _timelock.queueBurnSurplus();
        assertEq(_timelock.nextActionId(), next, "Unauthorized admission consumes no ID");
        assertEq(
            _timelock.getQueuedConfigStateCount(next, 0),
            0,
            "Unauthorized admission stores no payload"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Unauthorized admission commits no logs");
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unused-return)
