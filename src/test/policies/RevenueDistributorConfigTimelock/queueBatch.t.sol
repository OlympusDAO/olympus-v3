// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Scenario amounts stay inline for accounting clarity.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)

// Libraries
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IRevenueDistributorRescue} from "src/policies/interfaces/IRevenueDistributorRescue.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {RevenueDistributorConfigTimelockTest} from "./RevenueDistributorConfigTimelockTest.sol";

contract RevenueDistributorConfigTimelockQueueBatchTest is RevenueDistributorConfigTimelockTest {
    bytes4 internal constant INVALID_SELECTOR = 0xdeadbeef;

    /// @notice Rescue's four static ABI words must have exactly 128 bytes, before any preview call.
    /// @dev Retains the legacy truncated/trailing-payload proofs in the owning batch suite.
    function test_whenPendingRescuePayloadIsTruncatedOrHasTrailingWord_reverts() public {
        bytes memory canonical = abi.encode(address(token), alice, bob, uint256(4));
        bytes[2] memory invalid = [
            abi.encode(address(token)),
            bytes.concat(canonical, abi.encode(uint256(0)))
        ];
        for (uint256 i; i < invalid.length; ++i) {
            ITimelockBatchQueue.BatchAction[]
                memory actions = new ITimelockBatchQueue.BatchAction[](1);
            actions[0] = ITimelockBatchQueue.BatchAction(
                address(distributor),
                IRevenueDistributorRescue.rescuePendingPayout.selector,
                invalid[i]
            );
            uint64 next = configTimelock.nextActionId();
            vm.expectRevert(
                abi.encodeWithSelector(
                    IRevenueDistributorConfigTimelock
                        .RevenueDistributorConfigTimelock_InvalidAction
                        .selector,
                    address(distributor),
                    IRevenueDistributorRescue.rescuePendingPayout.selector
                )
            );
            vm.prank(admin);
            configTimelock.queueBatch(actions);
            assertEq(
                configTimelock.nextActionId(),
                next,
                "invalid static payload consumes no action ID"
            );
        }
    }

    // given queued rescue batch
    //   when later bucket paid before execution
    //     [X] it reverts with RevenueDistributor_InsufficientPendingDistribution
    //     [X] later stale bucket rolls back earlier surplus transfer
    //     [X] earlier surplus custody is restored
    //     [X] failed batch remains queued
    //     [X] ordinary payout remains settled
    // Scenarios: EXEC-I04
    function testFuzz_givenQueuedRescueBatch_whenLaterBucketPaidBeforeExecution_reverts(
        address executor_
    ) public {
        MockRevertingTransferToken pendingAsset = new MockRevertingTransferToken(18);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(admin);
        distributor.setAssetRoutes(address(pendingAsset), 0, routes);
        pendingAsset.mint(address(distributor), 10);
        pendingAsset.setTransferReverts(address(treasury), true);
        distributor.distribute(address(pendingAsset));
        token.mint(address(distributor), 9);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = ITimelockBatchQueue.BatchAction({
            target: address(distributor),
            selector: IRevenueDistributorRescue.rescue.selector,
            payload: abi.encode(address(token), bob)
        });
        actions[1] = ITimelockBatchQueue.BatchAction({
            target: address(distributor),
            selector: IRevenueDistributorRescue.rescuePendingPayout.selector,
            payload: abi.encode(address(pendingAsset), address(treasury), bob, uint256(1))
        });
        vm.prank(admin);
        uint64 actionId = configTimelock.queueBatch(actions);
        bytes32 actionBefore = keccak256(abi.encode(configTimelock.getQueuedAction(actionId)));
        (bytes32 firstKey, bytes32 firstHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        (bytes32 secondKey, bytes32 secondHash) = configTimelock.getQueuedConfigState(
            actionId,
            1,
            0
        );
        address firstDestination = configTimelock.getQueuedConfigDestination(actionId, 0);
        address secondDestination = configTimelock.getQueuedConfigDestination(actionId, 1);
        pendingAsset.setTransferReverts(address(treasury), false);
        distributor.transferPendingPayout(address(pendingAsset), address(treasury));
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorRescue
                    .RevenueDistributor_InsufficientPendingDistribution
                    .selector,
                address(pendingAsset),
                1,
                0
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertEq(token.balanceOf(bob), 0, "later stale bucket rolls back earlier surplus transfer");
        assertEq(token.balanceOf(address(distributor)), 9, "earlier surplus custody is restored");
        assertFalse(
            configTimelock.getQueuedAction(actionId).executed,
            "failed batch remains queued"
        );
        assertEq(pendingAsset.balanceOf(address(treasury)), 10, "ordinary payout remains settled");
        assertEq(
            keccak256(abi.encode(configTimelock.getQueuedAction(actionId))),
            actionBefore,
            "failed batch retains action"
        );
        assertEq(configTimelock.pendingActionId(firstKey), actionId, "first key remains owned");
        assertEq(configTimelock.pendingActionId(secondKey), actionId, "second key remains owned");
        (, bytes32 firstHashAfter) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        (, bytes32 secondHashAfter) = configTimelock.getQueuedConfigState(actionId, 1, 0);
        assertEq(firstHashAfter, firstHash, "first guard hash retained");
        assertEq(secondHashAfter, secondHash, "second guard hash retained");
        assertEq(
            configTimelock.getQueuedConfigDestination(actionId, 0),
            firstDestination,
            "first destination retained"
        );
        assertEq(
            configTimelock.getQueuedConfigDestination(actionId, 1),
            secondDestination,
            "second destination retained"
        );
    }

    function _rescueAction(
        address asset_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            ITimelockBatchQueue.BatchAction({
                target: address(distributor),
                selector: IRevenueDistributorRescue.rescue.selector,
                payload: abi.encode(asset_, bob)
            });
    }

    function _routeAction(
        address asset_,
        address configuredRecipient_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        IRevenueDistributor.AssetRoute[] memory shares = new IRevenueDistributor.AssetRoute[](
            configuredRecipient_ == address(0) ? 0 : 1
        );
        if (configuredRecipient_ != address(0)) {
            shares[0] = IRevenueDistributor.AssetRoute({
                recipient: configuredRecipient_,
                bps: 2_000
            });
        }
        return
            ITimelockBatchQueue.BatchAction({
                target: address(distributor),
                selector: IRevenueDistributor.setAssetRoutes.selector,
                payload: abi.encode(asset_, uint16(0), shares)
            });
    }

    function _yieldAction(
        address recipient_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            ITimelockBatchQueue.BatchAction({
                target: address(distributor),
                selector: IRevenueDistributor.setYieldRecipient.selector,
                payload: abi.encode(recipient_)
            });
    }

    function _assetKey(address asset_) internal view returns (bytes32) {
        bytes32 localKey = keccak256(abi.encode(keccak256("REVENUE_DISTRIBUTOR_ASSET"), asset_));
        return keccak256(abi.encode(address(distributor), localKey));
    }

    // Scenarios: BATCH-L03
    function testFuzz_givenOperatorRotated_whenBatchQueued_reverts(bool useRevenueAdmin_) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _routeAction(address(token), address(0));
        vm.prank(admin);
        distributor.setConfigOperator(bob);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(configTimelock)
            )
        );
        vm.prank(proposer);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "unselected operator consumes no ID");
    }

    // Scenarios: BATCH-I07
    function testFuzz_givenDistributorDisabled_whenRescuePrecedesRoute_batchRevertsAtomically(
        bool useRevenueAdmin_
    ) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        token.mint(address(distributor), 1);
        MockERC20 routeToken = new MockERC20("Route", "ROUTE", 18);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _rescueAction(address(token));
        actions[1] = _routeAction(address(routeToken), address(0));
        vm.prank(admin);
        distributor.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(proposer);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "failed mixed batch consumes no ID");
        assertEq(token.balanceOf(address(distributor)), 1, "queue failure moves no funds");
    }

    // Scenarios: BATCH-I08, BATCH-I09
    function testFuzz_givenDistributorDisabled_whenRescuePrecedesExistingConfig_batchRevertsAtomically(
        bool useRevenueAdmin_,
        bool retireRoute_
    ) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        token.mint(address(distributor), 1);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _rescueAction(address(token));
        if (retireRoute_) {
            MockERC20 routeToken = new MockERC20("Route", "ROUTE", 18);
            _activateAsset(address(routeToken));
            actions[1] = ITimelockBatchQueue.BatchAction({
                target: address(distributor),
                selector: IRevenueDistributor.disableAssetRoutes.selector,
                payload: abi.encode(address(routeToken))
            });
        } else {
            actions[1] = _yieldAction(address(_activeYieldRecipient()));
        }
        vm.prank(emergency);
        distributor.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(proposer);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "failed mixed batch consumes no ID");
        assertEq(token.balanceOf(address(distributor)), 1, "queue failure moves no funds");
    }

    // Scenarios: QBATCH-V01
    function testFuzz_whenLiveBatchRead_returnsExactSubActionsAndRejectsInvalidIndex(
        address caller_,
        uint256 validIndex_,
        bool maximumIndex_
    ) public {
        MockERC20 otherToken = new MockERC20("Other", "OTHER", 18);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _routeAction(address(token), address(0));
        actions[1] = _routeAction(address(otherToken), address(0));
        vm.prank(admin);
        uint64 actionId = configTimelock.queueBatch(actions);
        validIndex_ = bound(validIndex_, 0, actions.length - 1);

        vm.prank(caller_);
        (address target, bytes4 selector, bytes memory payload) = configTimelock.getQueuedSubAction(
            actionId,
            validIndex_
        );
        assertEq(target, actions[validIndex_].target, "target matches queued action");
        assertEq(selector, actions[validIndex_].selector, "selector matches queued action");
        assertEq(
            keccak256(payload),
            keccak256(actions[validIndex_].payload),
            "payload matches queued action"
        );

        uint256 invalidIndex = maximumIndex_ ? type(uint256).max : actions.length;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_SubActionIndexOutOfBounds.selector,
                actionId,
                invalidIndex,
                actions.length
            )
        );
        vm.prank(caller_);
        configTimelock.getQueuedSubAction(actionId, invalidIndex);
    }

    // Scenarios: QBATCH-V02
    function testFuzz_whenQueuedConfigRead_returnsExactStateAndDefaults(
        address caller_,
        bool maximumIndex_
    ) public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _routeAction(address(token), address(0));
        vm.prank(admin);
        uint64 actionId = configTimelock.queueBatch(actions);
        (bytes32 expectedKey, bytes32 expectedHash) = configTimelock.getQueuedConfigState(
            actionId,
            0,
            0
        );

        vm.startPrank(caller_);
        assertEq(configTimelock.getQueuedConfigStateCount(actionId, 0), 1, "one guard stored");
        assertEq(
            configTimelock.getQueuedConfigDestination(actionId, 0),
            address(distributor),
            "guard destination matches distributor"
        );
        (bytes32 key, bytes32 stateHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        assertEq(key, expectedKey, "guard key matches queued key");
        assertEq(stateHash, expectedHash, "guard hash matches queued hash");
        assertEq(configTimelock.getQueuedConfigStateCount(0, 0), 0, "unknown action has no guards");
        assertEq(
            configTimelock.getQueuedConfigDestination(0, 0),
            address(0),
            "unknown action has no destination"
        );

        uint256 invalidIndex = maximumIndex_ ? type(uint256).max : 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue
                    .IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds
                    .selector,
                actionId,
                0,
                invalidIndex,
                1
            )
        );
        configTimelock.getQueuedConfigState(actionId, 0, invalidIndex);
        vm.stopPrank();
    }

    // Scenarios: BATCH-I02, BATCH-I11
    function testFuzz_whenFirstActionTargetOrSelectorUnsupported_reverts(
        bool invalidTarget_,
        bool useRevenueAdmin_
    ) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        address target = invalidTarget_ ? address(token) : address(distributor);
        bytes4 selector = invalidTarget_
            ? IRevenueDistributor.setAssetRoutes.selector
            : INVALID_SELECTOR;
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = ITimelockBatchQueue.BatchAction(target, selector, "");

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_InvalidAction
                    .selector,
                target,
                selector
            )
        );
        vm.prank(proposer);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "invalid action consumes no ID");
    }

    // Scenarios: BATCH-I12
    function testFuzz_whenLaterActionUnsupported_rollsBackEarlierKey(bool useRevenueAdmin_) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _routeAction(address(token), address(0));
        actions[1] = ITimelockBatchQueue.BatchAction(address(distributor), INVALID_SELECTOR, "");

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_InvalidAction
                    .selector,
                address(distributor),
                INVALID_SELECTOR
            )
        );
        vm.prank(proposer);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "invalid later action consumes no ID");
        vm.prank(admin);
        assertEq(
            configTimelock.queueSetAssetRoutes(address(token), 0, _emptyRoutes()),
            1,
            "rolled-back key can be acquired"
        );
    }

    // Scenarios: BATCH-I03
    function testFuzz_whenStaticPayloadLengthIsInvalid_reverts(
        uint8 selectorIndex_,
        bool trailingWord_,
        bool laterPosition_,
        bool useRevenueAdmin_
    ) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        bytes4[4] memory selectors = [
            IRevenueDistributor.disableAssetRoutes.selector,
            IRevenueDistributor.setYieldRecipient.selector,
            IRevenueDistributorRescue.rescue.selector,
            IRevenueDistributorRescue.rescuePendingPayout.selector
        ];
        bytes4 selector = selectors[bound(selectorIndex_, 0, selectors.length - 1)];
        uint256 canonicalWords = selector == IRevenueDistributorRescue.rescuePendingPayout.selector
            ? 4
            : selector == IRevenueDistributorRescue.rescue.selector
            ? 2
            : 1;
        bytes memory payload = trailingWord_
            ? new bytes((canonicalWords + 1) * 32)
            : new bytes((canonicalWords - 1) * 32);
        uint256 malformedIndex = laterPosition_ ? 1 : 0;
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](
            laterPosition_ ? 2 : 1
        );
        if (laterPosition_) actions[0] = _rescueAction(address(token));
        actions[malformedIndex] = ITimelockBatchQueue.BatchAction(
            address(distributor),
            selector,
            payload
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_InvalidAction
                    .selector,
                address(distributor),
                selector
            )
        );
        vm.prank(proposer);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "malformed payload consumes no ID");
        assertEq(
            configTimelock.pendingActionId(_assetKey(address(token))),
            0,
            "earlier key rolls back"
        );
    }

    // Scenarios: BATCH-I04
    function testFuzz_whenRoutePayloadEncodingIsInvalid_reverts(
        bool useRevenueAdmin_,
        bool rawMalformed_,
        bool shiftedOffset_
    ) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        bytes memory payload;
        if (rawMalformed_) {
            payload = abi.encode(address(token), uint16(0));
        } else if (shiftedOffset_) {
            payload = abi.encode(address(token), uint16(0), uint256(128), uint256(0), uint256(0));
        } else {
            payload = bytes.concat(
                abi.encode(address(token), uint16(0), routes),
                abi.encode(uint256(0))
            );
        }
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = ITimelockBatchQueue.BatchAction({
            target: address(distributor),
            selector: IRevenueDistributor.setAssetRoutes.selector,
            payload: payload
        });

        if (rawMalformed_) {
            // Solidity's memory ABI decoder exposes no stable custom error for a missing dynamic offset.
            vm.expectRevert();
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IRevenueDistributorConfigTimelock
                        .RevenueDistributorConfigTimelock_InvalidAction
                        .selector,
                    address(distributor),
                    IRevenueDistributor.setAssetRoutes.selector
                )
            );
        }
        vm.prank(proposer);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "invalid route encoding consumes no ID");
        assertEq(
            configTimelock.pendingActionId(_assetKey(address(token))),
            0,
            "invalid encoding acquires no key"
        );
    }

    // Scenarios: BATCH-I05
    function testFuzz_whenAddressWordHasDirtyUpperBits_revertsAtQueue(
        uint8 selectorIndex_,
        bool useRevenueAdmin_
    ) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        bytes4[5] memory selectors = [
            IRevenueDistributor.setAssetRoutes.selector,
            IRevenueDistributor.disableAssetRoutes.selector,
            IRevenueDistributor.setYieldRecipient.selector,
            IRevenueDistributorRescue.rescue.selector,
            IRevenueDistributorRescue.rescuePendingPayout.selector
        ];
        bytes4 selector = selectors[bound(selectorIndex_, 0, selectors.length - 1)];
        uint256 dirtyWord = uint256(uint160(address(token))) | (uint256(1) << 160);
        bytes memory payload;
        if (selector == IRevenueDistributor.setAssetRoutes.selector) {
            payload = abi.encode(dirtyWord, uint16(0), uint256(96), uint256(0));
        } else if (selector == IRevenueDistributorRescue.rescue.selector) {
            payload = abi.encode(dirtyWord, bob);
        } else if (selector == IRevenueDistributorRescue.rescuePendingPayout.selector) {
            payload = abi.encode(dirtyWord, alice, bob, uint256(1));
        } else {
            payload = abi.encode(dirtyWord);
        }
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = ITimelockBatchQueue.BatchAction(address(distributor), selector, payload);

        // Solidity's memory ABI decoder exposes no stable custom error for a dirty address word.
        vm.expectRevert();
        vm.prank(proposer);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "dirty address consumes no ID");
    }

    // Scenarios: BATCH-Q04
    function testFuzz_whenTwoYieldActionsShareGlobalKey_batchReverts(bool useRevenueAdmin_) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _yieldAction(address(0));
        actions[1] = _yieldAction(address(0));
        uint64 actionId = configTimelock.nextActionId();
        bytes32 localKey = keccak256("REVENUE_DISTRIBUTOR_YIELD_RECIPIENT");
        bytes32 key = keccak256(abi.encode(address(distributor), localKey));

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                key,
                actionId
            )
        );
        vm.prank(proposer);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), actionId, "conflicting batch consumes no ID");
        assertEq(configTimelock.pendingActionId(key), 0, "rolled-back global key is free");
    }

    // Scenarios: RDT-Q02
    function testFuzz_whenReachableAssetActionsShareKey_batchReverts(
        uint8 pairKind_,
        bool useRevenueAdmin_
    ) public {
        pairKind_ = uint8(bound(pairKind_, 0, 6));
        address proposer = _permittedProposer(useRevenueAdmin_);
        MockERC20 asset = new MockERC20("Managed", "MGT", 18);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);

        if (pairKind_ == 6) {
            asset.mint(address(distributor), 2);
            actions[0] = _rescueAction(address(asset));
            actions[1] = _rescueAction(address(asset));
        } else {
            IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
                1
            );
            routes[0] = IRevenueDistributor.AssetRoute(alice, 10_000);
            vm.prank(admin);
            distributor.setAssetRoutes(address(asset), 0, routes);
            asset.mint(address(distributor), 2);
            distributor.seedPendingForTest(address(asset), alice, 2, 0, 0);

            ITimelockBatchQueue.BatchAction memory setRoute = _routeAction(
                address(asset),
                address(0)
            );
            ITimelockBatchQueue.BatchAction memory disableRoute = ITimelockBatchQueue.BatchAction({
                target: address(distributor),
                selector: IRevenueDistributor.disableAssetRoutes.selector,
                payload: abi.encode(address(asset))
            });
            ITimelockBatchQueue.BatchAction memory rescuePending = ITimelockBatchQueue.BatchAction({
                target: address(distributor),
                selector: IRevenueDistributorRescue.rescuePendingPayout.selector,
                payload: abi.encode(address(asset), alice, bob, uint256(1))
            });
            if (pairKind_ == 0) (actions[0], actions[1]) = (setRoute, disableRoute);
            if (pairKind_ == 1) (actions[0], actions[1]) = (disableRoute, setRoute);
            if (pairKind_ == 2) (actions[0], actions[1]) = (setRoute, rescuePending);
            if (pairKind_ == 3) (actions[0], actions[1]) = (rescuePending, setRoute);
            if (pairKind_ == 4) (actions[0], actions[1]) = (disableRoute, rescuePending);
            if (pairKind_ == 5) (actions[0], actions[1]) = (rescuePending, disableRoute);
        }

        uint64 expectedOwner = configTimelock.nextActionId();
        bytes32 key = _assetKey(address(asset));
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                key,
                expectedOwner
            )
        );
        vm.prank(proposer);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), expectedOwner, "conflicting batch consumes no ID");
        assertEq(configTimelock.pendingActionId(key), 0, "conflicting batch leaves key free");
    }

    function _conflictingBatch(
        address recipient_,
        bool routeFirst_
    ) internal view returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](2);
        ITimelockBatchQueue.BatchAction memory route = _routeAction(address(token), recipient_);
        ITimelockBatchQueue.BatchAction memory yieldChange = ITimelockBatchQueue.BatchAction({
            target: address(distributor),
            selector: IRevenueDistributor.setYieldRecipient.selector,
            payload: abi.encode(recipient_)
        });
        actions[0] = routeFirst_ ? route : yieldChange;
        actions[1] = routeFirst_ ? yieldChange : route;
    }

    // given unauthorized caller
    //   when batch queued
    //     [X] it reverts with NotAuthorised
    //     [X] unauthorized caller queues no batch
    // Scenarios: BATCH-A01
    function test_givenUnauthorizedCaller_whenBatchQueued_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != alice);
        _permittedProposer(true);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _rescueAction(address(token));

        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "unauthorized caller queues no batch");
    }

    // Scenarios: BATCH-A01
    function test_whenKnownUnauthorizedIdentitiesQueueBatch_reverts() public {
        _permittedProposer(true);
        address[] memory callers = new address[](4);
        callers[0] = emergency;
        callers[1] = bob;
        callers[2] = address(configTimelock);
        callers[3] = address(distributor);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _rescueAction(address(token));

        for (uint256 i; i < callers.length; ++i) {
            vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
            vm.prank(callers[i]);
            configTimelock.queueBatch(actions);
        }
        assertEq(configTimelock.nextActionId(), 1, "known unauthorized callers queue no batch");
    }

    // given disabled
    //   when batch queued
    //     [X] it reverts with NotEnabled
    //     [X] disabled timelock queues no batch
    // Scenarios: BATCH-L01
    function testFuzz_givenDisabled_whenBatchQueued_reverts(bool useRevenueAdmin_) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _rescueAction(address(token));
        bytes32 key = _assetKey(address(token));
        _disableTimelock();

        vm.prank(proposer);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "disabled timelock consumes no ID");
        assertEq(configTimelock.pendingActionId(key), 0, "disabled timelock acquires no key");

        assertEq(configTimelock.nextActionId(), 1, "disabled timelock queues no batch");
    }

    // given re-enabled
    //   when batch queued
    //     [X] re-enabled timelock queues batch
    function test_givenReEnabled_whenBatchQueued() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _rescueAction(address(token));
        vm.startPrank(admin);
        configTimelock.disable("");
        configTimelock.reEnable();

        uint64 actionId = configTimelock.queueBatch(actions);
        vm.stopPrank();

        assertEq(actionId, 1, "re-enabled timelock queues batch");
    }

    // given policy inactive
    //   when batch queued
    //     [X] it reverts with RevenueDistributorConfigTimelock_PolicyInactive
    //     [X] inactive timelock queues no batch
    // Scenarios: BATCH-L02
    function testFuzz_givenPolicyInactive_whenBatchQueued_reverts(bool useRevenueAdmin_) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _rescueAction(address(token));
        bytes32 key = _assetKey(address(token));
        _deactivateTimelock();

        vm.prank(proposer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_PolicyInactive
                    .selector,
                address(configTimelock)
            )
        );
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "inactive timelock consumes no ID");
        assertEq(configTimelock.pendingActionId(key), 0, "inactive timelock acquires no key");

        assertEq(configTimelock.nextActionId(), 1, "inactive timelock queues no batch");
    }

    // given policy reactivated
    //   when batch queued
    //     [X] reactivated timelock queues batch
    function test_givenPolicyReactivated_whenBatchQueued() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _rescueAction(address(token));
        vm.startPrank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
        kernel.executeAction(Actions.ActivatePolicy, address(configTimelock));

        uint64 actionId = configTimelock.queueBatch(actions);
        vm.stopPrank();

        assertEq(actionId, 1, "reactivated timelock queues batch");
    }

    // when empty batch queued
    //   [X] it reverts with ITimelockBatchQueue_BatchEmpty
    // Scenarios: BATCH-I01
    function testFuzz_whenEmptyBatchQueued_reverts(
        bool useRevenueAdmin_,
        uint8 lifecycleFault_
    ) public {
        address proposer = _permittedProposer(useRevenueAdmin_);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](0);
        lifecycleFault_ = uint8(bound(lifecycleFault_, 0, 2));
        if (lifecycleFault_ == 1) _disableTimelock();
        if (lifecycleFault_ == 2) _deactivateTimelock();

        vm.prank(proposer);
        vm.expectRevert(ITimelockBatchQueue.ITimelockBatchQueue_BatchEmpty.selector);
        configTimelock.queueBatch(actions);
        assertEq(configTimelock.nextActionId(), 1, "empty batch consumes no ID");
    }

    // when maximum batch queued
    //   [X] maximum-size batch queues
    // Scenarios: BATCH-P01
    function test_whenMaximumBatchQueued() public {
        uint256 maximum = 15;
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](
            maximum
        );
        for (uint256 i; i < maximum; ++i) {
            MockERC20 rescueToken = new MockERC20("Rescue", "REC", 18);
            actions[i] = _rescueAction(address(rescueToken));
        }

        vm.prank(admin);
        uint64 actionId = configTimelock.queueBatch(actions);

        assertEq(actionId, 1, "maximum-size batch queues");
    }

    // Scenarios: BATCH-P01
    function testFuzz_whenValidSizedBatchQueued_storesEveryActionAndGuard(
        uint8 length_,
        bool useRevenueAdmin_
    ) public {
        uint256 length = bound(length_, 1, 15);
        address proposer = _permittedProposer(useRevenueAdmin_);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](
            length
        );
        address[] memory assets = new address[](length);
        for (uint256 i; i < length; ++i) {
            assets[i] = address(new MockERC20("Rescue", "REC", 18));
            actions[i] = _rescueAction(assets[i]);
        }

        uint64 expectedId = configTimelock.nextActionId();
        vm.prank(proposer);
        uint64 actionId = configTimelock.queueBatch(actions);

        assertEq(actionId, expectedId, "batch receives next action ID");
        assertEq(configTimelock.nextActionId(), expectedId + 1, "batch consumes one action ID");
        assertEq(
            configTimelock.getQueuedActionLength(actionId),
            length,
            "stored action count matches input"
        );
        for (uint256 i; i < length; ++i) {
            (address target, bytes4 selector, bytes memory payload) = configTimelock
                .getQueuedSubAction(actionId, i);
            assertEq(target, address(distributor), "stored target matches");
            assertEq(
                selector,
                IRevenueDistributorRescue.rescue.selector,
                "stored selector matches"
            );
            assertEq(keccak256(payload), keccak256(actions[i].payload), "stored payload matches");
            bytes32 key = _assetKey(assets[i]);
            assertEq(
                configTimelock.getQueuedConfigStateCount(actionId, i),
                1,
                "one guard stored per rescue"
            );
            (bytes32 storedKey, bytes32 stateHash) = configTimelock.getQueuedConfigState(
                actionId,
                i,
                0
            );
            assertEq(storedKey, key, "stored guard key matches asset");
            assertEq(
                stateHash,
                keccak256(abi.encode(IRevenueDistributor.AssetState.NeverListed)),
                "guard hash matches"
            );
            assertEq(configTimelock.pendingActionId(key), actionId, "asset key belongs to batch");
        }
    }

    // when batch exceeds maximum
    //   [X] it reverts with ITimelockBatchQueue_BatchTooLarge
    // Scenarios: BATCH-I10
    function testFuzz_whenBatchExceedsMaximum_reverts(
        bool useRevenueAdmin_,
        uint8 lifecycleFault_
    ) public {
        uint256 maximum = 15;
        address proposer = _permittedProposer(useRevenueAdmin_);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](
            maximum + 1
        );
        lifecycleFault_ = uint8(bound(lifecycleFault_, 0, 2));
        if (lifecycleFault_ == 1) _disableTimelock();
        if (lifecycleFault_ == 2) _deactivateTimelock();

        vm.prank(proposer);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_BatchTooLarge.selector,
                maximum + 1,
                maximum
            )
        );
        configTimelock.queueBatch(actions);
        assertEq(configTimelock.nextActionId(), 1, "oversized batch consumes no ID");
    }

    // given a queued route names the proposed yield recipient
    //   when the recipient change is queued separately and the route executes first
    //     [X] the recipient change can queue but reverts when executed
    function test_givenQueuedRoute_whenConflictingYieldQueued_whenRouteExecutesFirst_yieldReverts()
        public
    {
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        IRevenueDistributor.AssetRoute[] memory shares = new IRevenueDistributor.AssetRoute[](1);
        shares[0] = IRevenueDistributor.AssetRoute({recipient: address(recipient), bps: 2_000});

        vm.prank(admin);
        uint64 routeId = configTimelock.queueSetAssetRoutes(address(token), 0, shares);
        vm.prank(admin);
        uint64 yieldId = configTimelock.queueSetYieldRecipient(address(recipient));
        assertEq(yieldId, routeId + 1, "conflicting yield change can queue");

        vm.warp(block.timestamp + configTimelock.timelockDelay());
        configTimelock.executeQueuedAction(routeId);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_DuplicateRecipient.selector,
                address(recipient)
            )
        );
        configTimelock.executeQueuedAction(yieldId);

        assertEq(distributor.yieldRecipient(), address(0), "failed yield change is not applied");
        (uint16 repurchaseBps, IRevenueDistributor.AssetRoute[] memory configured) = distributor
            .getAssetDistribution(address(token));
        assertEq(repurchaseBps, 0, "earlier route has no repurchase share");
        assertEq(configured[0].recipient, address(recipient), "earlier route remains active");
    }

    // given a batch names the same address in its route and yield recipient
    //   when the route executes before the yield change
    //     [X] the later action reverts and the whole batch rolls back
    // Scenarios: EXEC-I03
    function testFuzz_givenConflictingRouteAndYield_whenRouteFirstBatchExecutes_revertsAtomically(
        address executor_
    ) public {
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        vm.prank(admin);
        uint64 actionId = configTimelock.queueBatch(_conflictingBatch(address(recipient), true));
        bytes32 actionBefore = keccak256(abi.encode(configTimelock.getQueuedAction(actionId)));
        (bytes32 firstKey, bytes32 firstHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        (bytes32 secondKey, bytes32 secondHash) = configTimelock.getQueuedConfigState(
            actionId,
            1,
            0
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_DuplicateRecipient.selector,
                address(recipient)
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.NeverListed),
            "route update rolled back"
        );
        assertEq(distributor.yieldRecipient(), address(0), "yield change rolled back");
        _assertBatchRetained(actionId, actionBefore, firstKey, firstHash, secondKey, secondHash);
    }

    // given a batch names the same address in its route and yield recipient
    //   when the yield change executes before the route
    //     [X] the route state hash changes and the whole batch rolls back
    // Scenarios: EXEC-I03
    function testFuzz_givenConflictingRouteAndYield_whenYieldFirstBatchExecutes_revertsAtomically(
        address executor_
    ) public {
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        vm.prank(admin);
        uint64 actionId = configTimelock.queueBatch(_conflictingBatch(address(recipient), false));
        bytes32 actionBefore = keccak256(abi.encode(configTimelock.getQueuedAction(actionId)));
        (bytes32 firstKey, bytes32 firstHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        (bytes32 key, bytes32 expectedHash) = configTimelock.getQueuedConfigState(actionId, 1, 0);
        IRevenueDistributor.AssetRoute[] memory emptyShares = new IRevenueDistributor.AssetRoute[](
            0
        );
        bytes32 changedHash = keccak256(
            abi.encode(
                IRevenueDistributor.AssetState.NeverListed,
                uint16(0),
                emptyShares,
                address(recipient)
            )
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId,
                uint256(1),
                key,
                expectedHash,
                changedHash
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.NeverListed),
            "route update rolled back"
        );
        assertEq(distributor.yieldRecipient(), address(0), "yield change rolled back");
        _assertBatchRetained(actionId, actionBefore, firstKey, firstHash, key, expectedHash);
    }

    // Scenarios: EXEC-I05
    function testFuzz_givenCompatibleRouteAndYield_whenBatchExecutesInSuppliedOrder(
        bool routeFirst_,
        address executor_
    ) public {
        MockYieldRepurchaseRecipient recipient = _activeYieldRecipient();
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        ITimelockBatchQueue.BatchAction memory route = _routeAction(address(token), bob);
        ITimelockBatchQueue.BatchAction memory yieldChange = _yieldAction(address(recipient));
        actions[0] = routeFirst_ ? route : yieldChange;
        actions[1] = routeFirst_ ? yieldChange : route;
        vm.prank(admin);
        uint64 actionId = configTimelock.queueBatch(actions);
        bytes32 actionBefore = keccak256(abi.encode(configTimelock.getQueuedAction(actionId)));
        (bytes32 firstKey, bytes32 firstHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        (bytes32 secondKey, bytes32 secondHash) = configTimelock.getQueuedConfigState(
            actionId,
            1,
            0
        );
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        if (routeFirst_) {
            vm.prank(executor_);
            configTimelock.executeQueuedAction(actionId);

            (, IRevenueDistributor.AssetRoute[] memory configured) = distributor
                .getAssetDistribution(address(token));
            assertEq(configured.length, 1, "route installed before yield change");
            assertEq(configured[0].recipient, bob, "compatible route recipient retained");
            assertEq(
                distributor.yieldRecipient(),
                address(recipient),
                "yield recipient installed second"
            );
            assertEq(configTimelock.pendingActionId(firstKey), 0, "first key released");
            assertEq(configTimelock.pendingActionId(secondKey), 0, "second key released");
        } else {
            IRevenueDistributor.AssetRoute[]
                memory emptyRoutes = new IRevenueDistributor.AssetRoute[](0);
            bytes32 changedHash = keccak256(
                abi.encode(
                    IRevenueDistributor.AssetState.NeverListed,
                    uint16(0),
                    emptyRoutes,
                    address(recipient)
                )
            );
            vm.expectRevert(
                abi.encodeWithSelector(
                    IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                    actionId,
                    uint256(1),
                    secondKey,
                    secondHash,
                    changedHash
                )
            );
            vm.prank(executor_);
            configTimelock.executeQueuedAction(actionId);

            assertEq(distributor.yieldRecipient(), address(0), "yield-first change rolled back");
            assertEq(
                uint8(distributor.assetState(address(token))),
                0,
                "later route remains unapplied"
            );
            _assertBatchRetained(
                actionId,
                actionBefore,
                firstKey,
                firstHash,
                secondKey,
                secondHash
            );
        }
    }

    // given an asset route is already queued
    //   when a second route for the same asset is queued
    //     [X] its per-asset key rejects the second action
    function test_givenQueuedRoute_whenSameAssetRouteQueued_reverts() public {
        IRevenueDistributor.AssetRoute[] memory shares = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetRoutes(address(token), 0, shares);
        (bytes32 key, bytes32 expectedHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        assertEq(
            expectedHash,
            distributor.assetDistributionHash(address(token)),
            "route state was captured"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                key,
                actionId
            )
        );
        vm.prank(admin);
        // The call must revert, so its return value is unavailable.
        // forge-lint: disable-next-line(unused-return)
        configTimelock.queueSetAssetRoutes(address(token), 0, shares);
    }

    // given an asset route is already queued
    //   when a route for another asset is queued
    //     [X] both assets retain independent keys
    // Scenarios: BATCH-Q02
    function test_givenQueuedRoute_whenOtherAssetRouteQueued() public {
        MockERC20 otherToken = new MockERC20("Other Revenue", "OREV", 18);
        vm.label(address(otherToken), "Other revenue token");
        IRevenueDistributor.AssetRoute[] memory shares = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(admin);
        uint64 first = configTimelock.queueSetAssetRoutes(address(token), 0, shares);
        vm.prank(admin);
        uint64 second = configTimelock.queueSetAssetRoutes(address(otherToken), 0, shares);
        assertEq(second, first + 1, "other asset queues independently");
        bytes32 firstKey = _queuedKey(first, 0);
        bytes32 secondKey = _queuedKey(second, 0);
        assertEq(configTimelock.pendingActionId(firstKey), first, "first asset retains its key");
        assertEq(
            configTimelock.pendingActionId(secondKey),
            second,
            "second asset owns independent key"
        );
        assertEq(configTimelock.getQueuedActionLength(first), 1, "first queue retains its action");
        assertEq(configTimelock.getQueuedActionLength(second), 1, "second queue stores its action");
        assertEq(
            uint8(distributor.assetState(address(token))),
            0,
            "first route not applied at queue time"
        );
        assertEq(
            uint8(distributor.assetState(address(otherToken))),
            0,
            "second route not applied at queue time"
        );
    }

    // given two changes to one asset in one batch
    //   when the batch is queued
    //     [X] the second action conflicts on the per-asset key
    function test_givenTwoSameAssetRoutes_whenBatchQueued_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _routeAction(address(token), address(0));
        actions[1] = _routeAction(address(token), address(0));
        uint64 actionId = configTimelock.nextActionId();
        bytes32 localKey = keccak256(
            abi.encode(keccak256("REVENUE_DISTRIBUTOR_ASSET"), address(token))
        );
        bytes32 key = keccak256(abi.encode(address(distributor), localKey));

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                key,
                actionId
            )
        );
        vm.prank(admin);
        // The call must revert, so its return value is unavailable.
        // forge-lint: disable-next-line(unused-return)
        configTimelock.queueBatch(actions);
    }

    // given two different asset routes in one batch
    //   when the batch executes after the delay
    //     [X] both assets receive their routes
    // Scenarios: EXEC-P02
    function testFuzz_givenTwoDifferentAssetRoutes_whenBatchExecutes(address executor_) public {
        MockERC20 otherToken = new MockERC20("Other Revenue", "OREV", 18);
        vm.label(address(otherToken), "Other revenue token");
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _routeAction(address(token), address(0));
        actions[1] = _routeAction(address(otherToken), address(0));

        vm.prank(admin);
        uint64 actionId = configTimelock.queueBatch(actions);
        bytes32 firstKey = _queuedKey(actionId, 0);
        bytes32 secondKey = _queuedKey(actionId, 1);
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        vm.expectEmit(true, true, true, true, address(configTimelock));
        emit ITimelockBatchQueue.TimelockSubActionExecuted(
            actionId,
            address(distributor),
            IRevenueDistributor.setAssetRoutes.selector,
            0
        );
        vm.expectEmit(true, true, true, true, address(configTimelock));
        emit ITimelockBatchQueue.TimelockSubActionExecuted(
            actionId,
            address(distributor),
            IRevenueDistributor.setAssetRoutes.selector,
            1
        );
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit ITimelockBatchQueue.TimelockActionExecuted(actionId, executor_);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "first route activates"
        );
        assertEq(
            uint8(distributor.assetState(address(otherToken))),
            uint8(IRevenueDistributor.AssetState.Active),
            "second route activates"
        );
        assertEq(configTimelock.pendingActionId(firstKey), 0, "first key released");
        assertEq(configTimelock.pendingActionId(secondKey), 0, "second key released");
    }

    // Scenarios: EXEC-C01
    function testFuzz_whenRescueTokenCallbacksIntoExecution_preservesAtomicity(
        bool sameAction_,
        bool propagateFailure_,
        address executor_
    ) public {
        ReentrantFeeToken callbackAsset = new ReentrantFeeToken();
        callbackAsset.mint(address(distributor), 10);
        vm.prank(admin);
        uint64 outerId = configTimelock.queueRescue(address(callbackAsset), bob);
        bytes32 outerKey = _queuedKey(outerId, 0);

        MockERC20 routeAsset = new MockERC20("Callback route", "CBR", 18);
        uint64 nestedId = outerId;
        bytes32 nestedKey;
        if (!sameAction_) {
            vm.prank(admin);
            nestedId = configTimelock.queueSetAssetRoutes(address(routeAsset), 0, _emptyRoutes());
            nestedKey = _queuedKey(nestedId, 0);
        }
        callbackAsset.setCallbackFrom(
            address(distributor),
            address(configTimelock),
            abi.encodeCall(configTimelock.executeQueuedAction, (nestedId))
        );
        callbackAsset.setBubbleCallbackFailure(propagateFailure_);
        vm.warp(configTimelock.getQueuedAction(outerId).executableAt);

        if (propagateFailure_) {
            vm.expectRevert(abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector));
        }
        vm.prank(executor_);
        configTimelock.executeQueuedAction(outerId);

        if (propagateFailure_) {
            assertFalse(
                configTimelock.getQueuedAction(outerId).executed,
                "propagated callback retains outer action"
            );
            assertEq(
                configTimelock.pendingActionId(outerKey),
                outerId,
                "propagated callback retains outer key"
            );
            assertEq(
                callbackAsset.balanceOf(address(distributor)),
                10,
                "propagated callback restores custody"
            );
            assertEq(callbackAsset.balanceOf(bob), 0, "propagated callback pays nothing");
            assertTrue(callbackAsset.callbackEnabled(), "propagated callback state rolls back");
        } else {
            bytes4 expectedSelector = sameAction_
                ? ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector
                : ReentrancyGuard.ReentrancyGuardReentrantCall.selector;
            assertFalse(callbackAsset.callbackSucceeded(), "nested execution is rejected");
            assertEq(
                callbackAsset.callbackRevertSelector(),
                expectedSelector,
                "nested failure selector matches"
            );
            assertTrue(
                configTimelock.getQueuedAction(outerId).executed,
                "caught callback completes outer action"
            );
            assertEq(
                configTimelock.pendingActionId(outerKey),
                0,
                "caught callback releases outer key"
            );
            assertEq(
                callbackAsset.balanceOf(address(distributor)),
                0,
                "outer rescue spends custody once"
            );
            assertEq(callbackAsset.balanceOf(bob), 10, "outer rescue pays once");
        }
        if (!sameAction_) {
            assertFalse(
                configTimelock.getQueuedAction(nestedId).executed,
                "nested configuration stays live"
            );
            assertEq(
                configTimelock.pendingActionId(nestedKey),
                nestedId,
                "nested key remains owned"
            );
            assertEq(
                uint8(distributor.assetState(address(routeAsset))),
                0,
                "nested route is not installed"
            );
        }
    }

    function _assertBatchRetained(
        uint64 actionId_,
        bytes32 actionBefore_,
        bytes32 firstKey_,
        bytes32 firstHash_,
        bytes32 secondKey_,
        bytes32 secondHash_
    ) internal view {
        assertEq(
            keccak256(abi.encode(configTimelock.getQueuedAction(actionId_))),
            actionBefore_,
            "failed batch retains action"
        );
        assertEq(configTimelock.pendingActionId(firstKey_), actionId_, "first key remains owned");
        assertEq(configTimelock.pendingActionId(secondKey_), actionId_, "second key remains owned");
        (, bytes32 firstHashAfter) = configTimelock.getQueuedConfigState(actionId_, 0, 0);
        (, bytes32 secondHashAfter) = configTimelock.getQueuedConfigState(actionId_, 1, 0);
        assertEq(firstHashAfter, firstHash_, "first guard hash retained");
        assertEq(secondHashAfter, secondHash_, "second guard hash retained");
    }

    // given a disabled distributor and revenue distributor admin
    //   when an unmanaged rescue batch matures
    //     [X] the batch executes and sends unreserved funds to Treasury
    // Scenarios: BATCH-P02
    function testFuzz_givenDistributorDisabled_whenPermittedCallerQueuesRescueBatch(
        bool useRevenueAdmin_,
        bool includePending_
    ) public {
        token.mint(address(distributor), 9);
        MockERC20 pendingAsset = new MockERC20("Pending", "PEND", 18);
        if (includePending_) {
            IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
                1
            );
            routes[0] = IRevenueDistributor.AssetRoute(alice, 10_000);
            vm.prank(admin);
            distributor.setAssetRoutes(address(pendingAsset), 0, routes);
            pendingAsset.mint(address(distributor), 7);
            distributor.seedPendingForTest(address(pendingAsset), alice, 7, 0, 0);
        }
        vm.prank(emergency);
        distributor.disable("");
        address proposer = _permittedProposer(useRevenueAdmin_);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](
            includePending_ ? 2 : 1
        );
        actions[0] = ITimelockBatchQueue.BatchAction({
            target: address(distributor),
            selector: IRevenueDistributorRescue.rescue.selector,
            payload: abi.encode(address(token), address(treasury))
        });
        if (includePending_) {
            actions[1] = ITimelockBatchQueue.BatchAction({
                target: address(distributor),
                selector: IRevenueDistributorRescue.rescuePendingPayout.selector,
                payload: abi.encode(address(pendingAsset), alice, bob, uint256(4))
            });
        }
        vm.prank(proposer);
        uint64 actionId = configTimelock.queueBatch(actions);
        assertEq(token.balanceOf(address(treasury)), 0, "queue moves no surplus");
        assertEq(pendingAsset.balanceOf(bob), 0, "queue moves no pending payout");
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        vm.prank(bob);
        configTimelock.executeQueuedAction(actionId);
        assertEq(token.balanceOf(address(treasury)), 9, "batch rescue pays Treasury");
        if (includePending_) {
            assertEq(pendingAsset.balanceOf(bob), 4, "batch rescue pays pending destination");
            assertEq(
                pendingAsset.balanceOf(address(distributor)),
                3,
                "remaining pending custody retained"
            );
            _assertPendingPayouts(address(pendingAsset), alice, 3, 0, 0);
        }
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
