// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Expected-revert queue calls cannot use their returned action IDs.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {RevenueDistributorConfigTimelockTest} from "src/test/policies/RevenueDistributorConfigTimelock/RevenueDistributorConfigTimelockTest.sol";

contract RevenueDistributorConfigTimelockQueueDisableAssetRoutesTest is
    RevenueDistributorConfigTimelockTest
{
    // queueDisableAssetRoutes
    // given an asset has never been listed
    //  when either permitted proposer queues its retirement
    //   then queue-time validation rejects it without consuming state
    // Scenarios: QDAR-I01
    function test_givenNeverListedAsset_whenDisableQueued_revertsAtQueue(
        bool useRevenueAdmin_
    ) public {
        address proposer = _permittedProposer(useRevenueAdmin_);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_AssetNotActive.selector,
                address(token)
            )
        );
        vm.prank(proposer);
        configTimelock.queueDisableAssetRoutes(address(token));

        assertEq(configTimelock.nextActionId(), 1, "invalid retirement should not consume ID");
    }

    // queueDisableAssetRoutes
    // given an asset has already been retired
    //  when either permitted proposer queues another retirement
    //   then queue-time validation rejects it without consuming state
    // Scenarios: QDAR-I02
    function test_givenRetiredAsset_whenDisableQueued_revertsAtQueue(bool useRevenueAdmin_) public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.startPrank(admin);
        distributor.setAssetRoutes(address(token), 0, routes);
        distributor.disableAssetRoutes(address(token));
        vm.stopPrank();
        address proposer = _permittedProposer(useRevenueAdmin_);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_AssetNotActive.selector,
                address(token)
            )
        );
        vm.prank(proposer);
        configTimelock.queueDisableAssetRoutes(address(token));

        assertEq(configTimelock.nextActionId(), 1, "invalid retirement should not consume ID");
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Retired),
            "invalid retirement should preserve retired state"
        );
    }

    // Scenarios: QDAR-A01
    function testFuzz_whenUnauthorizedCallerQueues_reverts(
        address caller_,
        uint8 assetKind_
    ) public {
        address revenueAdmin = _permittedProposer(true);
        vm.assume(caller_ != admin);
        vm.assume(caller_ != revenueAdmin);
        uint8 assetKind = assetKind_ % 5;
        address asset = assetKind == 0 ? address(0) : assetKind == 1 ? bob : address(token);
        if (assetKind >= 3) _activateAsset(address(token));
        if (assetKind == 4) {
            vm.prank(admin);
            distributor.disableAssetRoutes(address(token));
        }

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        configTimelock.queueDisableAssetRoutes(asset);

        assertEq(configTimelock.nextActionId(), 1, "unauthorized call consumes no ID");
    }

    // Scenarios: QDAR-L01
    function testFuzz_givenTimelockDisabled_whenQueued_reverts(bool useRevenueAdmin_) public {
        _activateAsset(address(token));
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(emergency);
        configTimelock.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(proposer);
        configTimelock.queueDisableAssetRoutes(address(token));

        assertEq(configTimelock.nextActionId(), 1, "disabled call consumes no ID");
    }

    // Scenarios: QDAR-L02
    function testFuzz_givenTimelockInactive_whenQueued_reverts(bool useRevenueAdmin_) public {
        _activateAsset(address(token));
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
        configTimelock.queueDisableAssetRoutes(address(token));

        assertEq(configTimelock.nextActionId(), 1, "inactive call consumes no ID");
    }

    // Scenarios: QDAR-L03
    function testFuzz_givenOperatorRotated_whenQueued_reverts(bool useRevenueAdmin_) public {
        _activateAsset(address(token));
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
        configTimelock.queueDisableAssetRoutes(address(token));

        assertEq(configTimelock.nextActionId(), 1, "unselected operator consumes no ID");
    }

    // Scenarios: QDAR-L04
    function testFuzz_givenDistributorDisabled_whenQueued_reverts(bool useRevenueAdmin_) public {
        _activateAsset(address(token));
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(admin);
        distributor.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(proposer);
        configTimelock.queueDisableAssetRoutes(address(token));

        assertEq(configTimelock.nextActionId(), 1, "disabled target consumes no ID");
    }

    // Scenarios: QDAR-L05
    function testFuzz_givenDistributorInactive_whenQueued_reverts(
        bool useRevenueAdmin_,
        bool locallyEnabled_
    ) public {
        _activateAsset(address(token));
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
        configTimelock.queueDisableAssetRoutes(address(token));

        assertEq(configTimelock.nextActionId(), 1, "inactive target consumes no ID");
    }

    // Scenarios: QDAR-P01
    function testFuzz_whenActiveAssetDisableQueues_executesAfterDelay(
        bool useRevenueAdmin_,
        address executor_
    ) public {
        _activateAsset(address(token));
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(proposer);
        uint64 actionId = configTimelock.queueDisableAssetRoutes(address(token));
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "queue does not retire asset"
        );

        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Retired),
            "execution retires asset"
        );
    }

    // Scenarios: QDAR-S01
    function testFuzz_whenRouteChangesAfterQueue_executionRevertsAndRetainsKey(
        address executor_,
        bool useRevenueAdmin_
    ) public {
        _activateAsset(address(token));
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(proposer);
        uint64 actionId = configTimelock.queueDisableAssetRoutes(address(token));
        (bytes32 key, bytes32 expectedHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 1});
        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, routes);
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

    // Scenarios: QDAR-I01
    function testFuzz_givenNonContractNeverListedAsset_whenDisableQueued_revertsAtQueue(
        bool zero_,
        bool useRevenueAdmin_
    ) public {
        address asset = zero_ ? address(0) : bob;
        address proposer = _permittedProposer(useRevenueAdmin_);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_AssetNotActive.selector,
                asset
            )
        );
        vm.prank(proposer);
        configTimelock.queueDisableAssetRoutes(asset);

        assertEq(configTimelock.nextActionId(), 1, "invalid retirement consumes no ID");
    }

    // Scenarios: QDAR-P01
    function testFuzz_whenActiveAssetHasRouteAndDebt_retirementPreservesDebt(
        bool useRevenueAdmin_,
        address executor_
    ) public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 1});
        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, routes);
        uint256 pendingAmount = 7;
        distributor.seedPendingForTest(address(token), bob, pendingAmount, 0, 0);
        address proposer = _permittedProposer(useRevenueAdmin_);
        vm.prank(proposer);
        uint64 actionId = configTimelock.queueDisableAssetRoutes(address(token));
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Retired),
            "asset retired"
        );
        assertEq(
            distributor.pendingPayout(address(token), bob),
            pendingAmount,
            "pending debt preserved"
        );
    }

    // Scenarios: QDAR-S02
    function testFuzz_whenAssetRetiredAfterQueue_executionReverts(address executor_) public {
        _activateAsset(address(token));
        vm.prank(admin);
        uint64 actionId = configTimelock.queueDisableAssetRoutes(address(token));
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
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Retired),
            "independent retirement remains"
        );
    }

    // Scenarios: QDAR-S03
    function testFuzz_whenYieldPointerChangesAfterQueue_executionReverts(address executor_) public {
        _activateAsset(address(token));
        vm.prank(admin);
        uint64 actionId = configTimelock.queueDisableAssetRoutes(address(token));
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
    }

    // Scenarios: QDAR-Q01
    function testFuzz_whenAssetKeyAlreadyOwned_secondQueueReverts(
        bool routeOwnsKey_,
        bool useRevenueAdmin_
    ) public {
        _activateAsset(address(token));
        address proposer = _permittedProposer(useRevenueAdmin_);
        uint64 actionId;
        vm.prank(proposer);
        if (routeOwnsKey_) {
            actionId = configTimelock.queueSetAssetRoutes(address(token), 0, _emptyRoutes());
        } else {
            actionId = configTimelock.queueDisableAssetRoutes(address(token));
        }
        bytes32 key = _queuedKey(actionId, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                key,
                actionId
            )
        );
        vm.prank(proposer);
        configTimelock.queueDisableAssetRoutes(address(token));

        assertEq(configTimelock.pendingActionId(key), actionId, "first action retains key");
    }
}
// forge-lint: disable-end(unused-return)
