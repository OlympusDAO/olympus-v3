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

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
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
    // Scenarios: QSYR-I01.
    function test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue(
        bool useRevenueAdmin_,
        address proposerSeed_,
        bool revenueOnly_,
        bool overlap_
    ) public givenProposer(proposerSeed_, revenueOnly_, overlap_) {
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

    // Scenarios: QSYR-A01.
    function test_whenUnauthorizedCallerQueues_reverts(
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

    // Scenarios: QSYR-L01.
    function test_givenTimelockDisabled_whenQueued_reverts(
        bool useRevenueAdmin_,
        bool currentNonzero_,
        uint8 recipientKind_
    ) public {
        address current = _setCurrentPointer(currentNonzero_);
        address candidate = _candidateForLifecycle(recipientKind_);
        address proposer = _permittedProposer(useRevenueAdmin_);
        _disablePolicy(address(configTimelock), emergency);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(proposer);
        configTimelock.queueSetYieldRecipient(candidate);

        assertEq(configTimelock.nextActionId(), 1, "disabled call consumes no ID");
        assertEq(distributor.yieldRecipient(), current, "disabled call preserves pointer");
    }

    // Scenarios: QSYR-L02.
    function test_givenTimelockInactive_whenQueued_reverts(
        bool useRevenueAdmin_,
        bool currentNonzero_,
        uint8 recipientKind_
    ) public {
        address current = _setCurrentPointer(currentNonzero_);
        address candidate = _candidateForLifecycle(recipientKind_);
        address proposer = _permittedProposer(useRevenueAdmin_);
        _setPolicyActive(address(configTimelock), false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_PolicyNotActive
                    .selector,
                address(configTimelock)
            )
        );
        vm.prank(proposer);
        configTimelock.queueSetYieldRecipient(candidate);

        assertEq(configTimelock.nextActionId(), 1, "inactive call consumes no ID");
        assertEq(distributor.yieldRecipient(), current, "inactive call preserves pointer");
    }

    // Scenarios: QSYR-L03.
    function test_givenOperatorRotated_whenQueued_reverts(
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

    // Scenarios: QSYR-L04.
    function test_givenDistributorDisabled_whenQueued_reverts(
        bool useRevenueAdmin_,
        bool currentNonzero_,
        uint8 recipientKind_
    ) public {
        address current = _setCurrentPointer(currentNonzero_);
        address candidate = _candidateForLifecycle(recipientKind_);
        address proposer = _permittedProposer(useRevenueAdmin_);
        _disablePolicy(address(distributor), admin);

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(distributor)
            )
        );
        vm.prank(proposer);
        configTimelock.queueSetYieldRecipient(candidate);

        assertEq(configTimelock.nextActionId(), 1, "disabled target consumes no ID");
        assertEq(distributor.yieldRecipient(), current, "disabled target preserves pointer");
    }

    // Scenarios: QSYR-L05, QSYR-L06.
    function test_givenDistributorInactive_whenQueued_revertsBeforeLocalState(
        bool useRevenueAdmin_,
        bool locallyEnabled_,
        bool currentNonzero_,
        uint8 recipientKind_,
        address proposerSeed_,
        bool revenueOnly_,
        bool overlap_
    ) public givenProposer(proposerSeed_, revenueOnly_, overlap_) {
        address current = _setCurrentPointer(currentNonzero_);
        address candidate = _candidateForLifecycle(recipientKind_);
        address proposer = _permittedProposer(useRevenueAdmin_);
        if (!locallyEnabled_) {
            _disablePolicy(address(distributor), admin);
        }
        _setPolicyActive(address(distributor), false);

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(distributor)
            )
        );
        vm.prank(proposer);
        configTimelock.queueSetYieldRecipient(candidate);

        assertEq(configTimelock.nextActionId(), 1, "inactive target consumes no ID");
        assertEq(distributor.yieldRecipient(), current, "inactive target preserves pointer");
    }

    // Scenarios: QSYR-P01.
    function test_whenValidNonzeroRecipientQueues_executesAfterDelay(
        bool useRevenueAdmin_,
        address executor_,
        uint8 assetCount_,
        address proposerSeed_,
        bool revenueOnly_,
        bool overlap_
    ) public givenProposer(proposerSeed_, revenueOnly_, overlap_) {
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

    // Scenarios: QSYR-P04.
    function test_whenZeroRecipientQueues_reverts(
        bool useRevenueAdmin_,
        uint8 assetCount_,
        address proposerSeed_,
        bool revenueOnly_,
        bool overlap_
    ) public givenProposer(proposerSeed_, revenueOnly_, overlap_) {
        assetCount_ = uint8(bound(assetCount_, 0, 3));
        address[3] memory assets = _yieldAssets();
        for (uint256 i; i < assetCount_; ++i) {
            distributor.seedPendingForTest(assets[i], alice, 1, i + 2, i + 3);
        }
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_SameAddress.selector,
                address(0)
            )
        );
        vm.prank(proposer);
        configTimelock.queueSetYieldRecipient(address(0));
        assertEq(configTimelock.nextActionId(), 1, "Rejected pointer consumes no action ID");
        assertEq(distributor.yieldRecipient(), address(0), "Rejected pointer preserves selection");
        assertEq(vm.getRecordedLogs().length, 0, "Rejected pointer emits no logs");
        for (uint256 i; i < assetCount_; ++i) {
            assertEq(
                distributor.pendingPayout(assets[i], address(treasury)),
                2 * i + 5,
                "Treasury debts unchanged"
            );
            assertEq(distributor.pendingPayout(assets[i], alice), 1, "fixed debt unchanged");
        }
    }

    // Scenarios: QSYR-P02.
    function test_whenNonzeroPointerCleared_executes(
        bool useRevenueAdmin_,
        address executor_,
        uint8 assetCount_,
        address proposerSeed_,
        bool revenueOnly_,
        bool overlap_
    ) public givenProposer(proposerSeed_, revenueOnly_, overlap_) {
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

    // Scenarios: QSYR-P03.
    function test_whenSameNonzeroRecipientQueues_reverts(
        bool useRevenueAdmin_,
        uint8 assetCount_,
        address proposerSeed_,
        bool revenueOnly_,
        bool overlap_
    ) public givenProposer(proposerSeed_, revenueOnly_, overlap_) {
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
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_SameAddress.selector,
                address(recipient)
            )
        );
        vm.prank(proposer);
        configTimelock.queueSetYieldRecipient(address(recipient));
        assertEq(configTimelock.nextActionId(), 1, "Rejected pointer consumes no action ID");
        assertEq(
            distributor.yieldRecipient(),
            address(recipient),
            "Rejected pointer preserves selection"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected pointer emits no logs");
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

    // Scenarios: QSYR-S01, RDCT-EXECUTE-E05.
    function test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey(
        address executor_,
        address proposerSeed_,
        bool revenueOnly_,
        bool overlap_
    ) public givenProposer(proposerSeed_, revenueOnly_, overlap_) {
        MockYieldRepurchaseRecipient queuedRecipient = _activeYieldRecipient();
        MockYieldRepurchaseRecipient liveRecipient = _activeYieldRecipient();
        vm.prank(proposerSeed_);
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

    // Scenarios: QSYR-Q01.
    function test_whenGlobalKeyAlreadyOwned_secondQueueReverts(
        bool sameRecipient_,
        bool useRevenueAdmin_,
        address proposerSeed_,
        bool revenueOnly_,
        bool overlap_
    ) public givenProposer(proposerSeed_, revenueOnly_, overlap_) {
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

    // Scenarios: QSYR-S02, QSYR-S04.
    function test_whenCandidateBecomesUnavailable_executionRevertsThenRetries(
        bool deactivate_,
        address executor_,
        address proposerSeed_,
        bool revenueOnly_,
        bool overlap_
    ) public givenProposer(proposerSeed_, revenueOnly_, overlap_) {
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        vm.prank(proposerSeed_);
        uint64 actionId = configTimelock.queueSetYieldRecipient(address(recipient));
        bytes32 key = _queuedKey(actionId, 0);
        if (deactivate_) {
            _setPolicyActive(address(recipient), false);
        } else {
            recipient.setEnabled(false);
        }
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(recipient)
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(configTimelock.pendingActionId(key), actionId, "failed action retains key");
        if (deactivate_) {
            _setPolicyActive(address(recipient), true);
        } else {
            recipient.setEnabled(true);
        }
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertEq(distributor.yieldRecipient(), address(recipient), "retry updates pointer");
    }

    // Scenarios: QSYR-S05.
    function test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries(
        address executor_,
        address proposerSeed_,
        bool revenueOnly_,
        bool overlap_
    ) public givenProposer(proposerSeed_, revenueOnly_, overlap_) {
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        vm.prank(proposerSeed_);
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

    // Scenarios: QSYR-S03.
    function test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts(
        address executor_,
        address proposerSeed_,
        bool revenueOnly_,
        bool overlap_
    ) public givenProposer(proposerSeed_, revenueOnly_, overlap_) {
        MockYieldRepurchaseRecipient currentRecipient = _activeYieldRecipient();
        currentRecipient.setVaultConfig(address(token), address(token), true);
        vm.prank(admin);
        distributor.setYieldRecipient(address(currentRecipient));
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        vm.prank(proposerSeed_);
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

    // Scenarios: QSYR-S06.
    function test_whenUnsupportedRetiredPendingYieldAdded_executionReverts(
        address executor_,
        address proposerSeed_,
        bool revenueOnly_,
        bool overlap_
    ) public givenProposer(proposerSeed_, revenueOnly_, overlap_) {
        MockRevertingTransferToken pendingToken = new MockRevertingTransferToken(18);
        MockYieldRepurchaseRecipient currentRecipient = _activeYieldRecipient();
        currentRecipient.setVaultConfig(address(pendingToken), address(pendingToken), true);
        vm.prank(admin);
        distributor.setYieldRecipient(address(currentRecipient));
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        vm.prank(proposerSeed_);
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

    // Scenarios: QSYR-L05, QSYR-L06.
    function test_givenDistributorInactive_whenQueued_revertsBeforeLocalState_AdminOnlySeed()
        public
    {
        test_givenDistributorInactive_whenQueued_revertsBeforeLocalState(
            false,
            false,
            false,
            1,
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: QSYR-L05, QSYR-L06.
    function test_givenDistributorInactive_whenQueued_revertsBeforeLocalState_RevenueRoleOnlySeed()
        public
    {
        test_givenDistributorInactive_whenQueued_revertsBeforeLocalState(
            false,
            false,
            false,
            1,
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: QSYR-L05, QSYR-L06.
    function test_givenDistributorInactive_whenQueued_revertsBeforeLocalState_RolesOverlapSeed()
        public
    {
        test_givenDistributorInactive_whenQueued_revertsBeforeLocalState(
            false,
            false,
            false,
            1,
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: QSYR-S05.
    function test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries_AdminOnlySeed()
        public
    {
        test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries(
            address(0x2345),
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: QSYR-S05.
    function test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries_RevenueRoleOnlySeed()
        public
    {
        test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries(
            address(0x2345),
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: QSYR-S05.
    function test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries_RolesOverlapSeed()
        public
    {
        test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries(
            address(0x2345),
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: QSYR-S02, QSYR-S04.
    function test_whenCandidateBecomesUnavailable_executionRevertsThenRetries_AdminOnlySeed()
        public
    {
        test_whenCandidateBecomesUnavailable_executionRevertsThenRetries(
            false,
            address(0x2345),
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: QSYR-S02, QSYR-S04.
    function test_whenCandidateBecomesUnavailable_executionRevertsThenRetries_RevenueRoleOnlySeed()
        public
    {
        test_whenCandidateBecomesUnavailable_executionRevertsThenRetries(
            false,
            address(0x2345),
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: QSYR-S02, QSYR-S04.
    function test_whenCandidateBecomesUnavailable_executionRevertsThenRetries_RolesOverlapSeed()
        public
    {
        test_whenCandidateBecomesUnavailable_executionRevertsThenRetries(
            false,
            address(0x2345),
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: QSYR-Q01.
    function test_whenGlobalKeyAlreadyOwned_secondQueueReverts_AdminOnlySeed() public {
        test_whenGlobalKeyAlreadyOwned_secondQueueReverts(
            false,
            false,
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: QSYR-Q01.
    function test_whenGlobalKeyAlreadyOwned_secondQueueReverts_RevenueRoleOnlySeed() public {
        test_whenGlobalKeyAlreadyOwned_secondQueueReverts(
            false,
            false,
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: QSYR-Q01.
    function test_whenGlobalKeyAlreadyOwned_secondQueueReverts_RolesOverlapSeed() public {
        test_whenGlobalKeyAlreadyOwned_secondQueueReverts(
            false,
            false,
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: QSYR-P02.
    function test_whenNonzeroPointerCleared_executes_AdminOnlySeed() public {
        test_whenNonzeroPointerCleared_executes(
            false,
            address(0x2345),
            1,
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: QSYR-P02.
    function test_whenNonzeroPointerCleared_executes_RevenueRoleOnlySeed() public {
        test_whenNonzeroPointerCleared_executes(
            false,
            address(0x2345),
            1,
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: QSYR-P02.
    function test_whenNonzeroPointerCleared_executes_RolesOverlapSeed() public {
        test_whenNonzeroPointerCleared_executes(
            false,
            address(0x2345),
            1,
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: QSYR-S01.
    function test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey_AdminOnlySeed()
        public
    {
        test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey(
            address(0x2345),
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: QSYR-S01.
    function test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey_RevenueRoleOnlySeed()
        public
    {
        test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey(
            address(0x2345),
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: QSYR-S01.
    function test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey_RolesOverlapSeed()
        public
    {
        test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey(
            address(0x2345),
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: QSYR-P03.
    function test_whenSameNonzeroRecipientQueues_reverts_AdminOnlySeed() public {
        test_whenSameNonzeroRecipientQueues_reverts(false, 1, address(0x1234), false, false);
    }

    // Scenarios: QSYR-P03.
    function test_whenSameNonzeroRecipientQueues_reverts_RevenueRoleOnlySeed() public {
        test_whenSameNonzeroRecipientQueues_reverts(false, 1, address(0x1234), true, false);
    }

    // Scenarios: QSYR-P03.
    function test_whenSameNonzeroRecipientQueues_reverts_RolesOverlapSeed() public {
        test_whenSameNonzeroRecipientQueues_reverts(false, 1, address(0x1234), true, true);
    }

    // Scenarios: QSYR-I01.
    function test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue_AdminOnlySeed() public {
        test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue(
            false,
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: QSYR-I01.
    function test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue_RevenueRoleOnlySeed() public {
        test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue(false, address(0x1234), true, false);
    }

    // Scenarios: QSYR-I01.
    function test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue_RolesOverlapSeed() public {
        test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue(false, address(0x1234), true, true);
    }

    // Scenarios: QSYR-S03.
    function test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts_AdminOnlySeed()
        public
    {
        test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts(
            address(0x2345),
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: QSYR-S03.
    function test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts_RevenueRoleOnlySeed()
        public
    {
        test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts(
            address(0x2345),
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: QSYR-S03.
    function test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts_RolesOverlapSeed()
        public
    {
        test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts(
            address(0x2345),
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: QSYR-S06.
    function test_whenUnsupportedRetiredPendingYieldAdded_executionReverts_AdminOnlySeed() public {
        test_whenUnsupportedRetiredPendingYieldAdded_executionReverts(
            address(0x2345),
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: QSYR-S06.
    function test_whenUnsupportedRetiredPendingYieldAdded_executionReverts_RevenueRoleOnlySeed()
        public
    {
        test_whenUnsupportedRetiredPendingYieldAdded_executionReverts(
            address(0x2345),
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: QSYR-S06.
    function test_whenUnsupportedRetiredPendingYieldAdded_executionReverts_RolesOverlapSeed()
        public
    {
        test_whenUnsupportedRetiredPendingYieldAdded_executionReverts(
            address(0x2345),
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: QSYR-P01.
    function test_whenValidNonzeroRecipientQueues_executesAfterDelay_AdminOnlySeed() public {
        test_whenValidNonzeroRecipientQueues_executesAfterDelay(
            false,
            address(0x2345),
            1,
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: QSYR-P01.
    function test_whenValidNonzeroRecipientQueues_executesAfterDelay_RevenueRoleOnlySeed() public {
        test_whenValidNonzeroRecipientQueues_executesAfterDelay(
            false,
            address(0x2345),
            1,
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: QSYR-P01.
    function test_whenValidNonzeroRecipientQueues_executesAfterDelay_RolesOverlapSeed() public {
        test_whenValidNonzeroRecipientQueues_executesAfterDelay(
            false,
            address(0x2345),
            1,
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: QSYR-P04.
    function test_whenZeroRecipientQueues_reverts_AdminOnlySeed() public {
        test_whenZeroRecipientQueues_reverts(false, 1, address(0x1234), false, false);
    }

    // Scenarios: QSYR-P04.
    function test_whenZeroRecipientQueues_reverts_RevenueRoleOnlySeed() public {
        test_whenZeroRecipientQueues_reverts(false, 1, address(0x1234), true, false);
    }

    // Scenarios: QSYR-P04.
    function test_whenZeroRecipientQueues_reverts_RolesOverlapSeed() public {
        test_whenZeroRecipientQueues_reverts(false, 1, address(0x1234), true, true);
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
