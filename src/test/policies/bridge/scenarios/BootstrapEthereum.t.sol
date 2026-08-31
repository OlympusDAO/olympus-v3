// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenAdminRegistry} from "src/external/bridge/ICCIPTokenAdminRegistry.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BRIDGE_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPEthereumMigrationForkTest} from "./CCIPEthereumMigrationForkTest.sol";

/// @notice The Ethereum bootstrap: stand the config policy and the config timelock up over
///         the live lock/release pool and hand the authority from the DAO Multisig to the
///         OCG timelock, replaying the DAO batch and the OCG proposal step by step against
///         the pinned mainnet state.
contract CCIPMigrationForkTests_BootstrapEthereum is CCIPEthereumMigrationForkTest {
    /// @dev Digest of one route of the live pool, for the Solana-survival assertion.
    function _solanaRouteDigest() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    pool.getRemoteToken(solanaSelector),
                    pool.getRemotePools(solanaSelector),
                    _toConfig(pool.getCurrentOutboundRateLimiterState(solanaSelector)),
                    _toConfig(pool.getCurrentInboundRateLimiterState(solanaSelector))
                )
            );
    }

    // given the live mainnet state
    //   when the bootstrap runs step by step
    //     [X] the deployment fixes the documented bindings and the initial state
    //     [X] the DAO batch activates both policies but only PROPOSES the two handovers
    //     [X] the pool is funded to the recorded minimum backing before the proposal
    //     [X] the OCG proposal accepts both handovers, wires the stack and opens the burn/mint routes
    //     [X] the pre-existing Solana route survives untouched
    //     [X] the steady-state timelock path serves afterwards
    function test_bootstrap() public {
        bytes32 solanaBefore = _solanaRouteDigest();

        // Deployment only: nothing is activated and nothing has authority yet
        _deployPairOverLivePool();
        assertEq(config.pool(), address(pool), "deployment: the config should bind the live pool");
        assertEq(
            timelock.config(),
            address(config),
            "deployment: the timelock should bind the config"
        );
        assertFalse(config.isActive(), "deployment: the config should not be active yet");
        assertFalse(timelock.isActive(), "deployment: the timelock should not be active yet");
        assertFalse(config.isEnabled(), "deployment: the config should start disabled");
        assertFalse(timelock.isEnabled(), "deployment: the timelock should start disabled");

        // The DAO batch activates and proposes, but every acceptance is deferred to
        // the proposal, so nothing has changed hands yet
        _daoBatchActivateAndProposeHandovers(true);
        assertTrue(config.isActive(), "DAO batch: the config should be active");
        assertTrue(timelock.isActive(), "DAO batch: the timelock should be active");
        assertEq(pool.owner(), daoMS, "DAO batch: the pool ownership should only be proposed");
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = registry.getTokenConfig(
            address(ohm)
        );
        assertEq(
            tokenConfig.administrator,
            daoMS,
            "DAO batch: the OHM administrator should only be nominated"
        );
        assertEq(
            tokenConfig.pendingAdministrator,
            ocgTimelock,
            "DAO batch: the OCG timelock should be the pending administrator"
        );

        // The funding precondition of the proposal build
        _fundPoolToMinimumBacking();
        assertGe(
            ohm.balanceOf(address(pool)),
            minimumPoolBacking,
            "funding: the pool should reach the minimum backing"
        );

        // The OCG proposal accepts the handovers and wires the stack
        _ocgProposalAcceptAndWireStack();
        _assertStackWired(kernel, config, timelock, address(pool), "OCG proposal");
        tokenConfig = registry.getTokenConfig(address(ohm));
        assertEq(
            tokenConfig.administrator,
            ocgTimelock,
            "OCG proposal: the OCG timelock should administer OHM"
        );
        assertEq(
            tokenConfig.pendingAdministrator,
            address(0),
            "OCG proposal: no administrator transfer should stay pending"
        );
        assertEq(
            tokenConfig.tokenPool,
            address(pool),
            "OCG proposal: the registry entry should be untouched"
        );
        assertEq(
            ICCIPTokenPoolAdmin(address(pool)).getRateLimitAdmin(),
            address(0),
            "OCG proposal: the native rate limit admin should be cleared"
        );
        assertTrue(
            roles.hasRole(daoMS, BRIDGE_ADMIN_ROLE),
            "OCG proposal: the DAO MS should hold the bridge admin role"
        );

        // The four burn/mint routes carry the declared limits and counterpart tokens
        for (uint256 i; i < burnMintRoutes.length; ++i) {
            _assertRoute(
                address(pool),
                burnMintRoutes[i].chainSelector,
                burnMintRoutes[i].remoteToken,
                burnMintRoutes[i].outbound,
                burnMintRoutes[i].inbound,
                string.concat("route ", burnMintRoutes[i].name)
            );
        }

        // The live Solana route is untouched by the whole bootstrap
        assertEq(
            _solanaRouteDigest(),
            solanaBefore,
            "the Solana route should survive the bootstrap untouched"
        );

        // Steady state: route changes now flow through the timelock
        _assertTimelockPathServes(config, timelock, daoMS, burnMintRoutes[0].chainSelector);
    }

    // given the pair is deployed and activated
    //   when a route is added before the config policy is enabled
    //     [X] it reverts with NotEnabled
    // The proposal orders enable before every route call because the admin functions are
    // gated on the policy being enabled
    function test_whenAddChainPrecedesEnable_reverts() public {
        _deployPairOverLivePool();
        _daoBatchActivateAndProposeHandovers(true);
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _toChainUpdate(burnMintRoutes[0]);

        _expectRevertNotEnabled();
        vm.prank(ocgTimelock);
        config.addChain(update);
    }

    // given only the timelock has been activated in the kernel
    //   when the timelock is enabled
    //     [X] it reverts with CCIPBridgeConfigTimelock_ConfigNotActive
    // Enabling the timelock requires the config policy to be an active kernel policy, so the
    // activation order of the DAO batch is load-bearing
    function test_whenTimelockEnablePrecedesConfigActivation_reverts() public {
        _deployPairOverLivePool();
        vm.prank(daoMS);
        kernel.executeAction(Actions.ActivatePolicy, address(timelock));

        _expectRevertConfigNotActive(address(config));
        vm.prank(ocgTimelock);
        timelock.enable("");
    }

    // given the pool ownership was never proposed to the config
    //   when the config accepts the pool ownership
    //     [X] it reverts with MustBeProposedOwner
    // The DAO batch's ownership proposal is what arms the OCG-side acceptance
    function test_whenAcceptPoolOwnershipPrecedesTransfer_reverts() public {
        _deployPairOverLivePool();
        _daoBatchActivateAndProposeHandovers(false);
        vm.prank(ocgTimelock);
        config.enable("");

        _expectRevertMustBeProposedOwner();
        vm.prank(ocgTimelock);
        config.acceptPoolOwnership();
    }

    // given the bootstrap has completed
    //   when its steps are repeated
    //     [X] the kernel activation reverts with Kernel_PolicyAlreadyActivated
    //     [X] both enables revert with NotDisabled
    //     [X] the route addition reverts with ChainAlreadyExists
    //     [X] the registry nomination by the DAO MS reverts with OnlyAdministrator
    //     [X] the pool ownership proposal by the DAO MS reverts with OnlyCallableByOwner
    // These are the exact reverts the idempotent batch and proposal tooling must predict and
    // skip on when an action is already satisfied or an authority has moved on
    function test_givenBootstrapComplete_repeatedStepsRevertPredictably() public {
        _bootstrapStack();
        address ohmAddress = address(ohm);
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _toChainUpdate(burnMintRoutes[0]);

        _expectRevertPolicyAlreadyActivated(address(config));
        vm.prank(daoMS);
        kernel.executeAction(Actions.ActivatePolicy, address(config));

        _expectRevertNotDisabled();
        vm.prank(ocgTimelock);
        config.enable("");

        _expectRevertNotDisabled();
        vm.prank(ocgTimelock);
        timelock.enable("");

        _expectRevertChainAlreadyExists(update.remoteChainSelector);
        vm.prank(ocgTimelock);
        config.addChain(update);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenAdminRegistry.OnlyAdministrator.selector,
                daoMS,
                ohmAddress
            )
        );
        vm.prank(daoMS);
        registry.transferAdminRole(ohmAddress, ocgTimelock);

        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.OnlyCallableByOwner.selector));
        vm.prank(daoMS);
        pool.transferOwnership(address(config));
    }
}
