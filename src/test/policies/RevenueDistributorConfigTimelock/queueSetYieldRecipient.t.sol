// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Expected-revert queue calls cannot use their returned action IDs. Bounded three-asset loops
// exercise absent, single and multiple pending-yield sets.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";
import {RevenueDistributorConfigTimelockTest} from "src/test/policies/RevenueDistributorConfigTimelock/RevenueDistributorConfigTimelockTest.sol";

contract RevenueDistributorConfigTimelockQueueSetYieldRecipientTest is
    RevenueDistributorConfigTimelockTest
{
    function _setCurrentPointer(bool nonzero_) internal returns (address current) {
        if (!nonzero_) return address(0);
        current = address(_activeYieldRecipient());
        vm.prank(admin);
        distributor.setYieldRecipient(current);
    }

    function _candidateForLifecycle(uint8 kind_) internal returns (address candidate) {
        uint8 kind = kind_ % 7;
        if (kind == 1) return address(treasury);
        if (kind == 2) return bob;
        if (kind == 3) return address(token);
        if (kind == 4) return address(_activeYieldRecipient());
        if (kind == 5) return address(new MockYieldRepurchaseRecipient(kernel));
        if (kind == 6) {
            MockYieldRepurchaseRecipient disabledRecipient = _activeYieldRecipient();
            disabledRecipient.setEnabled(false);
            return address(disabledRecipient);
        }
    }

    function _yieldAssets() internal returns (address[3] memory assets) {
        assets = [
            address(token),
            address(new MockERC20("Second Revenue", "REV2", 18)),
            address(new MockERC20("Third Revenue", "REV3", 18))
        ];
    }

    // queueSetYieldRecipient
    // given Treasury is the requested yield recipient
    //  when either permitted proposer queues the change
    //   then queue-time validation rejects it without consuming state
    // Scenarios: QSYR-I01
    function test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue(bool useRevenueAdmin_) public {
        address proposer = _permittedProposer(useRevenueAdmin_);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidYieldRecipient.selector,
                address(treasury)
            )
        );
        vm.prank(proposer);
        configTimelock.queueSetYieldRecipient(address(treasury));

        assertEq(configTimelock.nextActionId(), 1, "invalid recipient should not consume ID");
        assertEq(
            distributor.yieldRecipient(),
            address(0),
            "invalid recipient should not be stored"
        );
    }

    // Scenarios: QSYR-A01
    function testFuzz_whenUnauthorizedCallerQueues_reverts(
        address caller_,
        uint8 recipientKind_
    ) public {
        address revenueAdmin = _permittedProposer(true);
        vm.assume(caller_ != admin);
        vm.assume(caller_ != revenueAdmin);
        address recipient;
        uint8 kind = recipientKind_ % 7;
        if (kind == 1) recipient = address(treasury);
        if (kind == 2) recipient = bob;
        if (kind == 3) recipient = address(token);
        if (kind == 4) recipient = address(_activeYieldRecipient());
        if (kind == 5) recipient = address(new MockYieldRepurchaseRecipient(kernel));
        if (kind == 6) {
            MockYieldRepurchaseRecipient disabledRecipient = _activeYieldRecipient();
            disabledRecipient.setEnabled(false);
            recipient = address(disabledRecipient);
        }

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        configTimelock.queueSetYieldRecipient(recipient);

        assertEq(configTimelock.nextActionId(), 1, "unauthorized call consumes no ID");
    }

    // Scenarios: QSYR-L01
    function testFuzz_givenTimelockDisabled_whenQueued_reverts(
        bool useRevenueAdmin_,
        bool currentNonzero_,
        uint8 recipientKind_
    ) public {
        address current = _setCurrentPointer(currentNonzero_);
        address candidate = _candidateForLifecycle(recipientKind_);
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(emergency);
        configTimelock.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(proposer);
        configTimelock.queueSetYieldRecipient(candidate);

        assertEq(configTimelock.nextActionId(), 1, "disabled call consumes no ID");
        assertEq(distributor.yieldRecipient(), current, "disabled call preserves pointer");
    }

    // Scenarios: QSYR-L02
    function testFuzz_givenTimelockInactive_whenQueued_reverts(
        bool useRevenueAdmin_,
        bool currentNonzero_,
        uint8 recipientKind_
    ) public {
        address current = _setCurrentPointer(currentNonzero_);
        address candidate = _candidateForLifecycle(recipientKind_);
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_PolicyInactive
                    .selector,
                address(configTimelock)
            )
        );
        vm.prank(proposer);
        configTimelock.queueSetYieldRecipient(candidate);

        assertEq(configTimelock.nextActionId(), 1, "inactive call consumes no ID");
        assertEq(distributor.yieldRecipient(), current, "inactive call preserves pointer");
    }

    // Scenarios: QSYR-L03
    function testFuzz_givenOperatorRotated_whenQueued_reverts(
        bool useRevenueAdmin_,
        bool currentNonzero_,
        uint8 recipientKind_
    ) public {
        address current = _setCurrentPointer(currentNonzero_);
        address candidate = _candidateForLifecycle(recipientKind_);
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(admin);
        distributor.setConfigOperator(bob);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(configTimelock)
            )
        );
        vm.prank(proposer);
        configTimelock.queueSetYieldRecipient(candidate);

        assertEq(configTimelock.nextActionId(), 1, "unselected operator consumes no ID");
        assertEq(distributor.yieldRecipient(), current, "unselected operator preserves pointer");
    }

    // Scenarios: QSYR-L04
    function testFuzz_givenDistributorDisabled_whenQueued_reverts(
        bool useRevenueAdmin_,
        bool currentNonzero_,
        uint8 recipientKind_
    ) public {
        address current = _setCurrentPointer(currentNonzero_);
        address candidate = _candidateForLifecycle(recipientKind_);
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(admin);
        distributor.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(proposer);
        configTimelock.queueSetYieldRecipient(candidate);

        assertEq(configTimelock.nextActionId(), 1, "disabled target consumes no ID");
        assertEq(distributor.yieldRecipient(), current, "disabled target preserves pointer");
    }

    // Scenarios: QSYR-L05
    function testFuzz_givenDistributorInactive_whenQueued_revertsBeforeLocalState(
        bool useRevenueAdmin_,
        bool locallyEnabled_,
        bool currentNonzero_,
        uint8 recipientKind_
    ) public {
        address current = _setCurrentPointer(currentNonzero_);
        address candidate = _candidateForLifecycle(recipientKind_);
        address proposer = _permittedProposer(useRevenueAdmin_);
        if (!locallyEnabled_) {
            vm.prank(admin);
            distributor.disable("");
        }
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_PolicyInactive
                    .selector,
                address(distributor)
            )
        );
        vm.prank(proposer);
        configTimelock.queueSetYieldRecipient(candidate);

        assertEq(configTimelock.nextActionId(), 1, "inactive target consumes no ID");
        assertEq(distributor.yieldRecipient(), current, "inactive target preserves pointer");
    }

    // Scenarios: QSYR-P01
    function testFuzz_whenValidNonzeroRecipientQueues_executesAfterDelay(
        bool useRevenueAdmin_,
        address executor_,
        uint8 assetCount_
    ) public {
        assetCount_ = uint8(bound(assetCount_, 0, 3));
        MockYieldRepurchaseRecipient former = _activeYieldRecipient();
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        address[3] memory assets = _yieldAssets();
        vm.prank(admin);
        distributor.setYieldRecipient(address(former));
        for (uint256 i; i < assetCount_; ++i) {
            former.setVaultConfig(assets[i], assets[i], true);
            recipient.setVaultConfig(assets[i], assets[i], true);
            vm.prank(admin);
            distributor.setAssetRoutes(assets[i], 1, _emptyRoutes());
            distributor.seedPendingForTest(assets[i], alice, 0, i + 1, 0);
        }
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(proposer);
        uint64 actionId = configTimelock.queueSetYieldRecipient(address(recipient));

        assertEq(distributor.yieldRecipient(), address(former), "queue does not update pointer");
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);
        vm.expectEmit(true, false, false, false, address(distributor));
        emit IRevenueDistributor.YieldRecipientSet(address(recipient));
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(distributor.yieldRecipient(), address(recipient), "execution updates pointer");
        for (uint256 i; i < assetCount_; ++i) {
            assertEq(
                distributor.pendingPayout(assets[i], address(former)),
                0,
                "former loses yield debt"
            );
            assertEq(
                distributor.pendingPayout(assets[i], address(recipient)),
                i + 1,
                "candidate gains yield debt"
            );
        }
    }

    // Scenarios: QSYR-P04
    function testFuzz_whenZeroRecipientQueues_executes(
        bool useRevenueAdmin_,
        address executor_,
        uint8 assetCount_
    ) public {
        assetCount_ = uint8(bound(assetCount_, 0, 3));
        address[3] memory assets = _yieldAssets();
        for (uint256 i; i < assetCount_; ++i) {
            distributor.seedPendingForTest(assets[i], alice, 1, i + 2, i + 3);
        }
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(proposer);
        uint64 actionId = configTimelock.queueSetYieldRecipient(address(0));
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.recordLogs();
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(distributor.yieldRecipient(), address(0), "zero pointer retained");
        assertTrue(configTimelock.getQueuedAction(actionId).executed, "no-op action executed");
        assertEq(vm.getRecordedLogs().length, 2, "no-op emits only timelock execution events");
        for (uint256 i; i < assetCount_; ++i) {
            assertEq(
                distributor.pendingPayout(assets[i], address(treasury)),
                2 * i + 5,
                "Treasury debts unchanged"
            );
            assertEq(distributor.pendingPayout(assets[i], alice), 1, "fixed debt unchanged");
        }
    }

    // Scenarios: QSYR-P02
    function testFuzz_whenNonzeroPointerCleared_executes(
        bool useRevenueAdmin_,
        address executor_,
        uint8 assetCount_
    ) public {
        assetCount_ = uint8(bound(assetCount_, 0, 3));
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        address[3] memory assets = _yieldAssets();
        vm.prank(admin);
        distributor.setYieldRecipient(address(recipient));
        for (uint256 i; i < assetCount_; ++i) {
            distributor.seedPendingForTest(assets[i], alice, 1, i + 2, i + 3);
        }
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(proposer);
        uint64 actionId = configTimelock.queueSetYieldRecipient(address(0));
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.expectEmit(true, false, false, false, address(distributor));
        emit IRevenueDistributor.YieldRecipientSet(address(0));
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(distributor.yieldRecipient(), address(0), "execution clears pointer");
        for (uint256 i; i < assetCount_; ++i) {
            assertEq(
                distributor.pendingPayout(assets[i], address(recipient)),
                0,
                "former loses yield debt"
            );
            assertEq(
                distributor.pendingPayout(assets[i], address(treasury)),
                2 * i + 5,
                "Treasury gains yield debt"
            );
            assertEq(distributor.pendingPayout(assets[i], alice), 1, "fixed debt unchanged");
        }
    }

    // Scenarios: QSYR-P03
    function testFuzz_whenSameNonzeroRecipientQueues_executesAsValidatedNoOp(
        bool useRevenueAdmin_,
        address executor_,
        uint8 assetCount_
    ) public {
        assetCount_ = uint8(bound(assetCount_, 0, 3));
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        address[3] memory assets = _yieldAssets();
        vm.prank(admin);
        distributor.setYieldRecipient(address(recipient));
        for (uint256 i; i < assetCount_; ++i) {
            recipient.setVaultConfig(assets[i], assets[i], true);
            vm.prank(admin);
            distributor.setAssetRoutes(assets[i], 1, _emptyRoutes());
            distributor.seedPendingForTest(assets[i], alice, 1, i + 2, i + 3);
        }
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(proposer);
        uint64 actionId = configTimelock.queueSetYieldRecipient(address(recipient));
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.recordLogs();
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(distributor.yieldRecipient(), address(recipient), "same pointer retained");
        assertTrue(configTimelock.getQueuedAction(actionId).executed, "no-op action executed");
        assertEq(vm.getRecordedLogs().length, 2, "no-op emits only timelock execution events");
        for (uint256 i; i < assetCount_; ++i) {
            assertEq(
                distributor.pendingPayout(assets[i], address(recipient)),
                i + 2,
                "yield debt unchanged"
            );
            assertEq(distributor.pendingPayout(assets[i], alice), 1, "fixed debt unchanged");
            assertEq(
                distributor.pendingPayout(assets[i], address(treasury)),
                i + 3,
                "Treasury debt unchanged"
            );
        }
    }

    // Scenarios: QSYR-S01
    function testFuzz_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey(
        address executor_
    ) public {
        MockYieldRepurchaseRecipient queuedRecipient = _activeYieldRecipient();
        MockYieldRepurchaseRecipient liveRecipient = _activeYieldRecipient();
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetYieldRecipient(address(queuedRecipient));
        (bytes32 key, bytes32 expectedHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        vm.prank(admin);
        distributor.setYieldRecipient(address(liveRecipient));
        bytes32 actualHash = keccak256(abi.encode(address(liveRecipient)));
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId,
                0,
                key,
                expectedHash,
                actualHash
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(distributor.yieldRecipient(), address(liveRecipient), "live pointer retained");
        assertEq(configTimelock.pendingActionId(key), actionId, "stale action retains key");
    }

    // Scenarios: QSYR-Q01
    function testFuzz_whenGlobalKeyAlreadyOwned_secondQueueReverts(
        bool sameRecipient_,
        bool useRevenueAdmin_
    ) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        MockYieldRepurchaseRecipient firstRecipient = _activeYieldRecipient();
        MockYieldRepurchaseRecipient secondRecipient = sameRecipient_
            ? firstRecipient
            : _activeYieldRecipient();
        vm.prank(proposer);
        uint64 actionId = configTimelock.queueSetYieldRecipient(address(firstRecipient));
        (bytes32 key, ) = configTimelock.getQueuedConfigState(actionId, 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                key,
                actionId
            )
        );
        vm.prank(proposer);
        configTimelock.queueSetYieldRecipient(address(secondRecipient));

        assertEq(configTimelock.nextActionId(), actionId + 1, "failed queue consumes no ID");
        assertEq(configTimelock.pendingActionId(key), actionId, "first action retains key");
    }

    // Scenarios: QSYR-S02, QSYR-S04
    function testFuzz_whenCandidateBecomesUnavailable_executionRevertsThenRetries(
        bool deactivate_,
        address executor_
    ) public {
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetYieldRecipient(address(recipient));
        bytes32 key = _queuedKey(actionId, 0);
        if (deactivate_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(recipient));
        } else {
            recipient.setEnabled(false);
        }
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidYieldRecipient.selector,
                address(recipient)
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(configTimelock.pendingActionId(key), actionId, "failed action retains key");
        if (deactivate_) {
            vm.prank(admin);
            kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        } else {
            recipient.setEnabled(true);
        }
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertEq(distributor.yieldRecipient(), address(recipient), "retry updates pointer");
    }

    // Scenarios: QSYR-S05
    function testFuzz_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries(
        address executor_
    ) public {
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetYieldRecipient(address(recipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: address(recipient), bps: 1});
        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, routes);
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_DuplicateRecipient.selector,
                address(recipient)
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, _emptyRoutes());
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertEq(distributor.yieldRecipient(), address(recipient), "retry updates pointer");
    }

    // Scenarios: QSYR-S03
    function testFuzz_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts(
        address executor_
    ) public {
        MockYieldRepurchaseRecipient currentRecipient = _activeYieldRecipient();
        currentRecipient.setVaultConfig(address(token), address(token), true);
        vm.prank(admin);
        distributor.setYieldRecipient(address(currentRecipient));
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetYieldRecipient(address(recipient));
        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 1, _emptyRoutes());
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(recipient),
                address(token)
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            distributor.yieldRecipient(),
            address(currentRecipient),
            "failed action preserves pointer"
        );
        assertFalse(configTimelock.getQueuedAction(actionId).executed, "action remains live");
    }

    // Scenarios: QSYR-S06
    function testFuzz_whenUnsupportedRetiredPendingYieldAdded_executionReverts(
        address executor_
    ) public {
        MockRevertingTransferToken pendingToken = new MockRevertingTransferToken(18);
        MockYieldRepurchaseRecipient currentRecipient = _activeYieldRecipient();
        currentRecipient.setVaultConfig(address(pendingToken), address(pendingToken), true);
        vm.prank(admin);
        distributor.setYieldRecipient(address(currentRecipient));
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetYieldRecipient(address(recipient));
        vm.prank(admin);
        distributor.setAssetRoutes(address(pendingToken), 10_000, _emptyRoutes());
        pendingToken.setTransferReverts(address(currentRecipient), true);
        pendingToken.mint(address(distributor), 1);
        distributor.distribute(address(pendingToken));
        vm.prank(admin);
        distributor.disableAssetRoutes(address(pendingToken));
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(recipient),
                address(pendingToken)
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            distributor.yieldRecipient(),
            address(currentRecipient),
            "failed action preserves pointer"
        );
        assertFalse(configTimelock.getQueuedAction(actionId).executed, "action remains live");
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
