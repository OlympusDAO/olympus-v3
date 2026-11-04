// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityConfigTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityConfigTimelock.sol";

// Mocks
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {YieldRepurchaseFacilityV2} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2.sol";
import {YieldRepurchaseFacilityConfigTimelock} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityConfigTimelock.sol";
import {YieldRepurchaseFacilityV2TestBase} from "src/test/policies/YieldRepurchaseFacility/YieldRepurchaseFacility/YieldRepurchaseFacilityV2TestBase.sol";
import {YieldRepurchaseFacilityConfigTimelockHarness} from "src/test/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityConfigTimelock/YieldRepurchaseFacilityConfigTimelockHarness.sol";

/// @notice Shared base for the YieldRepurchaseFacilityConfigTimelock test suite.
/// @dev Builds on the facility stack from `YieldRepurchaseFacilityV2TestBase`, whose
///      `_deployStack` deploys `configTimelock`, wires it to `yieldRepo`, and enables it, with
///      the guardian holding the admin and emergency roles and `yrfAdmin` holding the
///      yrf_admin role.
///
///      The facility pins its timelock as an immutable address, so the storage-inspecting
///      `YieldRepurchaseFacilityConfigTimelockHarness` cannot be wired to `yieldRepo`; `setUp` deploys a dedicated
///      `harnessFacility` pinned to the harness and wires the pair the same way.
abstract contract YieldRepurchaseFacilityConfigTimelockTestBase is
    YieldRepurchaseFacilityV2TestBase
{
    /// @notice Timelock harness exposing the internal pre-state and pending-slot storage.
    YieldRepurchaseFacilityConfigTimelockHarness internal timelockHarness;

    /// @notice Facility pinned to `timelockHarness`, mirroring the `yieldRepo` wiring.
    YieldRepurchaseFacilityV2 internal harnessFacility;

    function setUp() public virtual {
        _deployStack();

        timelockHarness = new YieldRepurchaseFacilityConfigTimelockHarness(
            kernel,
            configTimelockDelay,
            gracePeriod
        );
        vm.label(address(timelockHarness), "timelockHarness");
        kernel.executeAction(Actions.ActivatePolicy, address(timelockHarness));
        harnessFacility = _deployFacilityPinnedTo(address(timelockHarness));
        vm.label(address(harnessFacility), "harnessFacility");

        vm.startPrank(guardian);
        timelockHarness.setFacility(address(harnessFacility));
        timelockHarness.enable("");
        vm.stopPrank();
    }

    // ========== ACTION BUILDERS ========== //

    /// @notice Builds a sub-action targeting `yieldRepo`.
    function _facilityAction(
        bytes4 selector_,
        bytes memory payload_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory action) {
        action = ITimelockBatchQueue.BatchAction({
            target: address(yieldRepo),
            selector: selector_,
            payload: payload_
        });
    }

    /// @notice Builds a sub-action targeting `harnessFacility`.
    function _harnessAction(
        bytes4 selector_,
        bytes memory payload_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory action) {
        action = ITimelockBatchQueue.BatchAction({
            target: address(harnessFacility),
            selector: selector_,
            payload: payload_
        });
    }

    /// @notice Builds a length-1 batch from a raw (target, selector, payload) triple.
    function _singleAction(
        address target_,
        bytes4 selector_,
        bytes memory payload_
    ) internal pure returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = ITimelockBatchQueue.BatchAction({
            target: target_,
            selector: selector_,
            payload: payload_
        });
    }

    // ========== EVENT EXPECTATIONS ========== //

    /// @notice Expects the per-sub-action and closing queue events for a batch queued on
    ///         `queue_` in the current block.
    function _expectActionQueued(
        IYieldRepurchaseFacilityConfigTimelock queue_,
        uint64 actionId_,
        address proposer_,
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) internal {
        uint48 executableAt = uint48(vm.getBlockTimestamp()) + queue_.timelockDelay();
        uint48 expiresAt = executableAt + queue_.EXECUTION_WINDOW();

        for (uint256 i = 0; i < actions_.length; ++i) {
            vm.expectEmit(true, true, true, true, address(queue_));
            emit ITimelockBatchQueue.TimelockSubActionQueued(
                actionId_,
                actions_[i].target,
                actions_[i].selector,
                i,
                keccak256(actions_[i].payload)
            );
        }
        vm.expectEmit(true, true, false, true, address(queue_));
        emit ITimelockBatchQueue.TimelockActionQueued(
            actionId_,
            proposer_,
            keccak256(abi.encode(actions_)),
            executableAt,
            expiresAt
        );
    }

    /// @notice Expects the per-sub-action and closing execution events for a batch executed
    ///         on `queue_`. Facility events interleave between the expected ones.
    function _expectActionExecuted(
        IYieldRepurchaseFacilityConfigTimelock queue_,
        uint64 actionId_,
        address executor_,
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) internal {
        for (uint256 i = 0; i < actions_.length; ++i) {
            vm.expectEmit(true, true, true, true, address(queue_));
            emit ITimelockBatchQueue.TimelockSubActionExecuted(
                actionId_,
                actions_[i].target,
                actions_[i].selector,
                i
            );
        }
        vm.expectEmit(true, true, false, true, address(queue_));
        emit ITimelockBatchQueue.TimelockActionExecuted(actionId_, executor_);
    }

    // ========== QUEUE WRAPPERS ========== //
    // Each wrapper queues on `configTimelock` as the yrf_admin.

    function _queueSetYieldBuybackShare(
        address vault_,
        uint256 newShare_
    ) internal returns (uint64 actionId) {
        vm.prank(yrfAdmin);
        return configTimelock.queueSetYieldBuybackShare(vault_, newShare_);
    }

    function _queueSetInitialDiscount(uint256 initialDiscount_) internal returns (uint64 actionId) {
        vm.prank(yrfAdmin);
        return configTimelock.queueSetInitialDiscount(initialDiscount_);
    }

    function _queueSetMaxPricePremium(uint256 maxPricePremium_) internal returns (uint64 actionId) {
        vm.prank(yrfAdmin);
        return configTimelock.queueSetMaxPricePremium(maxPricePremium_);
    }

    function _queueEnableAsset(address vault_) internal returns (uint64 actionId) {
        vm.prank(yrfAdmin);
        return configTimelock.queueEnableAsset(vault_);
    }

    function _queueDisableAsset(address vault_) internal returns (uint64 actionId) {
        vm.prank(yrfAdmin);
        return configTimelock.queueDisableAsset(vault_);
    }

    function _queueExcludeClearinghouse(address clearinghouse_) internal returns (uint64 actionId) {
        vm.prank(yrfAdmin);
        return configTimelock.queueExcludeClearinghouse(clearinghouse_);
    }

    function _queueIncreaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) internal returns (uint64 actionId) {
        vm.prank(yrfAdmin);
        return configTimelock.queueIncreaseClearinghouseOffset(clearinghouse_, additionalOffset_);
    }

    function _queueDecreaseNextYield(
        address vault_,
        uint256 expectedNextYield_,
        uint256 newNextYield_
    ) internal returns (uint64 actionId) {
        vm.prank(yrfAdmin);
        return configTimelock.queueDecreaseNextYield(vault_, expectedNextYield_, newNextYield_);
    }

    function _queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) internal returns (uint64 actionId) {
        vm.prank(yrfAdmin);
        return configTimelock.queueBatch(actions_);
    }

    /// @notice Asserts the stored metadata and content of a single-action queue entry
    ///         queued by the yrf_admin at `queuedAt_` under the current delay.
    function _assertQueuedSingleAction(
        IYieldRepurchaseFacilityConfigTimelock queue_,
        uint64 actionId_,
        uint256 queuedAt_,
        ITimelockBatchQueue.BatchAction memory expected_
    ) internal view {
        ITimelockBatchQueue.QueuedAction memory action = queue_.getQueuedAction(actionId_);
        assertEq(action.proposer, yrfAdmin, "proposer");
        assertEq(action.queuedAt, queuedAt_, "queuedAt");
        assertEq(action.executableAt, queuedAt_ + queue_.timelockDelay(), "executableAt");
        assertEq(
            action.expiresAt,
            queuedAt_ + queue_.timelockDelay() + queue_.EXECUTION_WINDOW(),
            "expiresAt"
        );
        assertFalse(action.executed, "not executed");
        assertFalse(action.cancelled, "not cancelled");
        assertEq(action.actions.length, 1, "sub-action count");

        (address target, bytes4 selector, bytes memory payload) = queue_.getQueuedSubAction(
            actionId_,
            0
        );
        assertEq(target, expected_.target, "target");
        assertEq(selector, expected_.selector, "selector");
        assertEq(payload, expected_.payload, "payload");
    }

    // ========== TIME HELPERS ========== //

    /// @notice Warps to the first timestamp at which the action is executable.
    function _warpToExecutable(
        IYieldRepurchaseFacilityConfigTimelock queue_,
        uint64 actionId_
    ) internal {
        vm.warp(queue_.getQueuedAction(actionId_).executableAt);
    }

    /// @notice Warps to the first timestamp at which the action has expired.
    function _warpPastExpiry(
        IYieldRepurchaseFacilityConfigTimelock queue_,
        uint64 actionId_
    ) internal {
        vm.warp(uint256(queue_.getQueuedAction(actionId_).expiresAt) + 1);
    }

    // ========== STATE HELPERS ========== //

    /// @notice Deploys, activates, and enables a timelock whose facility slot is unset.
    function _deployUnwiredTimelock()
        internal
        returns (YieldRepurchaseFacilityConfigTimelock timelock)
    {
        timelock = new YieldRepurchaseFacilityConfigTimelock(
            kernel,
            configTimelockDelay,
            gracePeriod
        );
        vm.label(address(timelock), "unwiredTimelock");
        kernel.executeAction(Actions.ActivatePolicy, address(timelock));
        vm.prank(guardian);
        timelock.enable("");
    }

    /// @notice Deploys a facility pinned to `timelock_`, mirroring the `yieldRepo`
    ///         constructor arguments, and activates it as a policy so that it passes the
    ///         active-policy check of `setFacility`.
    function _deployFacilityPinnedTo(
        address timelock_
    ) internal returns (YieldRepurchaseFacilityV2 facility) {
        facility = new YieldRepurchaseFacilityV2(
            kernel,
            address(ohm),
            address(backingOracle),
            address(auctioneer),
            timelock_,
            gracePeriod
        );
        vm.label(address(facility), "pinnedFacility");
        kernel.executeAction(Actions.ActivatePolicy, address(facility));
    }

    /// @notice Registers `sReserve` on `facility_` as the enabled backing asset, seeding the
    ///         supplied next yield so that the decrease-next-yield path has material to cut.
    function _registerBackingAsset(
        YieldRepurchaseFacilityV2 facility_,
        uint256 nextYieldSeed_
    ) internal {
        vm.prank(guardian);
        facility_.addAsset(address(sReserve), 1e18, 0, 0, nextYieldSeed_, false, true);
    }

    /// @notice Registers a fresh non-backing asset (own reserve and vault mocks) on
    ///         `facility_`, returning the vault address. The asset is registered enabled;
    ///         its reserve is made priceable for the registration probe.
    function _registerSecondaryAsset(
        YieldRepurchaseFacilityV2 facility_,
        string memory label_,
        uint256 nextYieldSeed_
    ) internal returns (address vault) {
        MockERC20 secondaryReserve = new MockERC20(label_, label_, 18);
        vm.label(address(secondaryReserve), string.concat(label_, "Reserve"));
        MockERC4626 secondaryVault = new MockERC4626(secondaryReserve, label_, label_);
        vm.label(address(secondaryVault), label_);

        PRICE.setPrice(address(secondaryReserve), reservePrice);

        vm.prank(guardian);
        facility_.addAsset(address(secondaryVault), 1e18, 0, 0, nextYieldSeed_, false, false);

        return address(secondaryVault);
    }

    /// @notice Mirrors `YieldRepurchaseFacilityConfigTimelock`'s pending slot key of a vault's yield buyback share.
    function _yieldBuybackShareLockKey(address vault_) internal pure returns (bytes32) {
        return
            keccak256(abi.encode(IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector, vault_));
    }

    /// @notice Mirrors `YieldRepurchaseFacilityConfigTimelock`'s pending slot key of the initial discount.
    function _initialDiscountLockKey() internal pure returns (bytes32) {
        return keccak256(abi.encode(IYieldRepurchaseFacilityV2.setInitialDiscount.selector));
    }

    /// @notice Mirrors `YieldRepurchaseFacilityConfigTimelock`'s pending slot key of the max price premium.
    function _maxPricePremiumLockKey() internal pure returns (bytes32) {
        return keccak256(abi.encode(IYieldRepurchaseFacilityV2.setMaxPricePremium.selector));
    }
}
