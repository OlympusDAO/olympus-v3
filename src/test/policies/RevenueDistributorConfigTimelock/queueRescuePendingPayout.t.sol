// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20Errors} from "@openzeppelin-5.7.0/interfaces/draft-IERC6093.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IRevenueDistributorRescue} from "src/policies/interfaces/IRevenueDistributorRescue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";
import {RevenueDistributorTest} from "src/test/policies/RevenueDistributor/RevenueDistributorTest.sol";

// Small, finite scenario loops use literal base units and inspect expected failures.
// forge-lint: disable-start(literal-instead-of-constant,unused-return,calls-loop,unsafe-typecast)
/// @dev Fixed ten-unit entitlement isolates RDT validation and queue integration from RD allocation.
contract RevenueDistributorConfigTimelockQueueRescuePendingPayoutTest is RevenueDistributorTest {
    uint256 internal constant _AMOUNT = 4;
    uint256 internal constant _ENTITLEMENT = 10;
    uint16 internal constant _FULL_REPURCHASE_BPS = 10_000;
    MockRevertingTransferToken internal _rescueAsset;
    address internal _originalRecipient;
    address internal _revenueAdmin;
    enum Gate {
        Disabled,
        Inactive,
        OperatorChanged,
        DistributorInactive
    }

    /// @dev A failed configured distribution creates ten funded units; queue roles are distinct.
    function setUp() public override {
        super.setUp();
        _revenueAdmin = makeAddr("revenue admin");
        vm.prank(admin);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, _revenueAdmin);
        _originalRecipient = alice;
        _rescueAsset = new MockRevertingTransferToken(18);
        _setRoute(address(_rescueAsset), alice);
        _rescueAsset.mint(address(distributor), 10);
        _rescueAsset.setTransferReverts(alice, true);
        distributor.distribute(address(_rescueAsset));
        _assertPendingPayouts(address(_rescueAsset), alice, 10, 0, 0);
    }

    /// @notice Both roles queue exact four-unit requests for Active/Retired assets and disabled RD.
    // Scenarios: RDT-L01, RDT-Q01.
    function test_givenValidRequest_whenEachRoleQueues() public {
        address[2] memory callers = [admin, _revenueAdmin];
        for (uint256 state; state < 4; ++state) {
            for (uint256 c; c < callers.length; ++c) {
                uint256 snapshot = vm.snapshotState();
                if (state >= 2) {
                    vm.prank(admin);
                    distributor.disableAssetRoutes(address(_rescueAsset));
                }
                if (state % 2 != 0) {
                    vm.prank(admin);
                    distributor.disable("");
                }
                uint64 id = _assertQueued(
                    callers[c],
                    address(_rescueAsset),
                    _originalRecipient,
                    bob,
                    _AMOUNT
                );
                vm.warp(configTimelock.getQueuedAction(id).executableAt);
                _assertExecuted(id, 10);
                assertTrue(vm.revertToState(snapshot), "restore queue fixture");
            }
        }
    }

    /// @notice Earlier RDT gates win over caller/input errors; RD activity wins over its inputs.
    // Scenarios: RDT-L03.
    function test_givenTimelockDisabled_whenPendingRescueQueued_reverts() public {
        address[3] memory callers = [admin, _revenueAdmin, emergency];

        for (uint256 disabledRD; disabledRD < 2; ++disabledRD) {
            uint256 snapshot = vm.snapshotState();
            if (disabledRD != 0) {
                vm.prank(admin);
                distributor.disable("");
            }
            vm.startPrank(admin);
            configTimelock.disable("");
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(IEnabler.NotEnabled.selector);

            for (uint256 c; c < callers.length; ++c) {
                bytes memory expected = failure;
                _assertQueueFailure(callers[c], _AMOUNT, expected);
                _assertQueueFailure(callers[c], 0, expected);
            }
            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    // Scenarios: RDT-L07.
    function test_givenTimelockInactive_whenPendingRescueQueued_reverts() public {
        address[3] memory callers = [admin, _revenueAdmin, emergency];

        for (uint256 disabledRD; disabledRD < 2; ++disabledRD) {
            uint256 snapshot = vm.snapshotState();
            if (disabledRD != 0) {
                vm.prank(admin);
                distributor.disable("");
            }
            vm.startPrank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_PolicyInactive
                    .selector,
                address(configTimelock)
            );

            for (uint256 c; c < callers.length; ++c) {
                bytes memory expected = failure;
                _assertQueueFailure(callers[c], _AMOUNT, expected);
                _assertQueueFailure(callers[c], 0, expected);
            }
            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    // Scenarios: RDT-L08.
    function test_givenOperatorChanged_whenPendingRescueQueued_reverts() public {
        address[3] memory callers = [admin, _revenueAdmin, emergency];

        for (uint256 disabledRD; disabledRD < 2; ++disabledRD) {
            uint256 snapshot = vm.snapshotState();
            if (disabledRD != 0) {
                vm.prank(admin);
                distributor.disable("");
            }
            vm.startPrank(admin);
            distributor.setConfigOperator(emergency);
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(configTimelock)
            );

            for (uint256 c; c < callers.length; ++c) {
                bytes memory expected = failure;
                _assertQueueFailure(callers[c], _AMOUNT, expected);
                _assertQueueFailure(callers[c], 0, expected);
            }
            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    // Scenarios: RDT-L05.
    function test_givenDistributorInactive_whenAdminQueuesPendingRescue_reverts() public {
        for (uint256 disabledRD; disabledRD < 2; ++disabledRD) {
            uint256 snapshot = vm.snapshotState();
            if (disabledRD != 0) {
                vm.prank(admin);
                distributor.disable("");
            }
            vm.startPrank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
            );

            vm.expectRevert(failure);
            distributor.previewRescuePendingPayout(
                address(_rescueAsset),
                _originalRecipient,
                bob,
                0
            );

            bytes memory expected = failure;
            _assertQueueFailure(admin, _AMOUNT, expected);
            _assertQueueFailure(admin, 0, expected);

            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    // Scenarios: RDT-L05.
    function test_givenDistributorInactive_whenRevenueAdminQueuesPendingRescue_reverts() public {
        for (uint256 disabledRD; disabledRD < 2; ++disabledRD) {
            uint256 snapshot = vm.snapshotState();
            if (disabledRD != 0) {
                vm.prank(admin);
                distributor.disable("");
            }
            vm.startPrank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
            );

            vm.expectRevert(failure);
            distributor.previewRescuePendingPayout(
                address(_rescueAsset),
                _originalRecipient,
                bob,
                0
            );

            bytes memory expected = failure;
            _assertQueueFailure(_revenueAdmin, _AMOUNT, expected);
            _assertQueueFailure(_revenueAdmin, 0, expected);

            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    // Scenarios: RDT-L02.
    function test_givenDistributorInactive_whenUnauthorizedCallerQueuesPendingRescue_reverts()
        public
    {
        for (uint256 disabledRD; disabledRD < 2; ++disabledRD) {
            uint256 snapshot = vm.snapshotState();
            if (disabledRD != 0) {
                vm.prank(admin);
                distributor.disable("");
            }
            vm.startPrank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
            );

            vm.expectRevert(failure);
            distributor.previewRescuePendingPayout(
                address(_rescueAsset),
                _originalRecipient,
                bob,
                0
            );

            bytes memory expected = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
            _assertQueueFailure(emergency, _AMOUNT, expected);
            _assertQueueFailure(emergency, 0, expected);

            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    /// @notice Fuzz only unauthorized callers, then co-locate valid/invalid preview propagation.
    // Scenarios: RDT-L02.
    function test_whenQueueCallerIsUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != admin && caller_ != _revenueAdmin);
        _assertUnauthorized(caller_);
    }

    /// @notice Operator-only, emergency-only, original payout owner and zero are guaranteed seeds.
    // Scenarios: RDT-L02.
    function test_whenUnauthorizedIdentitiesAreSeeded_reverts() public {
        _assertUnauthorized(address(configTimelock));
        _assertUnauthorized(emergency);
        _assertUnauthorized(alice);
        _assertUnauthorized(address(0));
    }

    /// @notice Simultaneous disablement, activity and operator faults establish RDT check order.
    // Scenarios: RDT-L03, RDT-L07, RDT-L08.
    function test_whenQueueFaultsCompete_reverts() public {
        uint256 snapshot = vm.snapshotState();
        _failGate(Gate.DistributorInactive);
        _failGate(Gate.Inactive);
        _failGate(Gate.Disabled);
        _assertQueueFailure(emergency, 0, abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        assertTrue(vm.revertToState(snapshot), "restore competing lifecycle");
        snapshot = vm.snapshotState();
        _failGate(Gate.OperatorChanged);
        bytes memory failure = _failGate(Gate.Inactive);
        _assertQueueFailure(emergency, 0, failure);
        assertTrue(vm.revertToState(snapshot), "restore competing authority");
        failure = _failGate(Gate.OperatorChanged);
        _assertQueueFailure(emergency, 0, failure);
    }

    /// @notice Zero amount is rejected by RD before either a free or already-owned key.
    // Scenarios: RDT-I01.
    function test_whenPreviewRejectsBeforeConflict_reverts() public {
        for (uint256 state; state < 4; ++state) {
            uint256 snapshot = vm.snapshotState();
            if ((state & 1) != 0) {
                vm.prank(admin);
                distributor.disableAssetRoutes(address(_rescueAsset));
            }
            if ((state & 2) != 0) {
                vm.prank(admin);
                distributor.disable("");
            }

            address[2] memory callers = [admin, _revenueAdmin];
            bytes memory failure = abi.encodeWithSelector(
                IRevenueDistributorRescue.RevenueDistributor_InvalidRescueAmount.selector
            );
            for (uint256 c; c < callers.length; ++c) {
                _assertQueueFailure(callers[c], 0, failure);
            }
            _assertQueued(admin, address(_rescueAsset), _originalRecipient, bob, _AMOUNT);
            for (uint256 c; c < callers.length; ++c) {
                _assertQueueFailure(callers[c], 0, failure);
            }
            assertTrue(vm.revertToState(snapshot), "restore preview-before-conflict state");
        }
    }

    /// @notice All recipients/amounts/destinations and route actions share the same asset key.
    // Scenarios: RDT-Q02.
    function test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts() public {
        _setRoute(address(_rescueAsset), emergency);
        _rescueAsset.mint(address(distributor), 10);
        _rescueAsset.setTransferReverts(emergency, true);
        distributor.distribute(address(_rescueAsset));
        address[2] memory callers = [admin, _revenueAdmin];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            uint64 id = _assertQueued(callers[c], address(_rescueAsset), alice, bob, _AMOUNT);
            bytes memory failure = abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _key(address(_rescueAsset)),
                id
            );
            _assertQueueFailure(callers[c], 6, failure);
            bytes32 beforeState = _queueState();
            vm.expectRevert(failure);
            vm.prank(callers[c]);
            configTimelock.queueRescuePendingPayout(
                address(_rescueAsset),
                emergency,
                admin,
                _AMOUNT
            );
            assertEq(_queueState(), beforeState, "recipient/destination changes retain owner");
            IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
                0
            );
            vm.expectRevert(failure);
            vm.prank(callers[c]);
            configTimelock.queueSetAssetRoutes(address(_rescueAsset), 0, routes);
            assertEq(_queueState(), beforeState, "route action cannot reuse asset key");
            assertTrue(vm.revertToState(snapshot), "restore conflict fixture");
        }
    }

    /// @notice Another asset and a global yield-recipient action are independent of the rescue key.
    // Scenarios: RDT-Q03.
    function test_givenIndependentAssetAndGlobalAction_whenQueued() public {
        MockRevertingTransferToken other = new MockRevertingTransferToken(18);
        _setRoute(address(other), alice);
        other.mint(address(distributor), 10);
        other.setTransferReverts(alice, true);
        distributor.distribute(address(other));
        address[2] memory callers = [admin, _revenueAdmin];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            uint64 first = _assertQueued(callers[c], address(_rescueAsset), alice, bob, _AMOUNT);
            uint64 second = _assertQueued(callers[c], address(other), alice, bob, _AMOUNT);
            vm.prank(callers[c]);
            uint64 globalActionId = configTimelock.queueSetYieldRecipient(address(0));
            (bytes32 globalKey, bytes32 globalHash) = configTimelock.getQueuedConfigState(
                globalActionId,
                0,
                0
            );
            assertTrue(
                globalActionId != first && globalActionId != second,
                "global action has independent ID"
            );
            assertEq(
                configTimelock.pendingActionId(_key(address(_rescueAsset))),
                first,
                "first asset owner unchanged"
            );
            assertEq(
                configTimelock.pendingActionId(_key(address(other))),
                second,
                "second asset owns independent key"
            );
            assertEq(
                configTimelock.pendingActionId(globalKey),
                globalActionId,
                "global key owns yield action"
            );
            assertEq(
                globalHash,
                keccak256(abi.encode(address(0))),
                "global guard captures zero pointer"
            );
            assertEq(
                configTimelock.getQueuedConfigStateCount(globalActionId, 0),
                1,
                "global action has one guard"
            );
            assertEq(
                configTimelock.getQueuedConfigDestination(globalActionId, 0),
                address(distributor),
                "global action targets distributor"
            );
            assertEq(other.balanceOf(address(distributor)), 10, "other asset unpaid at queue time");
            assertTrue(vm.revertToState(snapshot), "restore independent queues");
        }
    }

    /// @notice Changing entitlement or custody keeps the hash live and revalidates stored amount=4.
    // Scenarios: RDT-E03, EXEC-S02.
    function test_givenQueuedRequest_whenEntitlementIncreases() public {
        vm.expectCall(
            address(distributor),
            abi.encodeCall(
                distributor.rescuePendingPayout,
                (address(_rescueAsset), _originalRecipient, bob, 4)
            ),
            uint64(1)
        );

        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertQueued(admin, address(_rescueAsset), alice, bob, 4);

        _rescueAsset.mint(address(distributor), 2);
        distributor.distribute(address(_rescueAsset));

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecuted(id, uint256(12));
        assertTrue(vm.revertToState(snapshot), "restore changed entitlement");
    }

    // Scenarios: RDT-E03, EXEC-S02.
    function test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient() public {
        vm.expectCall(
            address(distributor),
            abi.encodeCall(
                distributor.rescuePendingPayout,
                (address(_rescueAsset), _originalRecipient, bob, 4)
            ),
            uint64(1)
        );

        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertQueued(admin, address(_rescueAsset), alice, bob, 4);

        vm.prank(admin);
        distributor.rescuePendingPayout(address(_rescueAsset), alice, emergency, 4);

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecuted(id, 6);
        assertTrue(vm.revertToState(snapshot), "restore changed entitlement");
    }

    // Scenarios: RDT-E03, EXEC-S02.
    function test_givenQueuedRequest_whenEntitlementEqualsAmount() public {
        vm.expectCall(
            address(distributor),
            abi.encodeCall(
                distributor.rescuePendingPayout,
                (address(_rescueAsset), _originalRecipient, bob, 4)
            ),
            uint64(1)
        );

        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertQueued(admin, address(_rescueAsset), alice, bob, 4);

        vm.prank(admin);
        distributor.rescuePendingPayout(address(_rescueAsset), alice, emergency, 6);

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecuted(id, 4);
        assertTrue(vm.revertToState(snapshot), "restore changed entitlement");
    }

    // Scenarios: RDT-E03, EXEC-S02.
    function test_givenQueuedRequest_whenCustodyIncreases() public {
        vm.expectCall(
            address(distributor),
            abi.encodeCall(
                distributor.rescuePendingPayout,
                (address(_rescueAsset), _originalRecipient, bob, 4)
            ),
            uint64(1)
        );

        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertQueued(admin, address(_rescueAsset), alice, bob, 4);
        _rescueAsset.mint(address(distributor), 5);
        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecuted(id, 10);
        assertTrue(vm.revertToState(snapshot), "restore changed entitlement");
    }

    // Scenarios: RDT-E04.
    function test_givenQueuedRequest_whenEntitlementIsInsufficient_reverts() public {
        vm.expectCall(
            address(distributor),
            abi.encodeCall(
                distributor.rescuePendingPayout,
                (address(_rescueAsset), _originalRecipient, bob, 4)
            ),
            uint64(1)
        );

        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertQueued(admin, address(_rescueAsset), alice, bob, 4);

        vm.prank(admin);
        distributor.rescuePendingPayout(address(_rescueAsset), alice, emergency, 7);

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(
            id,
            abi.encodeWithSelector(
                IRevenueDistributorRescue
                    .RevenueDistributor_InsufficientPendingDistribution
                    .selector,
                address(_rescueAsset),
                4,
                3
            )
        );
        assertTrue(vm.revertToState(snapshot), "restore changed entitlement");
    }

    // Scenarios: RDT-E04.
    function test_givenQueuedRequest_whenEntitlementAlreadyPaid_reverts() public {
        vm.expectCall(
            address(distributor),
            abi.encodeCall(
                distributor.rescuePendingPayout,
                (address(_rescueAsset), _originalRecipient, bob, 4)
            ),
            uint64(1)
        );

        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertQueued(admin, address(_rescueAsset), alice, bob, 4);

        vm.prank(admin);
        distributor.rescuePendingPayout(address(_rescueAsset), alice, emergency, 10);

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(
            id,
            abi.encodeWithSelector(
                IRevenueDistributorRescue
                    .RevenueDistributor_InsufficientPendingDistribution
                    .selector,
                address(_rescueAsset),
                4,
                0
            )
        );
        assertTrue(vm.revertToState(snapshot), "restore changed entitlement");
    }

    /// @notice Retirement stales the hash before amount checks, even if entitlement fell below four.
    // Scenarios: RDT-E05.
    function test_givenQueuedActiveAsset_whenRetired_reverts() public {
        for (uint256 reduce; reduce < 2; ++reduce) {
            uint256 snapshot = vm.snapshotState();
            uint64 id = _assertQueued(admin, address(_rescueAsset), alice, bob, _AMOUNT);
            if (reduce != 0) {
                vm.prank(admin);
                distributor.rescuePendingPayout(address(_rescueAsset), alice, emergency, 7);
            }
            vm.prank(admin);
            distributor.disableAssetRoutes(address(_rescueAsset));
            vm.warp(configTimelock.getQueuedAction(id).executableAt);
            _assertExecutionFailure(
                id,
                abi.encodeWithSelector(
                    IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                    id,
                    uint256(0),
                    _key(address(_rescueAsset)),
                    keccak256(abi.encode(IRevenueDistributor.AssetState.Active)),
                    keccak256(abi.encode(IRevenueDistributor.AssetState.Retired))
                )
            );
            assertTrue(vm.revertToState(snapshot), "restore retirement fixture");
        }
    }

    /// @notice Route, yield-role and Treasury changes preserve fixed debt and do not stale rescue.
    // Scenarios: RDT-E09.
    function test_givenQueuedFixedRecipient_whenRouteChanges() public {
        // Historical route debt belongs to Alice, regardless of today's role destinations.
        vm.expectCall(
            address(distributor),
            abi.encodeCall(
                distributor.rescuePendingPayout,
                (address(_rescueAsset), _originalRecipient, bob, _AMOUNT)
            ),
            uint64(1)
        );
        uint64 id = _assertQueued(admin, address(_rescueAsset), alice, bob, _AMOUNT);
        _setRoute(address(_rescueAsset), emergency);
        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecuted(id, _ENTITLEMENT);
    }

    // Scenarios: RDT-E09.
    function test_givenQueuedFixedRecipient_whenYieldRecipientChanges() public {
        // Historical route debt belongs to Alice, regardless of today's role destinations.
        vm.expectCall(
            address(distributor),
            abi.encodeCall(
                distributor.rescuePendingPayout,
                (address(_rescueAsset), _originalRecipient, bob, _AMOUNT)
            ),
            uint64(1)
        );
        uint64 id = _assertQueued(admin, address(_rescueAsset), alice, bob, _AMOUNT);
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        distributor.setYieldRecipient(address(recipient));
        vm.stopPrank();
        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecuted(id, _ENTITLEMENT);
    }

    // Scenarios: RDT-E09.
    function test_givenQueuedFixedRecipient_whenTreasuryUpgraded() public {
        // Historical route debt belongs to Alice, regardless of today's role destinations.
        vm.expectCall(
            address(distributor),
            abi.encodeCall(
                distributor.rescuePendingPayout,
                (address(_rescueAsset), _originalRecipient, bob, _AMOUNT)
            ),
            uint64(1)
        );
        uint64 id = _assertQueued(admin, address(_rescueAsset), alice, bob, _AMOUNT);
        OlympusTreasury nextTreasury = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(nextTreasury));
        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecuted(id, _ENTITLEMENT);
    }

    /// @notice Global repurchase and Treasury debt follows new role destinations after queueing.
    // Scenarios: RDT-E04.
    function test_givenQueuedRepurchaseRecipient_whenRepurchaseRecipientChanges_reverts() public {
        // Role debt follows the current role holder; the queued address loses entitlement.
        _rescueAsset = new MockRevertingTransferToken(18);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        MockYieldRepurchaseRecipient recipient = _newYieldRecipient(address(_rescueAsset));
        vm.prank(admin);
        distributor.setYieldRecipient(address(recipient));
        _originalRecipient = address(recipient);
        vm.prank(admin);
        distributor.setAssetRoutes(address(_rescueAsset), _FULL_REPURCHASE_BPS, routes);
        _rescueAsset.mint(address(distributor), _ENTITLEMENT);
        _rescueAsset.setTransferReverts(_originalRecipient, true);
        distributor.distribute(address(_rescueAsset));
        uint64 id = _assertQueued(admin, address(_rescueAsset), _originalRecipient, bob, _AMOUNT);
        MockYieldRepurchaseRecipient next = _newYieldRecipient(address(_rescueAsset));
        vm.prank(admin);
        distributor.setYieldRecipient(address(next));
        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(
            id,
            abi.encodeWithSelector(
                IRevenueDistributorRescue
                    .RevenueDistributor_InsufficientPendingDistribution
                    .selector,
                address(_rescueAsset),
                _AMOUNT,
                0
            )
        );
    }

    // Scenarios: RDT-E04.
    function test_givenQueuedTreasuryRecipient_whenTreasuryUpgraded_reverts() public {
        // Role debt follows the current role holder; the queued address loses entitlement.
        _rescueAsset = new MockRevertingTransferToken(18);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        _originalRecipient = distributor.treasury();
        vm.prank(admin);
        distributor.setAssetRoutes(address(_rescueAsset), 0, routes);
        _rescueAsset.mint(address(distributor), _ENTITLEMENT);
        _rescueAsset.setTransferReverts(_originalRecipient, true);
        distributor.distribute(address(_rescueAsset));
        uint64 id = _assertQueued(admin, address(_rescueAsset), _originalRecipient, bob, _AMOUNT);
        OlympusTreasury next = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(next));
        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(
            id,
            abi.encodeWithSelector(
                IRevenueDistributorRescue
                    .RevenueDistributor_InsufficientPendingDistribution
                    .selector,
                address(_rescueAsset),
                _AMOUNT,
                0
            )
        );
    }

    /// @notice Transfer, insufficient custody, and target inactivity keep the queued rescue pending.
    // Scenarios: RDT-E06.
    function test_givenQueuedRequest_whenTokenRejectsTransfer_reverts() public {
        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertQueued(admin, address(_rescueAsset), _originalRecipient, bob, _AMOUNT);
        bytes memory expected;

        _rescueAsset.setTransferReverts(bob, true);
        expected = abi.encodeWithSelector(
            MockRevertingTransferToken.TransferReverted.selector,
            bob
        );

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(id, expected);
        assertTrue(vm.revertToState(snapshot), "restore dependency failure");
    }

    // Scenarios: RDT-E06.
    function test_givenQueuedRequest_whenCustodyIsInsufficient_reverts() public {
        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertQueued(admin, address(_rescueAsset), _originalRecipient, bob, _AMOUNT);
        bytes memory expected;

        _rescueAsset.burn(address(distributor), 10);
        expected = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector,
            address(distributor),
            0,
            _AMOUNT
        );

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(id, expected);
        assertTrue(vm.revertToState(snapshot), "restore dependency failure");
    }

    // Scenarios: RDT-E10.
    function test_givenQueuedRequest_whenDistributorBecomesInactive_reverts() public {
        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertQueued(admin, address(_rescueAsset), _originalRecipient, bob, _AMOUNT);
        bytes memory expected;

        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        expected = abi.encodeWithSelector(
            IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
        );

        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(id, expected);
        assertTrue(vm.revertToState(snapshot), "restore dependency failure");
    }

    /// @notice Disablement after queueing blocks a mature request and preserves its debt and key.
    // Scenarios: RDT-E11.
    function test_givenQueuedRequest_givenTimelockDisabled_whenExecuted_reverts() public {
        uint64 id = _assertQueued(admin, address(_rescueAsset), _originalRecipient, bob, _AMOUNT);
        bytes memory failure = _failGate(Gate.Disabled);
        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(id, failure);
    }

    /// @notice Kernel deactivation after queueing blocks a mature request before dispatch to RD.
    // Scenarios: RDT-E12.
    function test_givenQueuedRequest_givenTimelockInactive_whenExecuted_reverts() public {
        uint64 id = _assertQueued(admin, address(_rescueAsset), _originalRecipient, bob, _AMOUNT);
        bytes memory failure = _failGate(Gate.Inactive);
        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionFailure(id, failure);
    }

    /// @notice A ready pending rescue needs no executor role; only its queued inputs determine payment.
    // Scenarios: RDT-E13.
    function test_givenQueuedRequest_whenAnyCallerExecutes(address executor_) public {
        uint64 id = _assertQueued(admin, address(_rescueAsset), _originalRecipient, bob, _AMOUNT);
        vm.warp(configTimelock.getQueuedAction(id).executableAt);
        // No exclusions, including zero, proposers and protocol contracts. Keep the prank active
        // across the helper's balance reads so the execution call uses this fuzzed identity.
        vm.startPrank(executor_);
        _assertExecuted(id, 10);
        vm.stopPrank();
    }

    /// @dev Install a single 100% fixed route. Distribution setup, not allocation, is the queue fixture.
    function _setRoute(address asset_, address recipient_) internal {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: recipient_, bps: 10_000});
        vm.prank(admin);
        distributor.setAssetRoutes(asset_, 0, routes);
    }

    /// @dev Create a supported policy so role rotation reaches the real governance validation path.
    function _newYieldRecipient(
        address asset_
    ) internal returns (MockYieldRepurchaseRecipient recipient) {
        recipient = new MockYieldRepurchaseRecipient(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        recipient.setVaultConfig(asset_, asset_, true);
    }

    /// @dev Fail one gate and return its exact custom error; local RD disablement is independent.
    function _failGate(Gate gate_) internal returns (bytes memory) {
        vm.startPrank(admin);
        if (gate_ == Gate.Disabled) {
            configTimelock.disable("");
        } else if (gate_ == Gate.OperatorChanged) {
            distributor.setConfigOperator(emergency);
        } else {
            kernel.executeAction(
                Actions.DeactivatePolicy,
                gate_ == Gate.Inactive ? address(configTimelock) : address(distributor)
            );
        }
        vm.stopPrank();
        if (gate_ == Gate.Disabled) return abi.encodeWithSelector(IEnabler.NotEnabled.selector);
        if (gate_ == Gate.OperatorChanged) {
            return
                abi.encodeWithSelector(
                    IConfigOperator.ConfigOperator_Unauthorized.selector,
                    address(configTimelock)
                );
        }
        if (gate_ == Gate.DistributorInactive) {
            return
                abi.encodeWithSelector(
                    IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
                );
        }
        return
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_PolicyInactive
                    .selector,
                address(configTimelock)
            );
    }

    /// @dev Check unauthorized proposer rejection with ordinary and zero amounts.
    function _assertUnauthorized(address caller_) internal {
        bytes memory failure = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        _assertQueueFailure(caller_, _AMOUNT, failure);
        _assertQueueFailure(caller_, 0, failure);
    }

    /// @dev No queue ID, key, existing action, debt, configuration or custody may change on failure.
    function _assertQueueFailure(address caller_, uint256 amount_, bytes memory failure_) internal {
        bytes32 beforeState = _queueState();
        vm.recordLogs();
        vm.expectRevert(failure_);
        vm.prank(caller_);
        configTimelock.queueRescuePendingPayout(
            address(_rescueAsset),
            _originalRecipient,
            bob,
            amount_
        );
        assertEq(vm.getRecordedLogs().length, 0, "invalid queue emits no events");
        assertEq(_queueState(), beforeState, "invalid queue leaves state unchanged");
        // The batch entry point must enforce the same lifecycle/authorization gates.
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = ITimelockBatchQueue.BatchAction({
            target: address(distributor),
            selector: IRevenueDistributorRescue.rescuePendingPayout.selector,
            payload: abi.encode(address(_rescueAsset), _originalRecipient, bob, amount_)
        });
        vm.recordLogs();
        vm.expectRevert(failure_);
        vm.prank(caller_);
        configTimelock.queueBatch(actions);
        assertEq(vm.getRecordedLogs().length, 0, "failed batch queue emits no events");
        assertEq(_queueState(), beforeState, "failed batch queue leaves state unchanged");
    }

    /// @dev Verify every queued ABI field, timestamp, guard, key and event without executing.
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
        bytes32 key = _key(asset_);
        bytes32 stateHash = keccak256(abi.encode(distributor.assetState(asset_)));
        {
            ITimelockBatchQueue.BatchAction[]
                memory actions = new ITimelockBatchQueue.BatchAction[](1);
            actions[0] = ITimelockBatchQueue.BatchAction(
                address(distributor),
                IRevenueDistributorRescue.rescuePendingPayout.selector,
                payload
            );
            uint48 ready = uint48(block.timestamp + configTimelock.timelockDelay());
            vm.expectEmit(true, true, true, true, address(configTimelock));
            emit IConfigTimelockBatchQueue.ConfigStateQueued(
                next,
                0,
                key,
                0,
                address(distributor),
                stateHash
            );
            vm.expectEmit(true, true, true, true, address(configTimelock));
            emit ITimelockBatchQueue.TimelockSubActionQueued(
                next,
                address(distributor),
                IRevenueDistributorRescue.rescuePendingPayout.selector,
                0,
                keccak256(payload)
            );
            vm.expectEmit(true, true, false, true, address(configTimelock));
            emit ITimelockBatchQueue.TimelockActionQueued(
                next,
                caller_,
                keccak256(abi.encode(actions)),
                ready,
                ready + configTimelock.EXECUTION_WINDOW()
            );
        }
        vm.recordLogs();
        vm.prank(caller_);
        id = configTimelock.queueRescuePendingPayout(asset_, recipient_, destination_, amount_);
        assertEq(vm.getRecordedLogs().length, 3, "queue emits exactly three events");
        assertEq(id, next, "queue returns previous counter");
        assertEq(configTimelock.nextActionId(), next + 1, "counter increments once");
        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(id);
        assertEq(action.proposer, caller_, "proposer stored");
        assertEq(action.queuedAt, block.timestamp, "queue time stored");
        assertEq(
            action.executableAt,
            block.timestamp + configTimelock.timelockDelay(),
            "ready time stored"
        );
        assertEq(
            action.expiresAt,
            action.executableAt + configTimelock.EXECUTION_WINDOW(),
            "expiry stored"
        );
        assertFalse(action.executed || action.cancelled, "new action pending");
        assertEq(action.actions.length, 1, "one action stored");
        assertEq(action.actions[0].target, address(distributor), "RD is target");
        assertEq(
            action.actions[0].selector,
            IRevenueDistributorRescue.rescuePendingPayout.selector,
            "pending rescue selector stored"
        );
        assertEq(action.actions[0].payload, payload, "all four arguments stored");
        assertEq(
            configTimelock.getQueuedConfigDestination(id, 0),
            address(distributor),
            "RD owns config domain"
        );
        assertEq(configTimelock.getQueuedConfigStateCount(id, 0), 1, "one guard stored");
        (bytes32 storedKey, bytes32 storedHash) = configTimelock.getQueuedConfigState(id, 0, 0);
        assertEq(storedKey, key, "independent scoped key matches");
        assertEq(storedHash, stateHash, "guard hashes only listing state");
        assertEq(configTimelock.pendingActionId(key), id, "action owns asset key");
        assertEq(
            _requestFundsHash(asset_, recipient_, destination_),
            fundsBefore,
            "queue moves no funds or entitlement"
        );
    }

    /// @dev Compare execution with explicit current entitlement and verify completion/key release.
    function _assertExecuted(uint64 id_, uint256 available_) internal {
        uint256 custodyBefore = _rescueAsset.balanceOf(address(distributor));
        configTimelock.executeQueuedAction(id_);
        assertEq(_rescueAsset.balanceOf(bob), _AMOUNT, "only stored four paid");
        assertEq(
            _rescueAsset.balanceOf(address(distributor)),
            custodyBefore - _AMOUNT,
            "custody decreases exactly"
        );
        assertEq(
            distributor.pendingPayout(address(_rescueAsset), _originalRecipient),
            available_ - _AMOUNT,
            "only selected entitlement debited"
        );
        assertEq(
            distributor.totalPendingForTest(address(_rescueAsset)),
            available_ - _AMOUNT,
            "aggregate equals remaining fixed debt"
        );
        assertTrue(configTimelock.getQueuedAction(id_).executed, "action completes");
        assertEq(
            configTimelock.pendingActionId(_key(address(_rescueAsset))),
            0,
            "completed key released"
        );
    }

    /// @dev Failures retain the exact action and key and roll back all represented RD/token state.
    function _assertExecutionFailure(uint64 id_, bytes memory failure_) internal {
        bytes32 beforeState = _queueState();
        vm.expectRevert(failure_);
        configTimelock.executeQueuedAction(id_);
        assertEq(_queueState(), beforeState, "failed execution fully rolls back");
    }

    /// @dev Every asset-scoped action uses this RD/domain/asset key, independent of recipient.
    function _key(address asset_) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    address(distributor),
                    keccak256(abi.encode(keccak256("REVENUE_DISTRIBUTOR_ASSET"), asset_))
                )
            );
    }

    /// @dev Split fingerprints keep the legacy compiler stack shallow while covering raw state.
    function _fundsHash() internal view returns (bytes32) {
        bytes32 debts = keccak256(
            abi.encode(
                _rescueAsset.balanceOf(address(distributor)),
                _rescueAsset.balanceOf(bob),
                distributor.totalPendingForTest(address(_rescueAsset)),
                distributor.pendingAssetRouteForTest(address(_rescueAsset), alice),
                distributor.pendingAssetRouteForTest(address(_rescueAsset), emergency),
                distributor.pendingRepurchaseForTest(address(_rescueAsset)),
                distributor.pendingTreasuryForTest(address(_rescueAsset))
            )
        );
        bytes32 config = keccak256(
            abi.encode(
                distributor.configOperator(),
                distributor.yieldRecipient(),
                distributor.treasury(),
                distributor.assetDistributionHash(address(_rescueAsset)),
                distributor.assetState(address(_rescueAsset)),
                distributor.isEnabled(),
                configTimelock.isEnabled()
            )
        );
        return
            keccak256(
                abi.encode(
                    debts,
                    config,
                    distributor.getPendingPayoutAssets(),
                    distributor.getPendingPayoutRecipients(address(_rescueAsset))
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
                    distributor.pendingPayout(asset_, recipient_),
                    distributor.totalPendingForTest(asset_),
                    distributor.getPendingPayoutRecipients(asset_),
                    asset.balanceOf(address(distributor)),
                    asset.balanceOf(destination_)
                )
            );
    }

    /// @dev Include existing stored actions so failures cannot damage a prior queue owner.
    function _queueState() internal view returns (bytes32) {
        uint64 owner = configTimelock.pendingActionId(_key(address(_rescueAsset)));
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
// forge-lint: disable-end(literal-instead-of-constant,unused-return,calls-loop,unsafe-typecast)
