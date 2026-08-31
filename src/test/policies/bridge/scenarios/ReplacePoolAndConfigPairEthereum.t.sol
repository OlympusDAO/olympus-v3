// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {LockReleaseTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/LockReleaseTokenPool.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";

import {CCIPEthereumMigrationForkTest} from "./CCIPEthereumMigrationForkTest.sol";

/// @notice The Ethereum pool-and-config-pair replacement: replace the pool, the config
///         policy and the config timelock together. The outgoing stack is stood up by the
///         bootstrap procedure on the pinned mainnet state; the replacement pool is a fresh lock/release pool over the real
///         OHM, router and RMN proxy, the liquidity migrates through the rebalancer dance,
///         and the TokenAdminRegistry is re-pointed by the OHM administrator.
/// @dev    The activator of the documented proposal is packaging (it fits the sequence into
///         the fifteen-action limit under a temporary admin grant); the steps inside
///         `activate()` are replayed here directly as the admin-role holder, which preserves
///         every gate and ordering the procedure relies on. The Solana-side
///         `AppendRemotePoolAddresses` pre-step runs outside the EVM and is out of a
///         single-chain fork's reach; the cross-chain rule it implements is documented in the
///         migration notes.
contract CCIPMigrationForkTests_ReplacePoolAndConfigPairEthereum is CCIPEthereumMigrationForkTest {
    LockReleaseTokenPool internal newPool;

    function setUp() public override {
        super.setUp();
        // The outgoing stack: the bootstrap procedure over the live pool
        _bootstrapStack();
        _promoteToOldPair();
    }

    // ========== PHASES ========== //

    /// @notice Deployment and the DAO Multisig batch: the new pool is constructed
    ///         for the same OHM (a different token would fail `setPool` later), its ownership
    ///         is proposed to the new config by its deployer, and the new pair is activated.
    function _deployReplacementAndDaoBatch(bool cancelSeededAction_) internal {
        newPool = new LockReleaseTokenPool(
            IERC20(address(ohm)),
            9,
            new address[](0),
            rmnAddress,
            true,
            routerAddress
        );
        vm.label(address(newPool), "newPool");
        _deployPair(kernel, address(newPool));
        // The test contract deployed the pool, so it proposes the ownership as the deployer
        newPool.transferOwnership(address(config));

        vm.startPrank(daoMS);
        kernel.executeAction(Actions.ActivatePolicy, address(config));
        kernel.executeAction(Actions.ActivatePolicy, address(timelock));
        if (cancelSeededAction_ && seededActionId != 0) {
            oldTimelock.cancelQueuedAction(seededActionId);
        }
        vm.stopPrank();
    }

    /// @notice The OCG proposal: the activator's inner steps are replayed directly
    ///         as the admin-role holder, followed by the registry re-point that only the OHM
    ///         administrator can perform.
    function _ocgProposalMigrateToNewStack() internal {
        uint256 liquidity = ohm.balanceOf(address(pool));
        vm.startPrank(ocgTimelock);
        config.enable("");
        config.acceptPoolOwnership();
        _recreateRoutesFromOldPool();
        oldConfig.setRebalancer(address(newPool));
        config.transferLiquidity(address(pool), liquidity);
        config.setRebalancer(ocgTimelock);
        config.setConfigOperator(address(timelock));
        timelock.enable("");
        oldConfig.disable("");
        oldTimelock.disable("");
        registry.setPool(address(ohm), address(newPool));
        vm.stopPrank();
    }

    /// @notice The retirement batch: deactivates the outgoing pair in the kernel.
    function _daoBatchDeactivateOldPair() internal {
        vm.startPrank(daoMS);
        kernel.executeAction(Actions.DeactivatePolicy, address(oldConfig));
        kernel.executeAction(Actions.DeactivatePolicy, address(oldTimelock));
        vm.stopPrank();
    }

    /// @notice Recreates every route of the outgoing pool on the new one, copying the live
    ///         remote token and remote pools. The live bucket configurations are copied when
    ///         enabled and replaced by standard enabled values otherwise (the config's
    ///         validated paths refuse disabled buckets).
    function _recreateRoutesFromOldPool() internal {
        uint64[] memory selectors = pool.getSupportedChains();
        for (uint256 i; i < selectors.length; ++i) {
            (
                ICCIPRateLimiter.Config memory outbound,
                ICCIPRateLimiter.Config memory inbound
            ) = _serviceableRateLimits(address(pool), selectors[i]);
            config.addChain(
                ICCIPTokenPoolAdmin.ChainUpdate({
                    remoteChainSelector: selectors[i],
                    remotePoolAddresses: pool.getRemotePools(selectors[i]),
                    remoteTokenAddress: pool.getRemoteToken(selectors[i]),
                    outboundRateLimiterConfig: outbound,
                    inboundRateLimiterConfig: inbound
                })
            );
        }
    }

    // ========== TESTS ========== //

    // given the bootstrapped stack with a queued action in the outgoing timelock
    //   when the full replacement runs stage by stage
    //     [X] the new pool answers the off-ramp's ERC165 probe within its 30k gas allowance
    //     [X] every route of the outgoing pool is recreated on the new one
    //     [X] the liquidity migrates in full and the token supply is conserved
    //     [X] the registry points at the new pool only after it holds the liquidity
    //     [X] the outgoing pair ends disabled and deactivated, the seeded action cancelled
    //     [X] the outgoing pool stays owned by the disabled outgoing config, and returning
    //         that ownership is blocked until the old config is re-enabled
    //     [X] the steady-state timelock path serves through the new stack
    function test_replacement() public {
        _seedQueuedRateLimitAction(oldTimelock, oldConfig, daoMS, burnMintRoutes[0].chainSelector);
        uint64[] memory oldSelectors = pool.getSupportedChains();
        uint256 liquidityBefore = ohm.balanceOf(address(pool));
        uint256 supplyBefore = ohm.totalSupply();

        _deployReplacementAndDaoBatch(true);

        // The registry probe precondition: the replacement answers supportsInterface within
        // the 30,000 gas the destination off-ramp forwards; setPool itself never checks this
        (bool probeOk, bytes memory probeData) = address(newPool).staticcall{gas: 30_000}(
            abi.encodeCall(IERC165.supportsInterface, (bytes4(0xaff2afbf)))
        );
        assertTrue(probeOk, "the ERC165 probe should succeed within 30k gas");
        assertTrue(abi.decode(probeData, (bool)), "the new pool should advertise CCIP_POOL_V1");

        _ocgProposalMigrateToNewStack();

        // Every route of the outgoing pool is live on the new one with its token and pools
        for (uint256 i; i < oldSelectors.length; ++i) {
            assertTrue(
                newPool.isSupportedChain(oldSelectors[i]),
                "the recreated route should exist on the new pool"
            );
            assertEq(
                newPool.getRemoteToken(oldSelectors[i]),
                pool.getRemoteToken(oldSelectors[i]),
                "the recreated route should carry the same remote token"
            );
            assertEq(
                keccak256(abi.encode(newPool.getRemotePools(oldSelectors[i]))),
                keccak256(abi.encode(pool.getRemotePools(oldSelectors[i]))),
                "the recreated route should accept the same remote pools"
            );
        }

        // The liquidity moved in full: the old pool is empty, the new one holds everything,
        // and no OHM was minted or burned on the way
        assertEq(ohm.balanceOf(address(pool)), 0, "the outgoing pool should be empty");
        assertEq(
            ohm.balanceOf(address(newPool)),
            liquidityBefore,
            "the new pool should hold the migrated liquidity"
        );
        assertEq(ohm.totalSupply(), supplyBefore, "the migration should conserve the supply");
        assertGe(
            ohm.balanceOf(address(newPool)),
            minimumPoolBacking,
            "the new pool should carry the minimum backing"
        );

        // The registry points at the funded new pool
        assertEq(
            registry.getPool(address(ohm)),
            address(newPool),
            "the registry should point at the new pool"
        );

        _daoBatchDeactivateOldPair();
        _assertStackWired(kernel, config, timelock, address(newPool), "replacement");
        assertFalse(oldConfig.isEnabled(), "the outgoing config should be disabled");
        assertFalse(kernel.isPolicyActive(oldConfig), "the outgoing config should be deactivated");
        assertTrue(
            oldTimelock.getQueuedAction(seededActionId).cancelled,
            "the seeded action should be cancelled"
        );

        // The outgoing pool stays owned by the disabled outgoing config; returning the
        // ownership later requires re-enabling that policy first
        assertEq(
            pool.owner(),
            address(oldConfig),
            "the outgoing pool should stay owned by the outgoing config"
        );
        _expectRevertNotEnabled();
        vm.prank(ocgTimelock);
        oldConfig.transferPoolOwnership(daoMS);

        // Steady state: route changes flow through the new timelock over the new pool
        _assertTimelockPathServes(config, timelock, daoMS, burnMintRoutes[0].chainSelector);
    }

    // given the outgoing pool's rebalancer was not pointed at the new pool
    //   when the liquidity transfer runs
    //     [X] it reverts with Unauthorized carrying the new pool
    // withdrawLiquidity on the outgoing pool checks its rebalancer, so the rebalancer
    // handover must precede the transfer
    function test_whenTransferLiquidityPrecedesRebalancerHandover_reverts() public {
        _deployReplacementAndDaoBatch(false);
        uint256 liquidity = ohm.balanceOf(address(pool));
        address oldPoolAddress = address(pool);

        vm.startPrank(ocgTimelock);
        config.enable("");
        config.acceptPoolOwnership();
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.Unauthorized.selector, address(newPool))
        );
        config.transferLiquidity(oldPoolAddress, liquidity);
        vm.stopPrank();
    }

    // given the outgoing config was disabled before the liquidity moved
    //   when its rebalancer is pointed at the new pool
    //     [X] it reverts with NotEnabled
    // The rebalancer handover and the transfer must precede the disable of the outgoing
    // config, which serves both
    function test_whenRebalancerHandoverFollowsOldConfigDisable_reverts() public {
        _deployReplacementAndDaoBatch(false);
        address newPoolAddress = address(newPool);

        vm.prank(ocgTimelock);
        oldConfig.disable("");

        _expectRevertNotEnabled();
        vm.prank(ocgTimelock);
        oldConfig.setRebalancer(newPoolAddress);
    }

    // given the replacement has completed
    //   when its steps are repeated
    //     [X] a second liquidity pull reverts with CCIPBridgeConfig_ZeroAmount (the source
    //         is empty)
    //     [X] the outgoing disables revert with NotEnabled
    //     [X] the kernel deactivations revert with Kernel_PolicyNotActivated
    //     [X] the route recreation reverts with ChainAlreadyExists
    function test_givenReplacementComplete_repeatedStepsRevertPredictably() public {
        _deployReplacementAndDaoBatch(false);
        _ocgProposalMigrateToNewStack();
        _daoBatchDeactivateOldPair();
        address oldPoolAddress = address(pool);
        uint64 firstSelector = burnMintRoutes[0].chainSelector;

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPBridgeConfig.CCIPBridgeConfig_ZeroAmount.selector)
        );
        vm.prank(ocgTimelock);
        config.transferLiquidity(oldPoolAddress, 0);

        _expectRevertNotEnabled();
        vm.prank(ocgTimelock);
        oldConfig.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(Kernel.Kernel_PolicyNotActivated.selector, address(oldConfig))
        );
        vm.prank(daoMS);
        kernel.executeAction(Actions.DeactivatePolicy, address(oldConfig));

        _expectRevertChainAlreadyExists(firstSelector);
        vm.prank(ocgTimelock);
        config.addChain(_toChainUpdate(burnMintRoutes[0]));
    }
}
