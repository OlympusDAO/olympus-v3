// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// The test timestamp fits uint48. Queue returns are immaterial to tested reverts, and the fixed
// unauthorized-identity loop intentionally makes external assertions for each seed.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {RevenueDistributorConfigTimelockTest} from "./RevenueDistributorConfigTimelockTest.sol";

contract RevenueDistributorConfigTimelockQueueSetAssetRoutesTest is
    RevenueDistributorConfigTimelockTest
{
    uint16 internal constant QUEUED_REPURCHASE_BPS = 2_000;
    uint16 internal constant INVALID_ROUTE_BPS = 10_001;

    function _guardRoutes(
        bool includeRoute_,
        address recipient_,
        uint16 bps_
    ) internal pure returns (IRevenueDistributor.AssetRoute[] memory routes) {
        routes = new IRevenueDistributor.AssetRoute[](includeRoute_ ? 1 : 0);
        if (includeRoute_)
            routes[0] = IRevenueDistributor.AssetRoute({recipient: recipient_, bps: bps_});
    }

    function _assertExactQueuedRoute(
        uint64 actionId_,
        address proposer_,
        uint48 queuedAt_,
        uint48 executableAt_,
        uint48 expiresAt_,
        bytes memory payload_,
        bytes32 key_,
        bytes32 expectedHash_
    ) internal view {
        assertEq(configTimelock.nextActionId(), actionId_ + 1, "queue consumes one action ID");
        ITimelockBatchQueue.QueuedAction memory queued = configTimelock.getQueuedAction(actionId_);
        assertEq(queued.proposer, proposer_, "queued proposer");
        assertEq(queued.queuedAt, queuedAt_, "queued timestamp");
        assertEq(queued.executableAt, executableAt_, "ready timestamp");
        assertEq(queued.expiresAt, expiresAt_, "expiry timestamp");
        assertFalse(queued.executed, "queued action not executed");
        assertFalse(queued.cancelled, "queued action not cancelled");
        assertEq(queued.actions.length, 1, "one sub-action stored");
        assertEq(queued.actions[0].target, address(distributor), "stored target");
        assertEq(
            queued.actions[0].selector,
            IRevenueDistributor.setAssetRoutes.selector,
            "stored selector"
        );
        assertEq(keccak256(queued.actions[0].payload), keccak256(payload_), "stored payload");
        assertEq(configTimelock.getQueuedConfigStateCount(actionId_, 0), 1, "one guard stored");
        assertEq(
            configTimelock.getQueuedConfigDestination(actionId_, 0),
            address(distributor),
            "guard destination"
        );
        (bytes32 storedKey, bytes32 storedHash) = configTimelock.getQueuedConfigState(
            actionId_,
            0,
            0
        );
        assertEq(storedKey, key_, "guard key");
        assertEq(storedHash, expectedHash_, "guard state hash");
        assertEq(configTimelock.pendingActionId(key_), actionId_, "action owns guard key");
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.NeverListed),
            "queue does not configure route"
        );
    }

    // queueSetAssetRoutes
    // given route basis points exceed the maximum
    //  when either permitted proposer queues the route
    //   then queue-time validation rejects it without consuming state
    // Scenarios: QSAR-I01
    function test_whenRouteBasisPointsExceedMaximum_revertsAtQueue(bool useRevenueAdmin_) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: INVALID_ROUTE_BPS});

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidBasisPoints.selector,
                uint256(INVALID_ROUTE_BPS)
            )
        );
        vm.prank(proposer);
        configTimelock.queueSetAssetRoutes(address(token), 0, routes);

        assertEq(configTimelock.nextActionId(), 1, "invalid route should not consume action ID");
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.NeverListed),
            "invalid route should not list asset"
        );
    }

    // given a revenue distributor admin
    //   when that role queues a route and the delay elapses
    //     [X] the queued route activates
    function test_givenRevenueDistributorAdmin_whenRouteQueued_executesAfterDelay() public {
        address proposer = _permittedProposer(true);
        vm.prank(proposer);
        uint64 actionId = configTimelock.queueSetAssetRoutes(address(token), 0, _emptyRoutes());
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.NeverListed),
            "role holder cannot configure before delay"
        );
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);
        vm.prank(bob);
        configTimelock.executeQueuedAction(actionId);
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "role-queued route activates after delay"
        );
    }

    // Scenarios: QSAR-A01.
    function testFuzz_whenCallerHasNoConfigRole_queueReverts(
        address caller_,
        address asset_,
        uint16 repurchaseBps_,
        bool invalidRoute_
    ) public {
        address revenueAdmin = _permittedProposer(true);
        vm.assume(caller_ != admin);
        vm.assume(caller_ != revenueAdmin);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
            invalidRoute_ ? 1 : 0
        );
        if (invalidRoute_) {
            routes[0] = IRevenueDistributor.AssetRoute({recipient: address(0), bps: 0});
        }
        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        configTimelock.queueSetAssetRoutes(asset_, repurchaseBps_, routes);
    }

    // Scenarios: QSAR-A01
    function test_whenKnownUnauthorizedIdentitiesQueue_reverts() public {
        address[4] memory callers = [emergency, bob, address(configTimelock), address(distributor)];
        for (uint256 i; i < callers.length; ++i) {
            vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
            vm.prank(callers[i]);
            configTimelock.queueSetAssetRoutes(address(token), 0, _emptyRoutes());
        }
    }

    // Scenarios: QSAR-L01
    function testFuzz_givenTimelockDisabled_whenRouteQueued_reverts(
        bool useRevenueAdmin_,
        address asset_,
        uint16 repurchaseBps_,
        bool includeRoute_,
        address recipient_,
        uint16 routeBps_
    ) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(emergency);
        configTimelock.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(proposer);
        configTimelock.queueSetAssetRoutes(
            asset_,
            repurchaseBps_,
            _guardRoutes(includeRoute_, recipient_, routeBps_)
        );

        assertEq(configTimelock.nextActionId(), 1, "disabled call consumes no ID");
    }

    // Scenarios: QSAR-L02
    function testFuzz_givenTimelockInactive_whenRouteQueued_reverts(
        bool useRevenueAdmin_,
        address asset_,
        uint16 repurchaseBps_,
        bool includeRoute_,
        address recipient_,
        uint16 routeBps_
    ) public {
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
        configTimelock.queueSetAssetRoutes(
            asset_,
            repurchaseBps_,
            _guardRoutes(includeRoute_, recipient_, routeBps_)
        );

        assertEq(configTimelock.nextActionId(), 1, "inactive call consumes no ID");
    }

    // Scenarios: QSAR-L03
    function testFuzz_givenOperatorRotated_whenRouteQueued_reverts(
        bool useRevenueAdmin_,
        address asset_,
        uint16 repurchaseBps_,
        bool includeRoute_,
        address recipient_,
        uint16 routeBps_
    ) public {
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
        configTimelock.queueSetAssetRoutes(
            asset_,
            repurchaseBps_,
            _guardRoutes(includeRoute_, recipient_, routeBps_)
        );

        assertEq(configTimelock.nextActionId(), 1, "unselected operator consumes no ID");
    }

    // Scenarios: QSAR-L04
    function testFuzz_givenTargetDisabled_whenRouteQueued_revertsForEitherRole(
        bool useRevenueAdmin_,
        address asset_,
        uint16 repurchaseBps_,
        bool includeRoute_,
        address recipient_,
        uint16 routeBps_
    ) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(admin);
        distributor.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(proposer);
        configTimelock.queueSetAssetRoutes(
            asset_,
            repurchaseBps_,
            _guardRoutes(includeRoute_, recipient_, routeBps_)
        );

        assertEq(configTimelock.nextActionId(), 1, "disabled target consumes no ID");
    }

    // Scenarios: QSAR-L05
    function testFuzz_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState(
        bool useRevenueAdmin_,
        bool locallyEnabled_,
        address asset_,
        uint16 repurchaseBps_,
        bool includeRoute_,
        address recipient_,
        uint16 routeBps_
    ) public {
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
        configTimelock.queueSetAssetRoutes(
            asset_,
            repurchaseBps_,
            _guardRoutes(includeRoute_, recipient_, routeBps_)
        );

        assertEq(configTimelock.nextActionId(), 1, "inactive target consumes no ID");
    }

    // Scenarios: QSAR-P01
    function testFuzz_whenValidNonemptyRouteQueued_storesExactActionAndExecutes(
        bool useRevenueAdmin_,
        address executor_,
        uint48 executeAt_
    ) public {
        uint64 actionId;
        uint48 executableAt;
        uint48 expiresAt;
        bytes32 key;
        {
            address proposer = _permittedProposer(useRevenueAdmin_);
            IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
                1
            );
            routes[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 2_000});
            bytes memory payload = abi.encode(address(token), uint16(0), routes);
            ITimelockBatchQueue.BatchAction[]
                memory actions = new ITimelockBatchQueue.BatchAction[](1);
            actions[0] = ITimelockBatchQueue.BatchAction({
                target: address(distributor),
                selector: IRevenueDistributor.setAssetRoutes.selector,
                payload: payload
            });
            actionId = configTimelock.nextActionId();
            uint48 queuedAt = uint48(block.timestamp);
            executableAt = queuedAt + configTimelock.timelockDelay();
            expiresAt = executableAt + configTimelock.EXECUTION_WINDOW();
            bytes32 localKey = keccak256(
                abi.encode(keccak256("REVENUE_DISTRIBUTOR_ASSET"), address(token))
            );
            key = keccak256(abi.encode(address(distributor), localKey));
            bytes32 expectedHash = distributor.assetDistributionHash(address(token));

            vm.expectEmit(true, true, true, true, address(configTimelock));
            emit IConfigTimelockBatchQueue.ConfigStateQueued(
                actionId,
                0,
                key,
                0,
                address(distributor),
                expectedHash
            );
            vm.expectEmit(true, true, true, true, address(configTimelock));
            emit ITimelockBatchQueue.TimelockSubActionQueued(
                actionId,
                address(distributor),
                IRevenueDistributor.setAssetRoutes.selector,
                0,
                keccak256(payload)
            );
            vm.expectEmit(true, true, false, true, address(configTimelock));
            emit ITimelockBatchQueue.TimelockActionQueued(
                actionId,
                proposer,
                keccak256(abi.encode(actions)),
                executableAt,
                expiresAt
            );
            vm.prank(proposer);
            uint64 returnedId = configTimelock.queueSetAssetRoutes(address(token), 0, routes);

            assertEq(returnedId, actionId, "queue returns next action ID");
            _assertExactQueuedRoute(
                actionId,
                proposer,
                queuedAt,
                executableAt,
                expiresAt,
                payload,
                key,
                expectedHash
            );
        }

        executeAt_ = uint48(bound(executeAt_, executableAt, expiresAt));
        vm.warp(executeAt_);
        IRevenueDistributor.AssetRoute[]
            memory executionRoutes = new IRevenueDistributor.AssetRoute[](1);
        executionRoutes[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 2_000});
        vm.expectCall(
            address(distributor),
            abi.encodeCall(
                IRevenueDistributor.setAssetRoutes,
                (address(token), uint16(0), executionRoutes)
            ),
            1
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        (
            uint16 storedRepurchaseBps,
            IRevenueDistributor.AssetRoute[] memory storedRoutes
        ) = distributor.getAssetDistribution(address(token));
        assertEq(storedRepurchaseBps, 0, "repurchase BPS forwarded");
        assertEq(storedRoutes.length, 1, "one route configured");
        assertEq(storedRoutes[0].recipient, bob, "route recipient forwarded");
        assertEq(storedRoutes[0].bps, 2_000, "route BPS forwarded");
        assertTrue(configTimelock.getQueuedAction(actionId).executed, "action marked executed");
        assertEq(
            configTimelock.getQueuedAction(actionId).actions.length,
            0,
            "executed payload cleared"
        );
        assertEq(configTimelock.pendingActionId(key), 0, "executed action releases key");
    }

    // Scenarios: QSAR-S01
    function testFuzz_whenRouteChanges_executionRevertsAndRetainsKey(address executor_) public {
        _activateAsset(address(token));
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetRoutes(address(token), 0, _emptyRoutes());
        (bytes32 key, bytes32 expectedHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        IRevenueDistributor.AssetRoute[] memory changed = new IRevenueDistributor.AssetRoute[](1);
        changed[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 1});
        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, changed);
        bytes32 actualHash = distributor.assetDistributionHash(address(token));
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

        assertEq(configTimelock.pendingActionId(key), actionId, "stale action retains key");
        assertFalse(configTimelock.getQueuedAction(actionId).executed, "stale action remains live");
    }

    // Scenarios: QSAR-S04
    function testFuzz_whenListingChanges_executionRevertsAndRetainsKey(address executor_) public {
        _activateAsset(address(token));
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetRoutes(address(token), 0, _emptyRoutes());
        (bytes32 key, bytes32 expectedHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        vm.prank(admin);
        distributor.disableAssetRoutes(address(token));
        bytes32 actualHash = distributor.assetDistributionHash(address(token));
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

        assertEq(configTimelock.pendingActionId(key), actionId, "stale action retains key");
        assertFalse(configTimelock.getQueuedAction(actionId).executed, "stale action remains live");
    }

    // Scenarios: QSAR-S05
    function testFuzz_whenYieldPointerChanges_executionRevertsAndRetainsKey(
        address executor_
    ) public {
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetRoutes(address(token), 0, _emptyRoutes());
        (bytes32 key, bytes32 expectedHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        address recipient = address(_activeYieldRecipient());
        vm.prank(admin);
        distributor.setYieldRecipient(recipient);
        bytes32 actualHash = distributor.assetDistributionHash(address(token));
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

        assertEq(configTimelock.pendingActionId(key), actionId, "stale action retains key");
        assertFalse(configTimelock.getQueuedAction(actionId).executed, "stale action remains live");
    }

    // Scenarios: QSAR-S02
    function testFuzz_whenCustodyChangesAfterQueue_executionStillSucceeds(
        address executor_,
        uint256 donation_
    ) public {
        donation_ = bound(donation_, 1, type(uint128).max);
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetRoutes(address(token), 0, _emptyRoutes());
        token.mint(address(distributor), donation_);
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "custody donation does not stale route"
        );
        assertEq(token.balanceOf(address(distributor)), donation_, "donation remains in custody");
    }

    // Scenarios: QSAR-S06
    function testFuzz_whenPendingDebtPaidAfterQueue_executionStillSucceeds(
        address executor_
    ) public {
        MockRevertingTransferToken payoutToken = new MockRevertingTransferToken(18);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 10_000});
        vm.prank(admin);
        distributor.setAssetRoutes(address(payoutToken), 0, routes);
        payoutToken.mint(address(distributor), 10);
        payoutToken.setTransferReverts(bob, true);
        distributor.distribute(address(payoutToken));
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetRoutes(
            address(payoutToken),
            0,
            _emptyRoutes()
        );
        payoutToken.setTransferReverts(bob, false);
        distributor.transferPendingPayout(address(payoutToken), bob);
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(distributor.pendingPayout(address(payoutToken), bob), 0, "debt remains paid");
        (, IRevenueDistributor.AssetRoute[] memory configured) = distributor.getAssetDistribution(
            address(payoutToken)
        );
        assertEq(configured.length, 0, "queued route update applied");
    }

    // Scenarios: QSAR-S07
    function testFuzz_whenTreasuryUpgradesToNoncollidingAddress_executionSucceeds(
        address executor_
    ) public {
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetRoutes(address(token), 0, _emptyRoutes());
        OlympusTreasury replacement = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(distributor.treasury(), address(replacement), "replacement Treasury cached");
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "route update applied"
        );
    }

    // Scenarios: QSAR-S03
    function testFuzz_whenQueuedRecipientBecomesTreasury_executionReverts(
        address executor_
    ) public {
        OlympusTreasury replacement = new OlympusTreasury(kernel);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: address(replacement), bps: 1});
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetRoutes(address(token), 0, routes);
        bytes32 key = _queuedKey(actionId, 0);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
                address(replacement)
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(configTimelock.pendingActionId(key), actionId, "failed action retains key");
        assertFalse(configTimelock.getQueuedAction(actionId).executed, "action remains live");
    }

    // Scenarios: QSAR-Q01
    function testFuzz_whenAssetKeyAlreadyOwned_secondRouteQueueReverts(
        bool sameValue_,
        bool useRevenueAdmin_
    ) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(proposer);
        uint64 actionId = configTimelock.queueSetAssetRoutes(address(token), 0, _emptyRoutes());
        bytes32 key = _queuedKey(actionId, 0);
        IRevenueDistributor.AssetRoute[] memory secondRoutes = _emptyRoutes();
        if (!sameValue_) {
            secondRoutes = new IRevenueDistributor.AssetRoute[](1);
            secondRoutes[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 1});
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                key,
                actionId
            )
        );
        vm.prank(proposer);
        configTimelock.queueSetAssetRoutes(address(token), 0, secondRoutes);

        assertEq(configTimelock.pendingActionId(key), actionId, "first action retains key");
    }

    /// @dev Queue a valid repurchase route; later dependency changes do not alter its guard hash.
    function _queueRepurchaseRoute(
        bool useRevenueAdmin_
    ) internal returns (MockYieldRepurchaseRecipient recipient, uint64 actionId, bytes32 key) {
        recipient = _activeYieldRecipient();
        recipient.setVaultConfig(address(token), address(token), true);
        vm.prank(admin);
        distributor.setYieldRecipient(address(recipient));
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(proposer);
        actionId = configTimelock.queueSetAssetRoutes(
            address(token),
            QUEUED_REPURCHASE_BPS,
            _emptyRoutes()
        );
        key = _queuedKey(actionId, 0);
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);
    }

    /// @dev A dependency rejection must retain the exact queued payload/key and leave RD unlisted.
    function _assertRepurchaseRouteRetained(uint64 actionId_, bytes32 key_) internal view {
        ITimelockBatchQueue.QueuedAction memory queued = configTimelock.getQueuedAction(actionId_);
        assertFalse(queued.executed, "failed execution remains retryable");
        assertFalse(queued.cancelled, "failed execution does not cancel action");
        assertEq(queued.actions.length, 1, "failed execution retains payload");
        assertEq(queued.actions[0].target, address(distributor), "failed execution retains target");
        assertEq(
            queued.actions[0].selector,
            IRevenueDistributor.setAssetRoutes.selector,
            "failed execution retains selector"
        );
        assertEq(
            queued.actions[0].payload,
            abi.encode(address(token), QUEUED_REPURCHASE_BPS, _emptyRoutes()),
            "failed execution retains exact parameters"
        );
        assertEq(configTimelock.pendingActionId(key_), actionId_, "failed execution retains key");
        (, bytes32 queuedHash) = configTimelock.getQueuedConfigState(actionId_, 0, 0);
        assertEq(
            distributor.assetDistributionHash(address(token)),
            queuedHash,
            "dependency drift does not stale guard"
        );
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.NeverListed),
            "failed execution leaves asset unlisted"
        );
        assertEq(
            distributor.totalPendingForTest(address(token)),
            0,
            "failed execution creates no liability"
        );
        assertEq(token.balanceOf(address(distributor)), 0, "failed execution changes no custody");
    }

    function _executeRestoredRepurchaseRoute(
        uint64 actionId_,
        bytes32 key_,
        address executor_
    ) internal {
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId_);
        (uint16 repurchaseBps, IRevenueDistributor.AssetRoute[] memory routes) = distributor
            .getAssetDistribution(address(token));
        assertEq(repurchaseBps, QUEUED_REPURCHASE_BPS, "retry applies repurchase BPS");
        assertEq(routes.length, 0, "retry applies exact empty configured routes");
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "retry activates asset"
        );
        assertTrue(configTimelock.getQueuedAction(actionId_).executed, "retry consumes action");
        assertEq(configTimelock.pendingActionId(key_), 0, "retry releases key");
    }

    // Scenarios: QSAR-S08.
    function test_givenQueuedRepurchase_whenYieldRecipientDisabled_revertsThenRetries(
        bool useRevenueAdmin_,
        address executor_
    ) public {
        (
            MockYieldRepurchaseRecipient recipient,
            uint64 actionId,
            bytes32 key
        ) = _queueRepurchaseRoute(useRevenueAdmin_);
        recipient.setEnabled(false);
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidYieldRecipient.selector,
                address(recipient)
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertEq(vm.getRecordedLogs().length, 0, "rejected execution emits no events");
        _assertRepurchaseRouteRetained(actionId, key);
        recipient.setEnabled(true);
        _executeRestoredRepurchaseRoute(actionId, key, executor_);
    }

    // Scenarios: QSAR-S09.
    function test_givenQueuedRepurchase_whenYieldRecipientInactive_revertsThenRetries(
        bool useRevenueAdmin_,
        address executor_
    ) public {
        (
            MockYieldRepurchaseRecipient recipient,
            uint64 actionId,
            bytes32 key
        ) = _queueRepurchaseRoute(useRevenueAdmin_);
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(recipient));
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidYieldRecipient.selector,
                address(recipient)
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertEq(vm.getRecordedLogs().length, 0, "rejected execution emits no events");
        _assertRepurchaseRouteRetained(actionId, key);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        _executeRestoredRepurchaseRoute(actionId, key, executor_);
    }

    // Scenarios: QSAR-S10.
    function test_givenQueuedRepurchase_whenYieldRecipientAssetUnsupported_revertsThenRetries(
        bool useRevenueAdmin_,
        address executor_
    ) public {
        (
            MockYieldRepurchaseRecipient recipient,
            uint64 actionId,
            bytes32 key
        ) = _queueRepurchaseRoute(useRevenueAdmin_);
        recipient.setVaultConfig(address(token), address(token), false);
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(recipient),
                address(token)
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertEq(vm.getRecordedLogs().length, 0, "rejected execution emits no events");
        _assertRepurchaseRouteRetained(actionId, key);
        recipient.setVaultConfig(address(token), address(token), true);
        _executeRestoredRepurchaseRoute(actionId, key, executor_);
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
