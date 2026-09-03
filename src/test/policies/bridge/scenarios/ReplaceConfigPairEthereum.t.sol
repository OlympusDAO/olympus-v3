// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenAdminRegistry} from "src/external/bridge/ICCIPTokenAdminRegistry.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";

import {CCIPEthereumMigrationForkTest} from "./CCIPEthereumMigrationForkTest.sol";

/// @notice The Ethereum config-pair replacement: swap the config policy and the config
///         timelock while the pool keeps its address, owner chain, liquidity and routes. The
///         outgoing stack is stood up by the bootstrap procedure on the pinned mainnet state; a queued
///         action is seeded in the outgoing timelock so the migration's cancellation step has
///         something meaningful to cancel.
contract CCIPMigrationForkTests_ReplaceConfigPairEthereum is CCIPEthereumMigrationForkTest {
    function setUp() public override {
        super.setUp();
        // The outgoing stack: the bootstrap procedure over the live pool
        _bootstrapStack();
        _promoteToOldPair();
    }

    // ========== PHASES ========== //

    /// @notice The activation batch: deploys and activates the new pair and, when
    ///         asked, cancels the seeded action on the outgoing timelock.
    function _daoBatchActivateNewPair(bool cancelSeededAction_) internal {
        _deployPair(kernel, address(pool));
        vm.startPrank(daoMS);
        kernel.executeAction(Actions.ActivatePolicy, address(config));
        kernel.executeAction(Actions.ActivatePolicy, address(timelock));
        if (cancelSeededAction_ && seededActionId != 0) {
            // The DAO Multisig proposed the seeded action, so it cancels as the proposer
            oldTimelock.cancelQueuedAction(seededActionId);
        }
        vm.stopPrank();
    }

    /// @notice The OCG proposal: seven actions in the documented order, switching the pool
    ///         ownership and the operator seat to the new pair.
    function _ocgProposalSwitchPairs() internal {
        vm.startPrank(ocgTimelock);
        oldConfig.transferPoolOwnership(address(config));
        config.enable("");
        config.acceptPoolOwnership();
        config.setConfigOperator(address(timelock));
        timelock.enable("");
        oldConfig.disable("");
        oldTimelock.disable("");
        vm.stopPrank();
    }

    /// @notice The retirement batch: deactivates the outgoing pair in the kernel.
    function _daoBatchDeactivateOldPair() internal {
        vm.startPrank(daoMS);
        kernel.executeAction(Actions.DeactivatePolicy, address(oldConfig));
        kernel.executeAction(Actions.DeactivatePolicy, address(oldTimelock));
        vm.stopPrank();
    }

    // ========== TESTS ========== //

    // given the bootstrapped stack with a queued action in the outgoing timelock
    //   when the replacement runs stage by stage
    //     [X] the activation batch activates the new pair and cancels the seeded action
    //     [X] the OCG proposal hands the pool over, wires the new stack and disables the
    //         outgoing pair
    //     [X] the retirement batch deactivates the outgoing pair in the kernel
    //     [X] the pool address, registry entry, liquidity and every route are untouched
    //     [X] the steady-state timelock path serves through the new pair
    function test_replacement() public {
        _seedQueuedRateLimitAction(oldTimelock, oldConfig, daoMS, burnMintRoutes[0].chainSelector);
        bytes32 routesBefore = _routeDigest(address(pool));
        uint256 liquidityBefore = ohm.balanceOf(address(pool));

        _daoBatchActivateNewPair(true);
        assertTrue(config.isActive(), "activation batch: the new config should be active");
        assertTrue(timelock.isActive(), "activation batch: the new timelock should be active");
        ITimelockBatchQueue.QueuedAction memory seeded = oldTimelock.getQueuedAction(
            seededActionId
        );
        assertTrue(seeded.cancelled, "activation batch: the seeded action should be cancelled");
        assertEq(
            oldTimelock.pendingActionId(
                oldTimelock.getRateLimitsKey(burnMintRoutes[0].chainSelector)
            ),
            0,
            "activation batch: the cancellation should release the seeded action's domain"
        );

        _ocgProposalSwitchPairs();
        _assertStackWired(kernel, config, timelock, address(pool), "OCG proposal");
        assertFalse(oldConfig.isEnabled(), "OCG proposal: the outgoing config should be disabled");
        assertFalse(
            oldTimelock.isEnabled(),
            "OCG proposal: the outgoing timelock should be disabled"
        );

        _daoBatchDeactivateOldPair();
        assertFalse(
            kernel.isPolicyActive(oldConfig),
            "retirement: the outgoing config should be deactivated"
        );
        assertFalse(
            kernel.isPolicyActive(oldTimelock),
            "retirement: the outgoing timelock should be deactivated"
        );

        // The config-pair replacement touches nothing but the pair: same pool in the registry, identical
        // routes, identical liquidity
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = registry.getTokenConfig(
            address(ohm)
        );
        assertEq(tokenConfig.administrator, ocgTimelock, "the OHM administrator is untouched");
        assertEq(tokenConfig.tokenPool, address(pool), "the registry entry is untouched");
        assertEq(_routeDigest(address(pool)), routesBefore, "every route is untouched");
        assertEq(ohm.balanceOf(address(pool)), liquidityBefore, "the pool liquidity is untouched");

        // Steady state: route changes flow through the new timelock
        _assertTimelockPathServes(config, timelock, daoMS, burnMintRoutes[0].chainSelector);
    }

    // given the seeded action was not cancelled before the migration
    //   [X] executing it afterwards reverts with NotEnabled: disabling the outgoing timelock
    //       closes the window the skipped cancellation left open
    //   [X] re-enabling the outgoing timelock reverts with ConfigNotActive: the kernel
    //       deactivation makes the zombie pair unrevivable
    //   [X] the action still holds its domain, and cancellation still works and releases it
    // This pins why the cancellation step exists and what the later steps protect when it is
    // forgotten
    function test_givenSeededActionNotCancelled_migrationClosesTheWindow() public {
        _seedQueuedRateLimitAction(oldTimelock, oldConfig, daoMS, burnMintRoutes[0].chainSelector);
        _daoBatchActivateNewPair(false);
        _ocgProposalSwitchPairs();
        _daoBatchDeactivateOldPair();

        // The action ripened while the migration ran, but the disabled outgoing timelock
        // rejects the execution
        skip(oldTimelock.timelockDelay());
        _expectRevertNotEnabled();
        vm.prank(makeAddr("permissionlessExecutor"));
        oldTimelock.executeQueuedAction(seededActionId);

        // The zombie cannot be revived: enable requires its config policy to be an active
        // kernel policy, and the retirement batch deactivated it
        _expectRevertConfigNotActive(address(oldConfig));
        vm.prank(ocgTimelock);
        oldTimelock.enable("");

        // The forgotten action still holds its domain in the outgoing namespace, and
        // cancellation stays reachable in every product state: the proposer clears it
        bytes32 seededKey = oldTimelock.getRateLimitsKey(burnMintRoutes[0].chainSelector);
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
    // The proposal orders the handover before the disable because the admin functions are
    // gated on the policy being enabled
    function test_whenPoolHandoverFollowsOldConfigDisable_reverts() public {
        _daoBatchActivateNewPair(false);
        address newConfigAddress = address(config);

        vm.prank(ocgTimelock);
        oldConfig.disable("");

        _expectRevertNotEnabled();
        vm.prank(ocgTimelock);
        oldConfig.transferPoolOwnership(newConfigAddress);
    }

    // given the replacement has completed
    //   when its steps are repeated
    //     [X] the pool handover through the disabled outgoing config reverts with NotEnabled
    //     [X] the outgoing disables revert with NotEnabled
    //     [X] the kernel deactivations revert with Kernel_PolicyNotActivated
    //     [X] the new enables revert with NotDisabled
    // These are the exact reverts the idempotent tooling must predict and skip on
    function test_givenReplacementComplete_repeatedStepsRevertPredictably() public {
        _daoBatchActivateNewPair(false);
        _ocgProposalSwitchPairs();
        _daoBatchDeactivateOldPair();
        address newConfigAddress = address(config);

        _expectRevertNotEnabled();
        vm.prank(ocgTimelock);
        oldConfig.transferPoolOwnership(newConfigAddress);

        _expectRevertNotEnabled();
        vm.prank(ocgTimelock);
        oldConfig.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(Kernel.Kernel_PolicyNotActivated.selector, address(oldConfig))
        );
        vm.prank(daoMS);
        kernel.executeAction(Actions.DeactivatePolicy, address(oldConfig));

        _expectRevertNotDisabled();
        vm.prank(ocgTimelock);
        config.enable("");

        _expectRevertNotDisabled();
        vm.prank(ocgTimelock);
        timelock.enable("");
    }
}
