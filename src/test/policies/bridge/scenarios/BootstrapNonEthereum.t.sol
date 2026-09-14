// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";

import {CCIPNonEthereumMigrationForkTest} from "./CCIPNonEthereumMigrationForkTest.sol";

/// @notice The non-Ethereum EVM bootstrap: adopt the already-serving burn/mint pool
///         of base-sepolia into a freshly deployed config policy and config timelock, retire
///         the legacy LayerZero bridge, and hand the pool ownership from its EOA owner to the
///         config policy, replaying the setup batch step by step against the pinned state.
contract CCIPMigrationForkTests_BootstrapNonEthereum is CCIPNonEthereumMigrationForkTest {
    // given the live base-sepolia state
    //   when the adoption runs step by step
    //     [X] the legacy LayerZero bridge is switched off and deactivated with zero approval
    //     [X] the pair binds the existing pool and both policies activate
    //     [X] the wiring hands the pool to the config and seats the timelock
    //     [X] the live routes survive untouched and the pool never stops serving
    //     [X] the previous owner loses its direct pool authority
    //     [X] the steady-state timelock path serves afterwards
    function test_bootstrap() public {
        bytes32 routesBefore = _routeDigest(address(pool));

        _retireLegacyBridge();
        assertFalse(legacyBridge.bridgeActive(), "the legacy bridge should be switched off");
        assertFalse(
            kernel.isPolicyActive(legacyBridge),
            "the legacy bridge should be deactivated in the kernel"
        );

        _deployPair(kernel, address(pool));
        assertEq(config.pool(), address(pool), "the config should bind the existing pool");
        assertEq(timelock.config(), address(config), "the timelock should bind the config");

        _activatePairAndGrantRoles();
        assertTrue(config.isActive(), "the config should be active");
        assertTrue(timelock.isActive(), "the timelock should be active");

        _wireStack();
        _assertStackWired(kernel, config, timelock, address(pool), "adoption");

        // Adoption changes authority, never routes or service: the pool stayed enabled and
        // registered for the whole procedure, and every live route is byte-identical
        assertEq(
            _routeDigest(address(pool)),
            routesBefore,
            "the live routes should survive the adoption untouched"
        );
        assertTrue(pool.isEnabled(), "the pool should never stop serving");
        assertEq(
            registry.getPool(address(ohm)),
            address(pool),
            "the registry entry should be untouched"
        );

        // The previous owner has handed its direct pool authority to the config policy: with
        // the ownership moved and no rate limit admin grant, a direct bucket write by the
        // old owner is rejected by the pool itself
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(address(pool));
        assertEq(
            rigPool.getRateLimitAdmin(),
            address(0),
            "no native rate limit admin should be set"
        );
        ICCIPRateLimiter.Config memory liveOutbound = _toConfig(
            rigPool.getCurrentOutboundRateLimiterState(sepoliaSelector)
        );
        ICCIPRateLimiter.Config memory liveInbound = _toConfig(
            rigPool.getCurrentInboundRateLimiterState(sepoliaSelector)
        );
        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.Unauthorized.selector, daoMS));
        vm.prank(daoMS);
        rigPool.setChainRateLimiterConfig(sepoliaSelector, liveOutbound, liveInbound);

        // Steady state: route changes now flow through the timelock, over the live route
        _assertTimelockPathServes(config, timelock, daoMS, sepoliaSelector);
    }

    // given the pair is deployed and activated over the adopted pool
    //   when a route is added before the config policy is enabled
    //     [X] it reverts with NotEnabled
    // The setup batch orders enable before the route step because the admin functions are
    // gated on the policy being enabled
    function test_whenAddChainPrecedesEnable_reverts() public {
        _retireLegacyBridge();
        _deployPair(kernel, address(pool));
        _activatePairAndGrantRoles();
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _newCounterpartUpdate();

        _expectRevertNotEnabled();
        vm.prank(daoMS);
        config.addChain(update);
    }

    // given only the timelock has been activated in the kernel
    //   when the timelock is enabled
    //     [X] it reverts with CCIPTokenPoolConfigTimelock_ConfigNotActive
    // Enabling the timelock requires the config policy to be an active kernel policy, so the
    // activation order of the setup batch is load-bearing
    function test_whenTimelockEnablePrecedesConfigActivation_reverts() public {
        _deployPair(kernel, address(pool));
        vm.prank(daoMS);
        kernel.executeAction(Actions.ActivatePolicy, address(timelock));

        _expectRevertConfigNotActive(address(config));
        vm.prank(daoMS);
        timelock.enable("");
    }

    // given the pool ownership was never proposed to the config
    //   when the config accepts the pool ownership
    //     [X] it reverts with MustBeProposedOwner
    // The direct handover by the current owner is what arms the acceptance
    function test_whenAcceptPoolOwnershipPrecedesTransfer_reverts() public {
        _deployPair(kernel, address(pool));
        _activatePairAndGrantRoles();
        vm.prank(daoMS);
        config.enable("");

        _expectRevertMustBeProposedOwner();
        vm.prank(daoMS);
        config.acceptPoolOwnership();
    }

    // given the adoption has completed
    //   when its steps are repeated
    //     [X] the kernel activation reverts with Kernel_PolicyAlreadyActivated
    //     [X] both enables revert with NotDisabled
    //     [X] the legacy bridge deactivation reverts with Kernel_PolicyNotActivated
    //     [X] the route addition for a live route reverts with ChainAlreadyExists
    //     [X] the ownership handover by the previous owner reverts with OnlyCallableByOwner
    // These are the exact reverts the idempotent setup tooling must predict and skip on when
    // an action is already satisfied or an authority has moved on
    function test_givenBootstrapComplete_repeatedStepsRevertPredictably() public {
        _bootstrapStack();
        ICCIPTokenPoolAdmin.ChainUpdate memory liveRouteUpdate = _newCounterpartUpdate();
        liveRouteUpdate.remoteChainSelector = sepoliaSelector;
        liveRouteUpdate.remoteTokenAddress = sepoliaRemoteToken;

        _expectRevertPolicyAlreadyActivated(address(config));
        vm.prank(daoMS);
        kernel.executeAction(Actions.ActivatePolicy, address(config));

        _expectRevertNotDisabled();
        vm.prank(daoMS);
        config.enable("");

        _expectRevertNotDisabled();
        vm.prank(daoMS);
        timelock.enable("");

        vm.expectRevert(
            abi.encodeWithSelector(Kernel.Kernel_PolicyNotActivated.selector, address(legacyBridge))
        );
        vm.prank(daoMS);
        kernel.executeAction(Actions.DeactivatePolicy, address(legacyBridge));

        _expectRevertChainAlreadyExists(sepoliaSelector);
        vm.prank(daoMS);
        config.addChain(liveRouteUpdate);

        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.OnlyCallableByOwner.selector));
        vm.prank(daoMS);
        pool.transferOwnership(address(config));
    }
}
