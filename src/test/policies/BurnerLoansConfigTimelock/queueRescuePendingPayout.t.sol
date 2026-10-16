// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20Errors} from "@openzeppelin-5.7.0/interfaces/draft-IERC6093.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {IBurnerLoansRescue} from "src/policies/interfaces/IBurnerLoansRescue.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {BurnerLoansRescueQueueTest} from "src/test/policies/BurnerLoansConfigTimelock/fixtures/BurnerLoansRescueQueueTest.sol";

// These finite scenario loops exercise calls, not production gas behavior.
// forge-lint: disable-start(literal-instead-of-constant,unused-return,calls-loop)
/// @dev The queue owns validation/storage and rescue-specific changes, not BL bucket allocation.
contract BurnerLoansConfigTimelockQueueRescuePendingPayoutTest is BurnerLoansRescueQueueTest {
    uint256 internal constant _AMOUNT = 4;
    enum Gate {
        TimelockDisabled,
        TimelockInactive,
        ConfigDisabled,
        ConfigInactive,
        OperatorChanged,
        FacilityInactive
    }

    /// @notice Both queue roles store one exact action without paying, even when BL is disabled.
    // Scenarios: BLCT-L01, BLCT-Q01.
    function test_givenValidRequest_whenEachRoleQueues() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 disabled; disabled < 2; ++disabled) {
            for (uint256 c; c < callers.length; ++c) {
                uint256 snapshot = vm.snapshotState();
                if (disabled != 0) {
                    vm.prank(admin);
                    burnerLoans.disable("");
                }
                _assertQueued(
                    callers[c],
                    address(_rescueAsset),
                    _rescueKeeper,
                    _rescueDestination,
                    _AMOUNT
                );
                assertTrue(vm.revertToState(snapshot), "restore queue fixture");
            }
        }
    }

    /// @notice Disabling BLC after queueing blocks execution and preserves the pending action.
    // Scenarios: BLCT-E11.
    function test_givenQueuedRequest_whenConfigDisabled_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
            for (uint256 c; c < callers.length; ++c) {
                uint256 snapshot = vm.snapshotState();
                if (disabledBL != 0) {
                    vm.prank(admin);
                    burnerLoans.disable("");
                }
                uint64 id = _assertQueued(
                    callers[c],
                    address(_rescueAsset),
                    _rescueKeeper,
                    _rescueDestination,
                    _AMOUNT
                );
                vm.prank(admin);
                burnerLoansConfig.disable("");
                bytes memory failure = abi.encodeWithSelector(IEnabler.NotEnabled.selector);
                vm.warp(configTimelock.getQueuedAction(id).executableAt);
                _assertExecutionFailure(id, failure);
                assertTrue(vm.revertToState(snapshot), "restore disabled Config rejection");
            }
        }
    }

    /// @notice A disabled Config blocks rescue-only batches too.
    /// @dev Both orders and proposer roles reject without committing a key, action or payment.
    // Scenarios: BLCT-B03.
    function test_givenConfigAndFacilityDisabled_whenOnlyRescuesAreBatched_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 pendingIndex; pendingIndex < 2; ++pendingIndex) {
            for (uint256 c; c < callers.length; ++c) {
                uint256 snapshot = vm.snapshotState();
                vm.startPrank(admin);
                burnerLoansConfig.disable("");
                burnerLoans.disable("");
                vm.stopPrank();
                ITimelockBatchQueue.BatchAction[]
                    memory actions = new ITimelockBatchQueue.BatchAction[](2);
                actions[pendingIndex] = ITimelockBatchQueue.BatchAction({
                    target: address(burnerLoansConfig),
                    selector: IBurnerLoansConfig.rescuePendingPayout.selector,
                    payload: abi.encode(
                        address(_rescueAsset),
                        _rescueKeeper,
                        _rescueDestination,
                        _AMOUNT
                    )
                });
                actions[1 - pendingIndex] = ITimelockBatchQueue.BatchAction({
                    target: address(burnerLoansConfig),
                    selector: IBurnerLoansConfig.rescue.selector,
                    payload: abi.encode(address(_rescueAsset), _rescueDestination)
                });
                bytes32 beforeState = _queueState();
                vm.expectRevert(IEnabler.NotEnabled.selector);
                vm.prank(callers[c]);
                configTimelock.queueBatch(actions);
                assertEq(_queueState(), beforeState, "rejected rescue-only batch changes no state");
                assertEq(
                    configTimelock.getQueuedConfigStateCount(1, 0),
                    0,
                    "rejected batch stores no first guard"
                );
                assertEq(
                    configTimelock.getQueuedConfigStateCount(1, 1),
                    0,
                    "rejected batch stores no second guard"
                );
                assertTrue(vm.revertToState(snapshot), "restore disabled rescue-only batch");
            }
        }
    }

    /// @notice A disabled Config rejects queueing pending rescue plus a setter in either order.
    // Scenarios: BLCT-B01.
    function test_givenConfigDisabled_whenPendingRescueAndConfigurationAreQueued_reverts() public {
        for (uint256 rescueIndex; rescueIndex < 2; ++rescueIndex) {
            uint256 snapshot = vm.snapshotState();
            ITimelockBatchQueue.BatchAction[]
                memory actions = _pendingRescueAndConfigurationActions(rescueIndex);
            vm.prank(admin);
            burnerLoansConfig.disable("");
            bytes32 beforeState = _queueState();
            address[2] memory callers = [admin, burnerLoansAdmin];
            for (uint256 c; c < callers.length; ++c) {
                vm.expectRevert(IEnabler.NotEnabled.selector);
                vm.prank(callers[c]);
                configTimelock.queueBatch(actions);
                assertEq(_queueState(), beforeState, "mixed queue failure rolls back state");
                assertEq(
                    configTimelock.getQueuedConfigStateCount(1, rescueIndex),
                    0,
                    "failed rescue guard not retained"
                );
            }
            assertTrue(vm.revertToState(snapshot), "restore independent batch order");
        }
    }

    // Scenarios: BLCT-B02.
    function test_givenConfigDisabled_whenPendingRescueAndConfigurationAreExecuted_reverts()
        public
    {
        for (uint256 rescueIndex; rescueIndex < 2; ++rescueIndex) {
            uint256 snapshot = vm.snapshotState();
            ITimelockBatchQueue.BatchAction[]
                memory actions = _pendingRescueAndConfigurationActions(rescueIndex);
            vm.prank(admin);
            uint64 id = configTimelock.queueBatch(actions);
            vm.prank(admin);
            burnerLoansConfig.disable("");
            vm.warp(configTimelock.getQueuedAction(id).executableAt);
            _assertExecutionFailure(id, abi.encodeWithSelector(IEnabler.NotEnabled.selector));
            for (uint256 i; i < actions.length; ++i) {
                (bytes32 key, ) = configTimelock.getQueuedConfigState(id, i, 0);
                assertEq(
                    configTimelock.pendingActionId(key),
                    id,
                    "both mixed batch keys remain owned"
                );
            }
            assertTrue(vm.revertToState(snapshot), "restore independent batch order");
        }
    }

    // Scenarios: BLCT-B01.
    function test_givenConfigDisabled_whenSurplusRescueAndConfigurationAreQueued_reverts() public {
        for (uint256 rescueIndex; rescueIndex < 2; ++rescueIndex) {
            uint256 snapshot = vm.snapshotState();
            ITimelockBatchQueue.BatchAction[]
                memory actions = _surplusRescueAndConfigurationActions(rescueIndex);
            vm.prank(admin);
            burnerLoansConfig.disable("");
            bytes32 beforeState = _queueState();
            address[2] memory callers = [admin, burnerLoansAdmin];
            for (uint256 c; c < callers.length; ++c) {
                vm.expectRevert(IEnabler.NotEnabled.selector);
                vm.prank(callers[c]);
                configTimelock.queueBatch(actions);
                assertEq(_queueState(), beforeState, "mixed queue failure rolls back state");
                assertEq(
                    configTimelock.getQueuedConfigStateCount(1, rescueIndex),
                    0,
                    "failed rescue guard not retained"
                );
            }
            assertTrue(vm.revertToState(snapshot), "restore independent batch order");
        }
    }

    // Scenarios: BLCT-B02.
    function test_givenConfigDisabled_whenSurplusRescueAndConfigurationAreExecuted_reverts()
        public
    {
        for (uint256 rescueIndex; rescueIndex < 2; ++rescueIndex) {
            uint256 snapshot = vm.snapshotState();
            ITimelockBatchQueue.BatchAction[]
                memory actions = _surplusRescueAndConfigurationActions(rescueIndex);
            vm.prank(admin);
            uint64 id = configTimelock.queueBatch(actions);
            vm.prank(admin);
            burnerLoansConfig.disable("");
            vm.warp(configTimelock.getQueuedAction(id).executableAt);
            _assertExecutionFailure(id, abi.encodeWithSelector(IEnabler.NotEnabled.selector));
            for (uint256 i; i < actions.length; ++i) {
                (bytes32 key, ) = configTimelock.getQueuedConfigState(id, i, 0);
                assertEq(
                    configTimelock.pendingActionId(key),
                    id,
                    "both mixed batch keys remain owned"
                );
            }
            assertTrue(vm.revertToState(snapshot), "restore independent batch order");
        }
    }

    /// @dev Construct the explicit pending rescue plus setter; the test chooses only their order.
    function _pendingRescueAndConfigurationActions(
        uint256 rescueIndex_
    ) internal view returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[rescueIndex_] = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.rescuePendingPayout.selector,
            payload: abi.encode(address(_rescueAsset), _rescueKeeper, _rescueDestination, _AMOUNT)
        });
        actions[1 - rescueIndex_] = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.setPriceCacheMaxAge.selector,
            payload: abi.encode(uint48(1))
        });
    }

    /// @dev Construct the explicit surplus rescue plus setter; the test chooses only their order.
    function _surplusRescueAndConfigurationActions(
        uint256 rescueIndex_
    ) internal view returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[rescueIndex_] = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.rescue.selector,
            payload: abi.encode(address(_rescueAsset), _rescueDestination)
        });
        actions[1 - rescueIndex_] = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.setPriceCacheMaxAge.selector,
            payload: abi.encode(uint48(1))
        });
    }

    /// @notice A paused timelock cannot execute a mature pending rescue; the queued action remains intact.
    // Scenarios: BLCT-E12.
    function test_givenQueuedRequest_givenTimelockDisabled_whenExecuted_reverts() public {
        uint64 id = _assertQueued(
            admin,
            address(_rescueAsset),
            _rescueKeeper,
            _rescueDestination,
            _AMOUNT
        );
        bytes memory failure = _failGate(Gate.TimelockDisabled);
        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(id, failure);
    }

    /// @notice One valid and one invalid request expose each independent queue gate's precedence.
    // Scenarios: BLCT-L03.
    function test_givenTimelockDisabled_whenPendingRescueQueued_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];

        for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
            uint256 snapshot = vm.snapshotState();
            if (disabledBL != 0) {
                vm.prank(admin);
                burnerLoans.disable("");
            }
            vm.startPrank(admin);
            configTimelock.disable("");
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(IEnabler.NotEnabled.selector);

            for (uint256 c; c < callers.length; ++c) {
                _assertQueueFailure(callers[c], _AMOUNT, failure);
                _assertQueueFailure(callers[c], 0, failure);
            }
            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    // Scenarios: BLCT-L08.
    function test_givenTimelockInactive_whenPendingRescueQueued_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];

        for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
            uint256 snapshot = vm.snapshotState();
            if (disabledBL != 0) {
                vm.prank(admin);
                burnerLoans.disable("");
            }
            vm.startPrank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_PolicyInactive.selector,
                address(configTimelock)
            );

            for (uint256 c; c < callers.length; ++c) {
                _assertQueueFailure(callers[c], _AMOUNT, failure);
                _assertQueueFailure(callers[c], 0, failure);
            }
            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    // Scenarios: BLCT-L10.
    function test_givenConfigDisabled_whenPendingRescueQueued_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];

        for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
            uint256 snapshot = vm.snapshotState();
            if (disabledBL != 0) {
                vm.prank(admin);
                burnerLoans.disable("");
            }
            vm.startPrank(admin);
            burnerLoansConfig.disable("");
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(IEnabler.NotEnabled.selector);

            for (uint256 c; c < callers.length; ++c) {
                _assertQueueFailure(callers[c], _AMOUNT, failure);
                _assertQueueFailure(callers[c], 0, failure);
            }
            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    // Scenarios: BLCT-L09.
    function test_givenConfigInactive_whenPendingRescueQueued_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];

        for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
            uint256 snapshot = vm.snapshotState();
            if (disabledBL != 0) {
                vm.prank(admin);
                burnerLoans.disable("");
            }
            vm.startPrank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoansConfig));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_PolicyInactive.selector,
                address(burnerLoansConfig)
            );

            for (uint256 c; c < callers.length; ++c) {
                _assertQueueFailure(callers[c], _AMOUNT, failure);
                _assertQueueFailure(callers[c], 0, failure);
            }
            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    // Scenarios: BLCT-L04.
    function test_givenOperatorChanged_whenPendingRescueQueued_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];

        for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
            uint256 snapshot = vm.snapshotState();
            if (disabledBL != 0) {
                vm.prank(admin);
                burnerLoans.disable("");
            }
            vm.startPrank(admin);
            burnerLoansConfig.setConfigOperator(alice);
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                address(configTimelock)
            );

            for (uint256 c; c < callers.length; ++c) {
                _assertQueueFailure(callers[c], _AMOUNT, failure);
                _assertQueueFailure(callers[c], 0, failure);
            }
            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    // Scenarios: BLCT-L06.
    function test_givenFacilityInactive_whenPendingRescueQueued_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];

        for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
            uint256 snapshot = vm.snapshotState();
            if (disabledBL != 0) {
                vm.prank(admin);
                burnerLoans.disable("");
            }
            vm.startPrank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_PolicyInactive.selector
            );

            vm.expectRevert(failure);
            burnerLoans.previewRescuePendingPayout(
                address(_rescueAsset),
                _rescueKeeper,
                _rescueDestination,
                0
            );

            for (uint256 c; c < callers.length; ++c) {
                _assertQueueFailure(callers[c], _AMOUNT, failure);
                _assertQueueFailure(callers[c], 0, failure);
            }
            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    /// @notice Unauthorized callers cannot reach the preview with either valid or zero amount.
    // Scenarios: BLCT-L02.
    function test_whenQueueCallerIsUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != admin && caller_ != burnerLoansAdmin);
        _assertUnauthorized(caller_);
    }

    /// @notice Guarantee operator-only, emergency-only and payout-owner rejection identities.
    // Scenarios: BLCT-L02.
    function test_whenUnauthorizedIdentitiesAreSeeded_reverts() public {
        _assertUnauthorized(address(configTimelock));
        _assertUnauthorized(emergency);
        _assertUnauthorized(_rescueKeeper);
        _assertUnauthorized(address(0));
    }

    /// @notice Simultaneous faults prove local enablement, activity, role and operator order.
    // Scenarios: BLCT-L03, BLCT-L08, BLCT-L09, BLCT-L04.
    function test_whenQueueFaultsCompete_reverts() public {
        uint256 snapshot = vm.snapshotState();
        _failGate(Gate.ConfigInactive);
        _failGate(Gate.TimelockInactive);
        _failGate(Gate.TimelockDisabled);
        _assertQueueFailure(emergency, 0, abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        assertTrue(vm.revertToState(snapshot), "restore competing gates");
        snapshot = vm.snapshotState();
        _failGate(Gate.ConfigInactive);
        bytes memory failure = _failGate(Gate.TimelockInactive);
        _assertQueueFailure(emergency, 0, failure);
        assertTrue(vm.revertToState(snapshot), "restore activity precedence");
        snapshot = vm.snapshotState();
        failure = _failGate(Gate.OperatorChanged);
        vm.prank(admin);
        burnerLoansConfig.disable("");
        _assertQueueFailure(admin, 0, failure);
        _assertUnauthorized(emergency);
        assertTrue(vm.revertToState(snapshot), "restore operator precedence");
    }

    /// @notice BL's zero-amount error bubbles before a pending conflict key is considered.
    // Scenarios: BLCT-I01.
    function test_whenPreviewRejectsBeforeConflict_reverts() public {
        for (uint256 state; state < 2; ++state) {
            uint256 snapshot = vm.snapshotState();
            if (state != 0) {
                vm.prank(admin);
                burnerLoans.disable("");
            }

            address[2] memory callers = [admin, burnerLoansAdmin];
            bytes memory failure = abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_ZeroAmount.selector
            );
            for (uint256 c; c < callers.length; ++c) _assertQueueFailure(callers[c], 0, failure);
            _assertQueued(admin, address(_rescueAsset), _rescueKeeper, _rescueDestination, _AMOUNT);
            for (uint256 c; c < callers.length; ++c) _assertQueueFailure(callers[c], 0, failure);
            assertTrue(vm.revertToState(snapshot), "restore preview-before-conflict state");
        }
    }

    /// @notice Destination and valid amount changes still conflict with the same recipient key.
    // Scenarios: BLCT-Q02.
    function test_givenSameRecipientQueued_whenRequestChanges_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        uint64 actionId = _assertQueued(
            admin,
            address(_rescueAsset),
            _rescueKeeper,
            _rescueDestination,
            _AMOUNT
        );
        bytes memory failure = abi.encodeWithSelector(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
            _key(address(_rescueAsset), _rescueKeeper),
            actionId
        );
        for (uint256 c; c < callers.length; ++c) {
            _assertQueueFailure(callers[c], 6, failure);
            bytes32 beforeState = _queueState();
            vm.expectRevert(failure);
            vm.prank(callers[c]);
            configTimelock.queueRescuePendingPayout(
                address(_rescueAsset),
                _rescueKeeper,
                alice,
                _AMOUNT
            );
            assertEq(_queueState(), beforeState, "changed destination preserves prior queue");
        }
    }

    /// @notice Different recipients and different assets reserve independent keys for both roles.
    // Scenarios: BLCT-Q03.
    function test_givenIndependentRecipientsAndAssets_whenQueued() public {
        address secondKeeper = makeAddr("second keeper");
        _rescueAsset.mint(address(burnerLoans), 10);
        _rescueAsset.setTransferReverts(secondKeeper, true);
        burnerLoans.recordPendingSeizureRewardForTest(address(_rescueAsset), secondKeeper, 10);
        MockRevertingTransferToken secondAsset = _createPendingRescueAsset(_rescueKeeper);
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            uint64 first = _assertQueued(
                callers[c],
                address(_rescueAsset),
                _rescueKeeper,
                _rescueDestination,
                _AMOUNT
            );
            uint64 second = _assertQueued(
                callers[c],
                address(_rescueAsset),
                secondKeeper,
                _rescueDestination,
                _AMOUNT
            );
            uint64 third = _assertQueued(
                callers[c],
                address(secondAsset),
                _rescueKeeper,
                _rescueDestination,
                _AMOUNT
            );
            assertEq(
                configTimelock.pendingActionId(_key(address(_rescueAsset), _rescueKeeper)),
                first,
                "first recipient key remains owned"
            );
            assertEq(
                configTimelock.pendingActionId(_key(address(_rescueAsset), secondKeeper)),
                second,
                "second recipient key is independent"
            );
            assertEq(
                configTimelock.pendingActionId(_key(address(secondAsset), _rescueKeeper)),
                third,
                "second asset key is independent"
            );
            assertTrue(vm.revertToState(snapshot), "restore independent queues");
        }
    }

    /// @notice Mutable balances and entitlement do not stale the request: execute only stored four.
    // Scenarios: BLCT-E03.
    function test_givenQueuedRequest_whenEntitlementIncreases() public {
        vm.expectCall(
            address(burnerLoansConfig),
            abi.encodeCall(
                IBurnerLoansConfig.rescuePendingPayout,
                (address(_rescueAsset), _rescueKeeper, _rescueDestination, 4)
            ),
            1
        );
        vm.expectCall(
            address(burnerLoans),
            abi.encodeCall(
                IBurnerLoansRescue.rescuePendingPayout,
                (address(_rescueAsset), _rescueKeeper, _rescueDestination, 4)
            ),
            1
        );

        uint64 id = _assertQueued(
            admin,
            address(_rescueAsset),
            _rescueKeeper,
            _rescueDestination,
            4
        );

        _rescueAsset.mint(address(burnerLoans), 2);
        burnerLoans.recordPendingSeizureRewardForTest(address(_rescueAsset), _rescueKeeper, 2);

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecuted(id, uint256(12));
    }

    // Scenarios: BLCT-E03.
    function test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient() public {
        vm.expectCall(
            address(burnerLoansConfig),
            abi.encodeCall(
                IBurnerLoansConfig.rescuePendingPayout,
                (address(_rescueAsset), _rescueKeeper, _rescueDestination, 4)
            ),
            1
        );
        vm.expectCall(
            address(burnerLoans),
            abi.encodeCall(
                IBurnerLoansRescue.rescuePendingPayout,
                (address(_rescueAsset), _rescueKeeper, _rescueDestination, 4)
            ),
            1
        );

        uint64 id = _assertQueued(
            admin,
            address(_rescueAsset),
            _rescueKeeper,
            _rescueDestination,
            4
        );

        vm.prank(admin);
        burnerLoansConfig.rescuePendingPayout(address(_rescueAsset), _rescueKeeper, alice, 4);

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecuted(id, 6);
    }

    // Scenarios: BLCT-E03.
    function test_givenQueuedRequest_whenEntitlementEqualsAmount() public {
        vm.expectCall(
            address(burnerLoansConfig),
            abi.encodeCall(
                IBurnerLoansConfig.rescuePendingPayout,
                (address(_rescueAsset), _rescueKeeper, _rescueDestination, 4)
            ),
            1
        );
        vm.expectCall(
            address(burnerLoans),
            abi.encodeCall(
                IBurnerLoansRescue.rescuePendingPayout,
                (address(_rescueAsset), _rescueKeeper, _rescueDestination, 4)
            ),
            1
        );

        uint64 id = _assertQueued(
            admin,
            address(_rescueAsset),
            _rescueKeeper,
            _rescueDestination,
            4
        );

        vm.prank(admin);
        burnerLoansConfig.rescuePendingPayout(address(_rescueAsset), _rescueKeeper, alice, 6);

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecuted(id, 4);
    }

    // Scenarios: BLCT-E03.
    function test_givenQueuedRequest_whenCustodyIncreases() public {
        vm.expectCall(
            address(burnerLoansConfig),
            abi.encodeCall(
                IBurnerLoansConfig.rescuePendingPayout,
                (address(_rescueAsset), _rescueKeeper, _rescueDestination, 4)
            ),
            1
        );
        vm.expectCall(
            address(burnerLoans),
            abi.encodeCall(
                IBurnerLoansRescue.rescuePendingPayout,
                (address(_rescueAsset), _rescueKeeper, _rescueDestination, 4)
            ),
            1
        );

        uint64 id = _assertQueued(
            admin,
            address(_rescueAsset),
            _rescueKeeper,
            _rescueDestination,
            4
        );
        _rescueAsset.mint(address(burnerLoans), 5);
        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecuted(id, 10);
    }

    // Scenarios: BLCT-E04.
    function test_givenQueuedRequest_whenEntitlementIsInsufficient_reverts() public {
        vm.expectCall(
            address(burnerLoansConfig),
            abi.encodeCall(
                IBurnerLoansConfig.rescuePendingPayout,
                (address(_rescueAsset), _rescueKeeper, _rescueDestination, 4)
            ),
            1
        );
        vm.expectCall(
            address(burnerLoans),
            abi.encodeCall(
                IBurnerLoansRescue.rescuePendingPayout,
                (address(_rescueAsset), _rescueKeeper, _rescueDestination, 4)
            ),
            1
        );

        uint64 id = _assertQueued(
            admin,
            address(_rescueAsset),
            _rescueKeeper,
            _rescueDestination,
            4
        );

        vm.prank(admin);
        burnerLoansConfig.rescuePendingPayout(address(_rescueAsset), _rescueKeeper, alice, 7);

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(
            id,
            abi.encodeWithSelector(
                IBurnerLoansRescue.BurnerLoans_InsufficientPendingPayout.selector,
                address(_rescueAsset),
                4,
                3
            )
        );
    }

    // Scenarios: BLCT-E04.
    function test_givenQueuedRequest_whenEntitlementAlreadyPaid_reverts() public {
        vm.expectCall(
            address(burnerLoansConfig),
            abi.encodeCall(
                IBurnerLoansConfig.rescuePendingPayout,
                (address(_rescueAsset), _rescueKeeper, _rescueDestination, 4)
            ),
            1
        );
        vm.expectCall(
            address(burnerLoans),
            abi.encodeCall(
                IBurnerLoansRescue.rescuePendingPayout,
                (address(_rescueAsset), _rescueKeeper, _rescueDestination, 4)
            ),
            1
        );

        uint64 id = _assertQueued(
            admin,
            address(_rescueAsset),
            _rescueKeeper,
            _rescueDestination,
            4
        );

        vm.prank(admin);
        burnerLoansConfig.rescuePendingPayout(address(_rescueAsset), _rescueKeeper, alice, 10);

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(
            id,
            abi.encodeWithSelector(
                IBurnerLoansRescue.BurnerLoans_InsufficientPendingPayout.selector,
                address(_rescueAsset),
                4,
                0
            )
        );
    }

    /// @notice A fee destination change makes the original role recipient ineligible at execution.
    // Scenarios: BLCT-E09.
    function test_givenQueuedRoleRecipient_whenRoutingChanges_reverts() public {
        MockRevertingTransferToken asset = new MockRevertingTransferToken(18);
        asset.mint(alice, 10);
        vm.prank(alice);
        assertTrue(asset.approve(address(burnerLoans), 10), "fee approved");
        asset.setTransferReverts(address(trsry), true);
        burnerLoans.recordPendingFeeForTest(address(asset), alice, address(trsry), 10);
        uint64 id = _assertQueued(
            admin,
            address(asset),
            address(trsry),
            _rescueDestination,
            _AMOUNT
        );
        address[] memory tokens = new address[](1);
        tokens[0] = address(asset);
        _installRevenueDistributorForTest(tokens);
        vm.prank(address(configTimelock));
        burnerLoansConfig.setSendFeesToDistributor(true);
        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        bytes32 actionBefore = keccak256(abi.encode(configTimelock.getQueuedAction(id)));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRescue.BurnerLoans_InsufficientPendingPayout.selector,
                address(asset),
                _AMOUNT,
                0
            )
        );
        configTimelock.executeQueuedAction(id);
        assertEq(
            keccak256(abi.encode(configTimelock.getQueuedAction(id))),
            actionBefore,
            "routing failure retains action"
        );
        assertEq(
            configTimelock.pendingActionId(_key(address(asset), address(trsry))),
            id,
            "routing failure retains key"
        );
        assertEq(asset.balanceOf(address(burnerLoans)), 10, "role debt stays funded");
        assertEq(asset.balanceOf(_rescueDestination), 0, "role failure pays nothing");
        assertEq(burnerLoans.totalPendingForTest(address(asset)), 10, "role debt stays recorded");
    }

    /// @notice Treasury debt follows a module upgrade without invalidating the queued facility hash.
    // Scenarios: BLCT-E10.
    function test_givenQueuedTreasuryRecipient_whenTreasuryUpgraded_reverts() public {
        // The old Treasury owns 20 fee + 30 seizure units; the distinct keeper's ten stay separate.
        uint64 id = _assertQueued(
            admin,
            address(_rescueAsset),
            address(trsry),
            _rescueDestination,
            _AMOUNT
        );
        OlympusTreasury nextTreasury = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(nextTreasury));
        assertEq(
            burnerLoans.pendingPayout(address(_rescueAsset), address(trsry)),
            0,
            "old Treasury loses its role entitlement"
        );
        assertEq(
            burnerLoans.pendingPayout(address(_rescueAsset), address(nextTreasury)),
            _ROLE_PAYOUT,
            "new Treasury owns fee and seizure debt"
        );
        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(
            id,
            abi.encodeWithSelector(
                IBurnerLoansRescue.BurnerLoans_InsufficientPendingPayout.selector,
                address(_rescueAsset),
                _AMOUNT,
                uint256(0)
            )
        );
    }

    /// @notice Token/custody failure and BL inactivity roll back execution and keep the request pending.
    // Scenarios: BLCT-E05.
    function test_givenQueuedRequest_whenTokenRejectsTransfer_reverts() public {
        uint64 id = _assertQueued(
            admin,
            address(_rescueAsset),
            _rescueKeeper,
            _rescueDestination,
            _AMOUNT
        );
        bytes memory expected;

        _rescueAsset.setTransferReverts(_rescueDestination, true);
        expected = abi.encodeWithSelector(
            MockRevertingTransferToken.TransferReverted.selector,
            _rescueDestination
        );

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(id, expected);
    }

    // Scenarios: BLCT-E05.
    function test_givenQueuedRequest_whenCustodyIsInsufficient_reverts() public {
        uint64 id = _assertQueued(
            admin,
            address(_rescueAsset),
            _rescueKeeper,
            _rescueDestination,
            _AMOUNT
        );
        bytes memory expected;

        _rescueAsset.burn(address(burnerLoans), _rescueAsset.balanceOf(address(burnerLoans)));
        // The approved ERC-20 library bubbles its precise insufficient-balance error.
        expected = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector,
            address(burnerLoans),
            0,
            _AMOUNT
        );

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(id, expected);
    }

    // Scenarios: BLCT-E08.
    function test_givenQueuedRequest_whenFacilityBecomesInactive_reverts() public {
        uint64 id = _assertQueued(
            admin,
            address(_rescueAsset),
            _rescueKeeper,
            _rescueDestination,
            _AMOUNT
        );
        bytes memory expected;

        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
        expected = abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PolicyInactive.selector);

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(id, expected);
    }

    /// @dev Disable/deactivate one gate or rotate authority; return its exact queue error.
    function _failGate(Gate gate_) internal returns (bytes memory) {
        vm.startPrank(admin);
        if (gate_ == Gate.TimelockDisabled) configTimelock.disable("");
        else if (gate_ == Gate.ConfigDisabled) burnerLoansConfig.disable("");
        else if (gate_ == Gate.OperatorChanged) burnerLoansConfig.setConfigOperator(alice);
        else
            kernel.executeAction(
                Actions.DeactivatePolicy,
                gate_ == Gate.TimelockInactive
                    ? address(configTimelock)
                    : gate_ == Gate.ConfigInactive
                    ? address(burnerLoansConfig)
                    : address(burnerLoans)
            );
        vm.stopPrank();
        if (gate_ == Gate.TimelockDisabled || gate_ == Gate.ConfigDisabled)
            return abi.encodeWithSelector(IEnabler.NotEnabled.selector);
        if (gate_ == Gate.OperatorChanged)
            return
                abi.encodeWithSelector(
                    IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                    address(configTimelock)
                );
        if (gate_ == Gate.FacilityInactive)
            return abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PolicyInactive.selector);
        return
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_PolicyInactive.selector,
                gate_ == Gate.TimelockInactive
                    ? address(configTimelock)
                    : address(burnerLoansConfig)
            );
    }

    /// @dev Keep the exact authorized set excluded and compare both ordinary and invalid input.
    function _assertUnauthorized(address caller_) internal {
        bytes memory failure = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        _assertQueueFailure(caller_, _AMOUNT, failure);
        _assertQueueFailure(caller_, 0, failure);
    }

    /// @dev Rejection preserves the counter, conflict owner, existing action, configuration and funds.
    function _assertQueueFailure(address caller_, uint256 amount_, bytes memory failure_) internal {
        bytes32 beforeState = _queueState();
        vm.recordLogs();
        vm.expectRevert(failure_);
        vm.prank(caller_);
        configTimelock.queueRescuePendingPayout(
            address(_rescueAsset),
            _rescueKeeper,
            _rescueDestination,
            amount_
        );
        assertEq(vm.getRecordedLogs().length, 0, "queue validation emits no events");
        assertEq(_queueState(), beforeState, "queue rejection changes nothing");
        // The batch entry point must enforce the same lifecycle/authorization gates.
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.rescuePendingPayout.selector,
            payload: abi.encode(address(_rescueAsset), _rescueKeeper, _rescueDestination, amount_)
        });
        vm.recordLogs();
        vm.expectRevert(failure_);
        vm.prank(caller_);
        configTimelock.queueBatch(actions);
        assertEq(vm.getRecordedLogs().length, 0, "failed batch queue emits no events");
        assertEq(_queueState(), beforeState, "failed batch queue leaves state unchanged");
    }

    /// @dev Assert the queue-only ABI, timing, flags, config hash, key, events and unchanged custody.
    function _assertQueued(
        address caller_,
        address asset_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) internal returns (uint64 id) {
        bytes32 fundsBefore = _requestFundsHash(asset_, recipient_, destination_);
        uint64 next = configTimelock.nextActionId();
        bytes memory payload = abi.encode(asset_, recipient_, destination_, amount_);
        bytes32 key = _key(asset_, recipient_);
        bytes32 expectedHash = keccak256(abi.encode(burnerLoansConfig.facility()));
        vm.expectEmit(true, true, true, true, address(configTimelock));
        emit IConfigTimelockBatchQueue.ConfigStateQueued(
            next,
            0,
            key,
            0,
            address(burnerLoansConfig),
            expectedHash
        );
        _expectSingleActionQueued(
            next,
            caller_,
            IBurnerLoansConfig.rescuePendingPayout.selector,
            payload
        );
        vm.recordLogs();
        vm.prank(caller_);
        id = configTimelock.queueRescuePendingPayout(asset_, recipient_, destination_, amount_);
        assertEq(vm.getRecordedLogs().length, 3, "queue emits exactly three events");
        assertEq(id, next, "queue returns previous counter");
        assertEq(configTimelock.nextActionId(), next + 1, "queue increments counter once");
        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(id);
        assertEq(action.proposer, caller_, "queue stores proposer");
        assertEq(action.queuedAt, block.timestamp, "queue stores current time");
        assertEq(
            action.executableAt,
            block.timestamp + configTimelock.timelockDelay(),
            "queue stores ready time"
        );
        assertEq(
            action.expiresAt,
            action.executableAt + configTimelock.EXECUTION_WINDOW(),
            "queue stores expiry"
        );
        assertFalse(action.executed || action.cancelled, "new action is pending");
        assertEq(action.actions.length, 1, "one sub-action stored");
        assertEq(action.actions[0].target, address(burnerLoansConfig), "target is BLC");
        assertEq(
            action.actions[0].selector,
            IBurnerLoansConfig.rescuePendingPayout.selector,
            "selector preserved"
        );
        assertEq(action.actions[0].payload, payload, "all arguments preserved");
        assertEq(
            configTimelock.getQueuedConfigDestination(id, 0),
            address(burnerLoansConfig),
            "guard destination is BLC"
        );
        assertEq(configTimelock.getQueuedConfigStateCount(id, 0), 1, "one guard stored");
        (bytes32 storedKey, bytes32 storedHash) = configTimelock.getQueuedConfigState(id, 0, 0);
        assertEq(storedKey, key, "guard key matches independent encoding");
        assertEq(storedHash, expectedHash, "guard hashes only facility binding");
        assertEq(configTimelock.pendingActionId(key), id, "queued action owns key");
        assertEq(
            _requestFundsHash(asset_, recipient_, destination_),
            fundsBefore,
            "queue moves no funds or entitlement"
        );
    }

    /// @dev Execute a ready request once using unchanged parameters and current entitlement.
    function _assertExecuted(uint64 id_, uint256 available_) internal {
        uint256 custodyBefore = _rescueAsset.balanceOf(address(burnerLoans));
        configTimelock.executeQueuedAction(id_);
        assertEq(
            _rescueAsset.balanceOf(_rescueDestination),
            _AMOUNT,
            "stored amount paid exactly once"
        );
        assertEq(
            _rescueAsset.balanceOf(address(burnerLoans)),
            custodyBefore - _AMOUNT,
            "execution debits exact custody"
        );
        assertEq(
            burnerLoans.pendingPayout(address(_rescueAsset), _rescueKeeper),
            available_ - _AMOUNT,
            "current entitlement debited"
        );
        assertEq(
            burnerLoans.pendingFeeForTest(address(_rescueAsset)),
            _FEE_PAYOUT,
            "fee debt unchanged"
        );
        assertEq(
            burnerLoans.pendingSeizureForTest(address(_rescueAsset)),
            _SEIZURE_PAYOUT,
            "seizure debt unchanged"
        );
        assertTrue(configTimelock.getQueuedAction(id_).executed, "action completes");
        assertEq(
            configTimelock.pendingActionId(_key(address(_rescueAsset), _rescueKeeper)),
            0,
            "completed key released"
        );
    }

    /// @dev Failed execution retains all action metadata, guard/key ownership, debt and balances.
    function _assertExecutionFailure(uint64 id_, bytes memory failure_) internal {
        bytes32 beforeState = _queueState();
        // The request may select a role recipient rather than the default keeper.
        (bytes32 key, bytes32 guardHash) = configTimelock.getQueuedConfigState(id_, 0, 0);
        bytes32 actionBefore = keccak256(abi.encode(configTimelock.getQueuedAction(id_)));
        vm.expectRevert(failure_);
        configTimelock.executeQueuedAction(id_);
        assertEq(_queueState(), beforeState, "execution failure fully rolls back");
        assertEq(
            keccak256(abi.encode(configTimelock.getQueuedAction(id_))),
            actionBefore,
            "failed request retains its exact action"
        );
        (bytes32 keyAfter, bytes32 guardHashAfter) = configTimelock.getQueuedConfigState(id_, 0, 0);
        assertEq(keyAfter, key, "failed request retains its guard key");
        assertEq(guardHashAfter, guardHash, "failed request retains its guard hash");
        assertEq(configTimelock.pendingActionId(key), id_, "failed request retains key ownership");
    }

    /// @dev BLCT keys are scoped to BLC, selector, token and original recipient only.
    function _key(address asset_, address recipient_) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    address(burnerLoansConfig),
                    keccak256(
                        abi.encode(
                            keccak256("BURNER_LOANS_RESCUE"),
                            IBurnerLoansConfig.rescuePendingPayout.selector,
                            asset_,
                            recipient_
                        )
                    )
                )
            );
    }

    /// @dev Fingerprint authoritative debts, custody, payout enumeration and configuration.
    function _fundsHash() internal view returns (bytes32) {
        bytes32 debts = keccak256(
            abi.encode(
                _rescueAsset.balanceOf(address(burnerLoans)),
                _rescueAsset.balanceOf(_rescueDestination),
                burnerLoans.totalPendingForTest(address(_rescueAsset)),
                burnerLoans.pendingFeeForTest(address(_rescueAsset)),
                burnerLoans.pendingSeizureForTest(address(_rescueAsset)),
                burnerLoans.pendingSeizureRewardForTest(address(_rescueAsset), _rescueKeeper)
            )
        );
        bytes32 config = keccak256(
            abi.encode(
                burnerLoansConfig.facility(),
                burnerLoansConfig.configOperator(),
                burnerLoansConfig.isEnabled(),
                configTimelock.isEnabled(),
                burnerLoans.isEnabled()
            )
        );
        return
            keccak256(
                abi.encode(
                    debts,
                    config,
                    burnerLoans.getPendingPayoutTokens(),
                    burnerLoans.getPendingPayoutRecipients(address(_rescueAsset))
                )
            );
    }

    /// @dev Also fingerprint the actual request asset/recipient when queueing independent keys.
    function _requestFundsHash(
        address asset_,
        address recipient_,
        address destination_
    ) internal view returns (bytes32) {
        MockRevertingTransferToken asset = MockRevertingTransferToken(asset_);
        return
            keccak256(
                abi.encode(
                    _fundsHash(),
                    burnerLoans.pendingPayout(asset_, recipient_),
                    burnerLoans.totalPendingForTest(asset_),
                    burnerLoans.getPendingPayoutRecipients(asset_),
                    asset.balanceOf(address(burnerLoans)),
                    asset.balanceOf(destination_)
                )
            );
    }

    /// @dev Include existing pending-action contents so a failed second queue cannot corrupt them.
    function _queueState() internal view returns (bytes32) {
        uint64 owner = configTimelock.pendingActionId(_key(address(_rescueAsset), _rescueKeeper));
        bytes32 actionHash;
        if (owner != 0) {
            (bytes32 key, bytes32 stateHash) = configTimelock.getQueuedConfigState(owner, 0, 0);
            actionHash = keccak256(
                abi.encode(
                    configTimelock.getQueuedAction(owner),
                    key,
                    stateHash,
                    configTimelock.getQueuedConfigDestination(owner, 0),
                    configTimelock.getQueuedConfigStateCount(owner, 0)
                )
            );
        }
        return
            keccak256(abi.encode(configTimelock.nextActionId(), owner, actionHash, _fundsHash()));
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unused-return,calls-loop)
