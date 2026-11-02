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

contract BurnerLoansInventoryConfigTimelockQueueRescueSurplusTest is
    BurnerLoansInventoryConfigTimelockTest
{
    // Scenarios: BLINCT-RESCUE-L01.
    function test_givenDisabledInventory_whenRescueExecutes_thenProviderIdleIsProtected() public {
        _supplyInventory(_borrower, 50e9);
        _ohm.mint(address(_inventory), 1e9);
        _inventory.disable("");
        vm.prank(_recipient);
        uint64 id = _timelock.queueRescueSurplus();
        // A further 2 OHM arrives during notice: 1 + 2 = 3 OHM live surplus, not a pinned quote.
        _ohm.mint(address(_inventory), 2e9);
        address treasury = _treasury();
        uint256 beforeBalance = _ohm.balanceOf(treasury);
        _makeReady(id);
        _timelock.executeQueuedAction(id);
        assertEq(_ohm.balanceOf(treasury), beforeBalance + 3e9, "Rescue uses live surplus");
        assertEq(_ohm.balanceOf(address(_inventory)), 50e9, "Provider idle protected");
        assertEq(_inventory.suppliedOhm(), 50e9, "Provider claims preserved");
        assertFalse(_inventory.isEnabled(), "Rescue leaves Inventory disabled");
    }

    // Scenarios: BLINCT-RESCUE-A02, BLINCT-RESCUE-P07.
    function test_givenPermittedProposer_whenQueued_thenExactMetadataAndEvents(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public givenProviderSurplus {
        _grantRecoveryAdmin(caller_, blAdmin_, overlap_);
        _assertRecoveryQueued(
            _timelock.queueRescueSurplus,
            IBurnerLoansInventory.rescueSurplus.selector,
            caller_
        );
    }

    // Scenarios: BLINCT-RESCUE-A02.
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

    // Scenarios: BLINCT-RESCUE-A01.
    function test_whenUnauthorizedProposer_reverts(address caller_) public givenProviderSurplus {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        _expectQueueRejected(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector), caller_);
    }

    // Scenarios: BLINCT-RESCUE-A03.
    function test_givenAnotherController_whenQueued_reverts() public {
        _inventory.setConfigOperator(_inventoryConfigurator);
        _expectQueueRejected(
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            address(this)
        );
    }

    // Scenarios: BLINCT-RESCUE-A04.
    function test_givenClearedController_whenQueued_reverts() public {
        _inventory.setConfigOperator(address(0));
        _expectQueueRejected(
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            address(this)
        );
    }

    // Scenarios: BLINCT-RESCUE-L03.
    function test_givenActiveDisabledTimelock_whenQueued_reverts() public {
        _setState(_timelock, true, false);
        _expectQueueRejected(abi.encodeWithSelector(IEnabler.NotEnabled.selector), address(this));
    }

    // Scenarios: BLINCT-RESCUE-L04.
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

    // Scenarios: BLINCT-RESCUE-L05.
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

    // Scenarios: BLINCT-RESCUE-L02, BLINCT-RESCUE-L07.
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

    // Scenarios: BLINCT-RESCUE-D01.
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

    // Scenarios: BLINCT-RESCUE-L08.
    function test_givenReEnabled_whenQueued_thenOneAction() public {
        _timelock.disable("");
        _timelock.reEnable();
        uint64 id = _timelock.queueRescueSurplus();
        _assertQueued(id, IBurnerLoansInventory.rescueSurplus.selector, address(this));
    }

    // Scenarios: BLINCT-RESCUE-P03.
    function test_givenSameActionPending_whenQueued_reverts() public {
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

    // Scenarios: BLINCT-BURN-P01, BLINCT-RESCUE-P01.
    function test_givenBurnPending_whenRescueQueued_reverts() public {
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

    // Scenarios: BLINCT-RESCUE-P04.
    function test_givenAnyCoreLifecycle_whenQueued_thenIndependent(
        bool active_,
        bool enabled_
    ) public {
        _setState(_core, active_, enabled_);
        uint64 id = _timelock.queueRescueSurplus();
        _assertQueued(id, IBurnerLoansInventory.rescueSurplus.selector, address(this));
    }

    // Scenarios: BLINCT-RESCUE-P04.
    function test_givenEachCoreLifecyclePair_whenQueued_thenIndependent() public {
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                uint256 checkpoint = vm.snapshotState();
                test_givenAnyCoreLifecycle_whenQueued_thenIndependent(active != 0, enabled != 0);
                assertTrue(vm.revertToState(checkpoint), "Restore Core and queue for next state");
            }
        }
    }

    // Scenarios: BLINCT-RESCUE-P05.
    function test_givenNoSurplus_whenExecuted_thenNoInventoryEventAndKeyReleased() public {
        uint64 id = _timelock.queueRescueSurplus();
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

    // Scenarios: BLINCT-RESCUE-P06.
    function test_givenSurplusArrivesDuringNotice_whenExecuted_thenLiveAmount()
        public
        givenProviderSurplus
    {
        uint64 id = _timelock.queueRescueSurplus();
        _ohm.mint(address(_inventory), 2e9);
        uint256 beforeSupply = _ohm.totalSupply();
        uint256 beforeTreasury = _ohm.balanceOf(_treasury());
        _makeReady(id);
        _timelock.executeQueuedAction(id);
        _assertBacking(50e9);
        _assertCleared(id);
        assertEq(
            _ohm.balanceOf(_treasury()),
            beforeTreasury + 3e9,
            "Transfer live surplus to Treasury"
        );
        assertEq(_ohm.totalSupply(), beforeSupply, "Rescue preserves token supply");
    }

    // Scenarios: BLINCT-RESCUE-N01.
    function test_givenExhaustedCounter_whenQueued_revertsWithoutPartialState() public {
        _setNextId(type(uint64).max);
        _expectQueueRejected(
            abi.encodeWithSignature("Panic(uint256)", uint256(0x11)),
            address(this)
        );
    }

    // Scenarios: BLINCT-RESCUE-N04.
    function test_givenLastAvailableId_whenQueued_thenMaximumCounter() public {
        _setNextId(type(uint64).max - 1);
        uint64 id = _timelock.queueRescueSurplus();
        assertEq(id, type(uint64).max - 1, "Final representable action ID");
        _assertQueued(id, IBurnerLoansInventory.rescueSurplus.selector, address(this));
    }

    // Scenarios: BLINCT-RESCUE-N02.
    function test_givenMaximumExpiry_whenQueued_thenNoTruncation() public {
        vm.warp(uint256(type(uint48).max) - 4 days);
        uint64 id = _timelock.queueRescueSurplus();
        _assertQueued(id, IBurnerLoansInventory.rescueSurplus.selector, address(this));
        assertEq(
            _timelock.getQueuedAction(id).expiresAt,
            type(uint48).max,
            "Maximum inclusive expiry"
        );
    }

    // Scenarios: BLINCT-RESCUE-N03.
    function test_givenExpiryAdditionOverflows_whenQueued_revertsWithoutPartialState() public {
        vm.warp(uint256(type(uint48).max) - 4 days + 1);
        _expectQueueRejected(
            abi.encodeWithSignature("Panic(uint256)", uint256(0x11)),
            address(this)
        );
    }

    function _expectQueueRejected(bytes memory reason_, address caller_) internal {
        _expectRejectedRecoveryQueue(_timelock.queueRescueSurplus, reason_, caller_);
    }

    // Scenarios: BLINCT-RESCUE-I01.
    function test_whenSubActionIndexOutOfBounds_reverts(
        uint256 index_,
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        index_ = bound(index_, 1, type(uint256).max);
        uint64 id = _timelock.queueRescueSurplus();
        _setState(_timelock, active_, enabled_);
        _expectSubActionIndexRejected(id, index_, caller_);
    }

    // Scenarios: BLINCT-RESCUE-I01.
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

    // Scenarios: BLINCT-RESCUE-I02.
    function test_whenConfigStateIndexOutOfBounds_reverts(
        uint256 index_,
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        index_ = bound(index_, 1, type(uint256).max);
        uint64 id = _timelock.queueRescueSurplus();
        _setState(_timelock, active_, enabled_);
        _expectConfigStateIndexRejected(id, index_, caller_);
    }

    // Scenarios: BLINCT-RESCUE-I02.
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

    // Scenarios: BLINCT-RESCUE-I03.
    function test_whenSubActionStateIndexOutOfBounds_reverts(
        uint256 index_,
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        index_ = bound(index_, 1, type(uint256).max);
        uint64 id = _timelock.queueRescueSurplus();
        _setState(_timelock, active_, enabled_);
        _expectSubActionStateIndexRejected(id, index_, caller_);
    }

    // Scenarios: BLINCT-RESCUE-I03.
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
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unused-return)
