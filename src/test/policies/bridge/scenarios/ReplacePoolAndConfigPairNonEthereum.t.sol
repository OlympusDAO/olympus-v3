// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";

// Contracts
import {Actions, Kernel, Module} from "src/Kernel.sol";
import {CCIPBurnMintTokenPool} from "src/policies/bridge/CCIPBurnMintTokenPool.sol";

import {CCIPNonEthereumMigrationForkTest} from "./CCIPNonEthereumMigrationForkTest.sol";

/// @notice Mirror of the live CCIP router's off-ramp listing, used to impersonate a real
///         off-ramp for the inbound delivery probes.
interface IRouterOffRamps {
    struct OffRamp {
        uint64 sourceChainSelector;
        address offRamp;
    }

    function getOffRamps() external view returns (OffRamp[] memory offRamps);
}

/// @notice The non-Ethereum EVM pool-and-config-pair replacement: replace the burn/mint
///         pool, the config policy and the config timelock in one local DAO Multisig batch.
///         The outgoing stack is stood up by the adoption bootstrap on the pinned
///         base-sepolia state; inbound
///         delivery is probed through a real off-ramp of the live router, so the two ordering
///         gates around `setPool` (MINTR permissions from the kernel activation, the pool's
///         own enablement) are observed as actual mint failures, not just as reverts of the
///         setup calls.
/// @dev    The documented Ethereum-side pre-step (adding the new local pool to the Ethereum
///         pool's accepted remote pools) runs on the counterpart chain and is out of a
///         single-chain fork's reach; the local half asserted here is complete.
contract CCIPMigrationForkTests_ReplacePoolAndConfigPairNonEthereum is
    CCIPNonEthereumMigrationForkTest
{
    CCIPBurnMintTokenPool internal newPool;

    /// @notice The amount of the inbound delivery probes, in OHM base units: far below the
    ///         standard enabled inbound capacity of 20_000 base units, so the rate limiter
    ///         never interferes with the gate under test.
    uint256 internal constant PROBE_AMOUNT = 1_000;

    function setUp() public override {
        super.setUp();
        // The outgoing stack: the adoption bootstrap of the live pool
        _bootstrapStack();
        _promoteToOldPair();
    }

    // ========== THE SINGLE BATCH ========== //

    /// @notice Deploys the replacement pool and pair; the test contract is the deployer, so
    ///         it proposes the pool ownership to the new config directly.
    function _deployReplacement() internal {
        newPool = new CCIPBurnMintTokenPool(
            address(kernel),
            address(ohm),
            rmnAddress,
            routerAddress
        );
        vm.label(address(newPool), "newPool");
        _deployPair(kernel, address(newPool));
        newPool.transferOwnership(address(config));
    }

    /// @notice The whole local migration as one DAO Multisig batch, in the documented order.
    ///         `registerPool_` and `enableNewPool_` are split out so the ordering negatives
    ///         can omit exactly one gate.
    function _singleBatchMigration(
        bool cancelSeededAction_,
        bool enableNewPool_,
        bool registerPool_
    ) internal {
        vm.startPrank(daoMS);
        if (cancelSeededAction_ && seededActionId != 0) {
            oldTimelock.cancelQueuedAction(seededActionId);
        }
        kernel.executeAction(Actions.ActivatePolicy, address(newPool));
        kernel.executeAction(Actions.ActivatePolicy, address(config));
        kernel.executeAction(Actions.ActivatePolicy, address(timelock));
        if (enableNewPool_) newPool.enable("");
        config.enable("");
        config.acceptPoolOwnership();
        vm.stopPrank();
        _recreateRoutesFromOldPool();
        vm.startPrank(daoMS);
        config.setConfigOperator(address(timelock));
        timelock.enable("");
        if (registerPool_) registry.setPool(address(ohm), address(newPool));
        vm.stopPrank();
    }

    /// @notice Retires the outgoing stack: disables all three policies and deactivates them.
    function _retireOutgoingStack() internal {
        vm.startPrank(daoMS);
        pool.disable("");
        oldConfig.disable("");
        oldTimelock.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(pool));
        kernel.executeAction(Actions.DeactivatePolicy, address(oldConfig));
        kernel.executeAction(Actions.DeactivatePolicy, address(oldTimelock));
        vm.stopPrank();
    }

    /// @notice Recreates every route of the outgoing pool on the new one, copying the live
    ///         remote token and remote pools; the live disabled bucket shapes (a legacy
    ///         direct-owner configuration) are replaced by standard enabled values, which the
    ///         config's validated paths require.
    function _recreateRoutesFromOldPool() internal {
        ICCIPTokenPoolAdmin oldPool = ICCIPTokenPoolAdmin(address(pool));
        uint64[] memory selectors = oldPool.getSupportedChains();
        vm.startPrank(daoMS);
        for (uint256 i; i < selectors.length; ++i) {
            (
                ICCIPRateLimiter.Config memory outbound,
                ICCIPRateLimiter.Config memory inbound
            ) = _serviceableRateLimits(address(pool), selectors[i]);
            config.addChain(
                ICCIPTokenPoolAdmin.ChainUpdate({
                    remoteChainSelector: selectors[i],
                    remotePoolAddresses: oldPool.getRemotePools(selectors[i]),
                    remoteTokenAddress: oldPool.getRemoteToken(selectors[i]),
                    outboundRateLimiterConfig: outbound,
                    inboundRateLimiterConfig: inbound
                })
            );
        }
        vm.stopPrank();
    }

    // ========== INBOUND DELIVERY PROBE ========== //

    /// @notice A real off-ramp of the live router for the sepolia lane; the pool accepts
    ///         `releaseOrMint` only from an address the router lists.
    function _findSepoliaOffRamp() internal view returns (address) {
        IRouterOffRamps.OffRamp[] memory offRamps = IRouterOffRamps(routerAddress).getOffRamps();
        for (uint256 i; i < offRamps.length; ++i) {
            if (offRamps[i].sourceChainSelector == sepoliaSelector) return offRamps[i].offRamp;
        }
        revert("live: the router should list an off-ramp for the sepolia lane");
    }

    /// @notice Fires an inbound delivery at a pool exactly as the off-ramp would. A non-empty
    ///         `expectedRevert_` arms the expectation immediately before the delivery call, so
    ///         the helper's own setup reads cannot consume it; empty bytes expect success.
    function _deliverInbound(
        CCIPBurnMintTokenPool targetPool_,
        address recipient_,
        bytes memory expectedRevert_
    ) internal {
        address offRamp = _findSepoliaOffRamp();
        Pool.ReleaseOrMintInV1 memory delivery = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(makeAddr("sourceSender")),
            remoteChainSelector: sepoliaSelector,
            receiver: recipient_,
            amount: PROBE_AMOUNT,
            localToken: address(ohm),
            sourcePoolAddress: sepoliaRemotePool,
            sourcePoolData: "",
            offchainTokenData: ""
        });
        if (expectedRevert_.length != 0) vm.expectRevert(expectedRevert_);
        vm.prank(offRamp);
        targetPool_.releaseOrMint(delivery);
    }

    // ========== TESTS ========== //

    // given the adopted stack with a queued action in the outgoing timelock
    //   when the full local replacement runs
    //     [X] the new stack is wired over the new pool with every route copied
    //     [X] the registry points at the new pool and the seeded action is cancelled
    //     [X] a real off-ramp delivery mints on the new pool with a zero net mint approval
    //     [X] the outgoing pool is disabled and deactivated and rejects deliveries
    //     [X] the outgoing pool keeps its recorded mint approval semantics: none is left
    //     [X] the steady-state timelock path serves through the new stack
    function test_replacement() public {
        _seedQueuedRateLimitAction(oldTimelock, oldConfig, daoMS, sepoliaSelector);
        ICCIPTokenPoolAdmin oldPool = ICCIPTokenPoolAdmin(address(pool));
        uint64[] memory oldSelectors = oldPool.getSupportedChains();

        _deployReplacement();
        _singleBatchMigration(true, true, true);
        _retireOutgoingStack();

        _assertStackWired(kernel, config, timelock, address(newPool), "replacement");
        assertTrue(
            oldTimelock.getQueuedAction(seededActionId).cancelled,
            "the seeded action should be cancelled"
        );
        assertEq(
            registry.getPool(address(ohm)),
            address(newPool),
            "the registry should point at the new pool"
        );
        for (uint256 i; i < oldSelectors.length; ++i) {
            assertTrue(
                newPool.isSupportedChain(oldSelectors[i]),
                "the recreated route should exist on the new pool"
            );
        }
        assertFalse(pool.isEnabled(), "the outgoing pool should be disabled");
        assertFalse(
            kernel.isPolicyActive(pool),
            "the outgoing pool should be deactivated in the kernel"
        );
        assertEq(
            mintr.mintApproval(address(pool)),
            0,
            "the outgoing pool should leave no usable mint approval"
        );

        // A real inbound delivery mints on the new pool; the pool raises its own approval
        // and consumes it in the same call, so nothing accumulates
        address recipient = makeAddr("deliveryRecipient");
        uint256 supplyBefore = ohm.totalSupply();
        _deliverInbound(newPool, recipient, "");
        assertEq(
            ohm.balanceOf(recipient),
            PROBE_AMOUNT,
            "the delivery should mint to the recipient"
        );
        assertEq(
            ohm.totalSupply(),
            supplyBefore + PROBE_AMOUNT,
            "the delivery should mint new supply"
        );
        assertEq(
            mintr.mintApproval(address(newPool)),
            0,
            "the new pool should hold no net mint approval"
        );

        // The retired pool rejects deliveries: its enable gate closed with the migration
        _deliverInbound(pool, recipient, abi.encodeWithSelector(IEnabler.NotEnabled.selector));

        // Steady state: route changes flow through the new timelock
        _assertTimelockPathServes(config, timelock, daoMS, sepoliaSelector);
    }

    // given the new pool was registered before it was enabled
    //   [X] a real off-ramp delivery fails with NotEnabled: a registered pool that cannot
    //       mint strands inbound messages
    //   [X] enabling the pool afterwards makes the same delivery succeed
    // This is the ordering gate that puts `enable` before `setPool` in the procedure
    function test_whenPoolRegisteredBeforeEnable_mintFails() public {
        _deployReplacement();
        _singleBatchMigration(false, false, true);

        address recipient = makeAddr("deliveryRecipient");
        _deliverInbound(newPool, recipient, abi.encodeWithSelector(IEnabler.NotEnabled.selector));

        vm.prank(daoMS);
        newPool.enable("");
        _deliverInbound(newPool, recipient, "");
        assertEq(
            ohm.balanceOf(recipient),
            PROBE_AMOUNT,
            "the delivery should succeed once the pool is enabled"
        );
    }

    // given the new pool lost its kernel activation while registered and enabled
    //   [X] a real off-ramp delivery fails with Module_PolicyNotPermitted: the MINTR
    //       permissions granted by the activation are what let a registered pool mint
    //   [X] re-activating the pool makes the same delivery succeed
    // This is the ordering gate that puts `ActivatePolicy` before `setPool` in the
    // procedure; the deactivation is how the permission half is observable separately from
    // the enable gate, which survives a deactivation
    function test_givenPoolDeactivatedInKernel_mintFails() public {
        _deployReplacement();
        _singleBatchMigration(false, true, true);
        vm.prank(daoMS);
        kernel.executeAction(Actions.DeactivatePolicy, address(newPool));
        assertTrue(newPool.isEnabled(), "the enable flag should survive the deactivation");

        address recipient = makeAddr("deliveryRecipient");
        _deliverInbound(
            newPool,
            recipient,
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(newPool))
        );

        vm.prank(daoMS);
        kernel.executeAction(Actions.ActivatePolicy, address(newPool));
        _deliverInbound(newPool, recipient, "");
        assertEq(
            ohm.balanceOf(recipient),
            PROBE_AMOUNT,
            "the delivery should succeed once the permissions are restored"
        );
    }

    // given the replacement has completed
    //   when its steps are repeated
    //     [X] the new pool's enable reverts with NotDisabled
    //     [X] the outgoing pool's disable reverts with NotEnabled
    //     [X] the kernel deactivations revert with Kernel_PolicyNotActivated
    //     [X] the route recreation reverts with ChainAlreadyExists
    function test_givenReplacementComplete_repeatedStepsRevertPredictably() public {
        _deployReplacement();
        _singleBatchMigration(false, true, true);
        _retireOutgoingStack();

        _expectRevertNotDisabled();
        vm.prank(daoMS);
        newPool.enable("");

        _expectRevertNotEnabled();
        vm.prank(daoMS);
        pool.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(Kernel.Kernel_PolicyNotActivated.selector, address(pool))
        );
        vm.prank(daoMS);
        kernel.executeAction(Actions.DeactivatePolicy, address(pool));

        _expectRevertChainAlreadyExists(sepoliaSelector);
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _newCounterpartUpdate();
        update.remoteChainSelector = sepoliaSelector;
        vm.prank(daoMS);
        config.addChain(update);
    }
}
