// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";

import {CCIPNonEthereumMigrationForkTest} from "./CCIPNonEthereumMigrationForkTest.sol";

/// @notice The non-Ethereum EVM config-pair replacement: swap the config policy and the config
///         timelock while the burn/mint pool keeps its address, kernel state and MINTR
///         permissions. The local DAO Multisig holds every authority, so the three Ethereum
///         stages collapse into one batch. The outgoing stack is stood up by the adoption bootstrap of
///         adoption on the pinned base-sepolia state.
contract CCIPMigrationForkTests_ReplaceConfigPairNonEthereum is CCIPNonEthereumMigrationForkTest {
    function setUp() public override {
        super.setUp();
        // The outgoing stack: the adoption bootstrap of the live pool
        _bootstrapStack();
        _promoteToOldPair();
    }

    // ========== THE SINGLE BATCH ========== //

    /// @notice The whole migration as one local DAO Multisig batch, in the documented order.
    function _singleBatchMigration(bool cancelSeededAction_) internal {
        _deployPair(kernel, address(pool));
        address newConfigAddress = address(config);
        address newTimelockAddress = address(timelock);
        vm.startPrank(daoMS);
        kernel.executeAction(Actions.ActivatePolicy, newConfigAddress);
        kernel.executeAction(Actions.ActivatePolicy, newTimelockAddress);
        if (cancelSeededAction_ && seededActionId != 0) {
            // The DAO Multisig proposed the seeded action, so it cancels as the proposer
            oldTimelock.cancelQueuedAction(seededActionId);
        }
        oldConfig.transferPoolOwnership(newConfigAddress);
        config.enable("");
        config.acceptPoolOwnership();
        config.setConfigOperator(newTimelockAddress);
        timelock.enable("");
        oldConfig.disable("");
        oldTimelock.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(oldConfig));
        kernel.executeAction(Actions.DeactivatePolicy, address(oldTimelock));
        vm.stopPrank();
    }

    // ========== TESTS ========== //

    // given the adopted stack with a queued action in the outgoing timelock
    //   when the single-batch replacement runs
    //     [X] the seeded action is cancelled and its domain released
    //     [X] the new stack is wired and the outgoing pair is disabled and deactivated
    //     [X] the pool keeps its kernel state, registry entry and every route, and never
    //         stops serving
    //     [X] the steady-state timelock path serves through the new pair
    function test_replacement() public {
        _seedQueuedRateLimitAction(oldTimelock, oldConfig, daoMS, sepoliaSelector);
        bytes32 routesBefore = _routeDigest(address(pool));

        _singleBatchMigration(true);

        ITimelockBatchQueue.QueuedAction memory seeded = oldTimelock.getQueuedAction(
            seededActionId
        );
        assertTrue(seeded.cancelled, "the seeded action should be cancelled");
        assertEq(
            oldTimelock.pendingActionId(oldTimelock.getRateLimitsKey(sepoliaSelector)),
            0,
            "the cancellation should release the seeded action's domain"
        );

        _assertStackWired(kernel, config, timelock, address(pool), "single batch");
        assertFalse(oldConfig.isEnabled(), "the outgoing config should be disabled");
        assertFalse(oldTimelock.isEnabled(), "the outgoing timelock should be disabled");
        assertFalse(kernel.isPolicyActive(oldConfig), "the outgoing config should be deactivated");
        assertFalse(
            kernel.isPolicyActive(oldTimelock),
            "the outgoing timelock should be deactivated"
        );

        // The pool is a policy here but is not replaced: kernel state, enablement, registry
        // entry and every route are untouched, so the chain never stops serving
        assertTrue(kernel.isPolicyActive(pool), "the pool policy should stay active");
        assertTrue(pool.isEnabled(), "the pool should never stop serving");
        assertEq(
            registry.getPool(address(ohm)),
            address(pool),
            "the registry entry should be untouched"
        );
        assertEq(_routeDigest(address(pool)), routesBefore, "every route should be untouched");

        // Steady state: route changes flow through the new timelock
        _assertTimelockPathServes(config, timelock, daoMS, sepoliaSelector);
    }

    // given the seeded action was not cancelled before the migration
    //   [X] executing it afterwards reverts with NotEnabled: disabling the outgoing timelock
    //       closes the window the skipped cancellation left open
    //   [X] re-enabling the outgoing timelock reverts with ConfigNotActive
    //   [X] the action still holds its domain, and cancellation still works and releases it
    function test_givenSeededActionNotCancelled_migrationClosesTheWindow() public {
        _seedQueuedRateLimitAction(oldTimelock, oldConfig, daoMS, sepoliaSelector);
        _singleBatchMigration(false);

        skip(oldTimelock.timelockDelay());
        _expectRevertNotEnabled();
        vm.prank(makeAddr("permissionlessExecutor"));
        oldTimelock.executeQueuedAction(seededActionId);

        _expectRevertConfigNotActive(address(oldConfig));
        vm.prank(daoMS);
        oldTimelock.enable("");

        bytes32 seededKey = oldTimelock.getRateLimitsKey(sepoliaSelector);
        assertEq(
            oldTimelock.pendingActionId(seededKey),
            seededActionId,
            "the forgotten action should still hold its domain"
        );
        vm.prank(daoMS);
        oldTimelock.cancelQueuedAction(seededActionId);
        assertEq(
            oldTimelock.pendingActionId(seededKey),
            0,
            "the late cancellation should release the domain"
        );
    }

    // given the outgoing config was disabled before the pool handover
    //   when the pool ownership is transferred through it
    //     [X] it reverts with NotEnabled
    // The batch orders the handover before the disable because the admin functions are gated
    // on the policy being enabled
    function test_whenPoolHandoverFollowsOldConfigDisable_reverts() public {
        _deployPair(kernel, address(pool));
        address newConfigAddress = address(config);

        vm.prank(daoMS);
        oldConfig.disable("");

        _expectRevertNotEnabled();
        vm.prank(daoMS);
        oldConfig.transferPoolOwnership(newConfigAddress);
    }

    // given the replacement has completed
    //   when its steps are repeated
    //     [X] the pool handover through the disabled outgoing config reverts with NotEnabled
    //     [X] the outgoing disables revert with NotEnabled
    //     [X] the kernel deactivations revert with Kernel_PolicyNotActivated
    //     [X] the new enables revert with NotDisabled
    function test_givenReplacementComplete_repeatedStepsRevertPredictably() public {
        _singleBatchMigration(false);
        address newConfigAddress = address(config);

        _expectRevertNotEnabled();
        vm.prank(daoMS);
        oldConfig.transferPoolOwnership(newConfigAddress);

        _expectRevertNotEnabled();
        vm.prank(daoMS);
        oldTimelock.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(Kernel.Kernel_PolicyNotActivated.selector, address(oldTimelock))
        );
        vm.prank(daoMS);
        kernel.executeAction(Actions.DeactivatePolicy, address(oldTimelock));

        _expectRevertNotDisabled();
        vm.prank(daoMS);
        config.enable("");

        _expectRevertNotDisabled();
        vm.prank(daoMS);
        timelock.enable("");
    }
}
