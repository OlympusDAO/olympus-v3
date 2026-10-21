// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {RevenueDistributorConfigTimelockTest} from "src/test/policies/RevenueDistributorConfigTimelock/RevenueDistributorConfigTimelockTest.sol";

// These finite action/lifecycle combinations use token base units, not production gas loops.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
contract RevenueDistributorConfigTimelockCancelQueuedActionTest is
    RevenueDistributorConfigTimelockTest
{
    // Scenarios: CAN-A01
    function testFuzz_whenNonEmergencyCancels_reverts(
        address caller_,
        bool rotateOperator_
    ) public {
        vm.assume(caller_ != emergency);
        _permittedProposer(true);
        uint64 actionId = _queueRoute(address(token));
        bytes32 key = _queuedKey(actionId, 0);
        if (rotateOperator_) {
            vm.prank(admin);
            distributor.setConfigOperator(bob);
        }

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));
        vm.prank(caller_);
        configTimelock.cancelQueuedAction(actionId);

        assertFalse(configTimelock.getQueuedAction(actionId).cancelled, "action remains live");
        assertEq(configTimelock.pendingActionId(key), actionId, "key remains owned");
    }

    // Scenarios: CAN-A01
    function test_whenKnownNonEmergencyRolesCancel_reverts() public {
        address proposer = _permittedProposer(true);
        address[] memory callers = new address[](4);
        callers[0] = admin;
        callers[1] = proposer;
        callers[2] = address(configTimelock);
        callers[3] = address(distributor);

        for (uint256 i; i < callers.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            uint64 actionId = _queueRoute(address(token));
            bytes32 key = _queuedKey(actionId, 0);

            vm.expectRevert(
                abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE)
            );
            vm.prank(callers[i]);
            configTimelock.cancelQueuedAction(actionId);

            assertFalse(configTimelock.getQueuedAction(actionId).cancelled, "action remains live");
            assertEq(configTimelock.pendingActionId(key), actionId, "key remains owned");
            assertTrue(vm.revertToState(snapshot), "restore known caller case");
        }
    }

    // Scenarios: CAN-I01
    function testFuzz_whenActionDoesNotExist_revertsBeforeLifecycle(
        address caller_,
        uint64 actionId_
    ) public {
        vm.prank(emergency);
        configTimelock.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                actionId_
            )
        );
        vm.prank(caller_);
        configTimelock.cancelQueuedAction(actionId_);
    }

    // Scenarios: CAN-I02
    function testFuzz_whenActionAlreadyExecuted_revertsBeforeAuthority(address caller_) public {
        uint64 actionId = _queueRoute(address(token));
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);
        configTimelock.executeQueuedAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        vm.prank(caller_);
        configTimelock.cancelQueuedAction(actionId);
    }

    // Scenarios: CAN-I03
    function testFuzz_whenActionAlreadyCancelled_revertsBeforeAuthority(address caller_) public {
        uint64 actionId = _queueRoute(address(token));
        vm.prank(emergency);
        configTimelock.cancelQueuedAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        vm.prank(caller_);
        configTimelock.cancelQueuedAction(actionId);
    }

    // Scenarios: CAN-P01
    function test_whenCancelled_releasesKeyForReplacement() public {
        uint64 actionId = _queueRoute(address(token));
        bytes32 key = _queuedKey(actionId, 0);
        vm.prank(emergency);
        configTimelock.cancelQueuedAction(actionId);

        uint64 replacementId = _queueRoute(address(token));

        assertEq(replacementId, actionId + 1, "replacement consumes next ID");
        assertEq(configTimelock.pendingActionId(key), replacementId, "replacement acquires key");
    }

    // Scenarios: CAN-V01
    function testFuzz_whenCancelledOrUnknownActionRead_returnsTerminalStateAndDefaults(
        address caller_,
        bool maximumUnknownId_
    ) public {
        uint64 actionId = _queueRoute(address(token));
        bytes32 key = _queuedKey(actionId, 0);
        vm.prank(emergency);
        configTimelock.cancelQueuedAction(actionId);
        uint64 unknownId = maximumUnknownId_ ? type(uint64).max : 0;

        vm.startPrank(caller_);
        ITimelockBatchQueue.QueuedAction memory cancelled = configTimelock.getQueuedAction(
            actionId
        );
        assertTrue(cancelled.cancelled, "getter reports cancelled terminal state");
        assertFalse(cancelled.executed, "cancelled action is not executed");
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        configTimelock.getQueuedActionLength(actionId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                unknownId
            )
        );
        configTimelock.getQueuedAction(unknownId);
        assertEq(
            configTimelock.getQueuedConfigStateCount(unknownId, 0),
            0,
            "unknown action has no guard state"
        );
        assertEq(
            configTimelock.getQueuedConfigDestination(unknownId, 0),
            address(0),
            "unknown action has no guard destination"
        );
        assertEq(configTimelock.pendingActionId(key), 0, "cancelled action released key");
        vm.stopPrank();
    }

    /// @notice Both rescue selectors retain their payload, key and funds when RDT cannot cancel.
    // Scenarios: CAN-L01, CAN-L02.
    function test_givenTimelockUnavailable_whenEmergencyCancelsRescue_reverts() public {
        for (uint256 pending; pending < 2; ++pending) {
            for (uint256 disabled; disabled < 2; ++disabled) {
                for (uint256 inactive; inactive < 2; ++inactive) {
                    if (disabled == 0 && inactive == 0) continue;
                    uint256 snapshot = vm.snapshotState();
                    uint64 id = _queueRescue(pending != 0);
                    bytes32 actionBefore = keccak256(
                        abi.encode(configTimelock.getQueuedAction(id))
                    );
                    (bytes32 key, bytes32 guardHash) = configTimelock.getQueuedConfigState(
                        id,
                        0,
                        0
                    );
                    vm.startPrank(admin);
                    if (disabled != 0) configTimelock.disable("");
                    if (inactive != 0) {
                        kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
                    }
                    vm.stopPrank();
                    bytes memory failure = disabled != 0
                        ? abi.encodeWithSelector(IEnabler.NotEnabled.selector)
                        : abi.encodeWithSelector(
                            IRevenueDistributorConfigTimelock
                                .RevenueDistributorConfigTimelock_PolicyInactive
                                .selector,
                            address(configTimelock)
                        );
                    vm.expectRevert(failure);
                    vm.prank(emergency);
                    configTimelock.cancelQueuedAction(id);
                    assertEq(
                        keccak256(abi.encode(configTimelock.getQueuedAction(id))),
                        actionBefore,
                        "blocked cancellation preserves action"
                    );
                    assertEq(
                        configTimelock.pendingActionId(key),
                        id,
                        "blocked cancellation retains key"
                    );
                    (, bytes32 hashAfter) = configTimelock.getQueuedConfigState(id, 0, 0);
                    assertEq(hashAfter, guardHash, "blocked cancellation retains guard");
                    assertEq(
                        token.balanceOf(address(distributor)),
                        10,
                        "blocked cancellation moves no custody"
                    );
                    assertEq(token.balanceOf(bob), 0, "blocked cancellation pays no destination");
                    if (pending != 0) _assertPendingPayouts(address(token), alice, 10, 0, 0);
                    assertTrue(vm.revertToState(snapshot), "restore cancellation lifecycle");
                }
            }
        }
    }

    /// @notice Enabled, active RDT still lets Emergency cancel either rescue before/at readiness or after expiry.
    // Scenarios: CAN-P01.
    function test_givenTimelockEnabledAndActive_whenEmergencyCancelsRescue() public {
        for (uint256 pending; pending < 2; ++pending) {
            for (uint256 timing; timing < 3; ++timing) {
                uint256 snapshot = vm.snapshotState();
                uint64 id = _queueRescue(pending != 0);
                ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(id);
                (bytes32 key, ) = configTimelock.getQueuedConfigState(id, 0, 0);
                vm.warp(
                    timing == 0 ? action.queuedAt : timing == 1
                        ? action.executableAt
                        : uint256(action.expiresAt) + 1
                );
                vm.expectEmit(true, true, false, true, address(configTimelock));
                emit ITimelockBatchQueue.TimelockActionCancelled(id, emergency);
                vm.prank(emergency);
                configTimelock.cancelQueuedAction(id);
                assertTrue(configTimelock.getQueuedAction(id).cancelled, "action marked cancelled");
                assertEq(
                    configTimelock.getQueuedAction(id).actions.length,
                    0,
                    "cancelled sub-actions cleared"
                );
                assertEq(configTimelock.pendingActionId(key), 0, "cancelled key released");
                assertEq(
                    configTimelock.getQueuedConfigStateCount(id, 0),
                    0,
                    "cancelled guard cleared"
                );
                assertEq(
                    token.balanceOf(address(distributor)),
                    10,
                    "cancellation preserves custody"
                );
                if (pending != 0) _assertPendingPayouts(address(token), alice, 10, 0, 0);
                assertTrue(vm.revertToState(snapshot), "restore successful cancellation");
            }
        }
    }

    // Scenarios: CAN-P01.
    function testFuzz_whenEmergencyCancelsBatch_releasesEveryKey(
        bool useRevenueAdmin_,
        bool rotateOperator_,
        uint8 timing_
    ) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        address secondAsset = address(new MockERC20("Second", "SECOND", 18));
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _routeBatchAction(address(token), alice);
        actions[1] = _routeBatchAction(secondAsset, bob);

        vm.prank(proposer);
        uint64 actionId = configTimelock.queueBatch(actions);
        bytes32 firstKey = _queuedKey(actionId, 0);
        bytes32 secondKey = _queuedKey(actionId, 1);
        ITimelockBatchQueue.QueuedAction memory queued = configTimelock.getQueuedAction(actionId);
        timing_ = uint8(bound(timing_, 0, 2));
        vm.warp(
            timing_ == 0 ? queued.queuedAt : timing_ == 1
                ? queued.executableAt
                : uint256(queued.expiresAt) + 1
        );
        if (rotateOperator_) {
            vm.prank(admin);
            distributor.setConfigOperator(bob);
        }

        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit ITimelockBatchQueue.TimelockActionCancelled(actionId, emergency);
        vm.prank(emergency);
        configTimelock.cancelQueuedAction(actionId);

        assertTrue(configTimelock.getQueuedAction(actionId).cancelled, "batch marked cancelled");
        assertEq(
            configTimelock.getQueuedAction(actionId).actions.length,
            0,
            "cancelled batch cleared"
        );
        assertEq(configTimelock.pendingActionId(firstKey), 0, "first key released");
        assertEq(configTimelock.pendingActionId(secondKey), 0, "second key released");
        assertEq(configTimelock.getQueuedConfigStateCount(actionId, 0), 0, "first guard cleared");
        assertEq(configTimelock.getQueuedConfigStateCount(actionId, 1), 0, "second guard cleared");
        assertEq(
            uint8(distributor.assetState(address(token))),
            0,
            "first route remains unconfigured"
        );
        assertEq(
            uint8(distributor.assetState(secondAsset)),
            0,
            "second route remains unconfigured"
        );
    }

    /// @dev Construct one valid rescue; cancellation does not depend on debt allocation.
    function _queueRescue(bool pending_) internal returns (uint64 id) {
        token.mint(address(distributor), 10);
        vm.startPrank(admin);
        if (pending_) {
            IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
                1
            );
            routes[0] = IRevenueDistributor.AssetRoute(alice, 10_000);
            distributor.setAssetRoutes(address(token), 0, routes);
            distributor.seedPendingForTest(address(token), alice, 10, 0, 0);
            id = configTimelock.queueRescuePendingPayout(address(token), alice, bob, 4);
        } else {
            id = configTimelock.queueRescue(address(token), bob);
        }
        vm.stopPrank();
    }

    function _routeBatchAction(
        address asset_,
        address recipient_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory action) {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute(recipient_, 10_000);
        action = ITimelockBatchQueue.BatchAction({
            target: address(distributor),
            selector: IRevenueDistributor.setAssetRoutes.selector,
            payload: abi.encode(asset_, 0, routes)
        });
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
