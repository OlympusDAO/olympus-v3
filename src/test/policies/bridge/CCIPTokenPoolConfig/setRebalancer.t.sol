// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPLiquidityContainer} from "src/external/bridge/ICCIPLiquidityContainer.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";

// Contracts
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPTokenPoolConfigTest} from "./CCIPTokenPoolConfigTest.sol";

contract CCIPTokenPoolConfigTests_setRebalancer is CCIPTokenPoolConfigTest {
    // given the policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.setRebalancer(thirdParty);
    }

    // given the policy is disabled
    //   when the caller does not hold the admin role
    //     [X] it reverts with NotEnabled
    function test_givenDisabled_whenCallerIsNotAdmin_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.setRebalancer(thirdParty);
    }

    // when the caller does not hold the admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // The fuzz excludes the admin account and the zero address
    function test_whenCallerIsNotAdmin_reverts(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(0));

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        config.setRebalancer(thirdParty);
    }

    // given the config operator is set
    //   when the caller is the config operator
    //     [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsConfigOperator_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenConfigOperatorSet
    {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(operator);
        config.setRebalancer(thirdParty);
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsBridgeAdmin_reverts() public givenEnabled givenPoolOwnershipAccepted {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeAdmin);
        config.setRebalancer(thirdParty);
    }

    // when the caller holds only the emergency role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled givenPoolOwnershipAccepted {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(emergency);
        config.setRebalancer(thirdParty);
    }

    // when the caller does not hold the admin role
    //   given the pool is not a liquidity container
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Pins the masking order: the role check answers before the container gate
    function test_whenCallerIsNotAdmin_givenPoolIsNotLiquidityContainer_reverts()
        public
        givenBurnMintPoolRig
        givenEnabled
    {
        address caller = makeAddr("unauthorizedCaller");
        assertFalse(config.isLiquidityContainer(), "the burn/mint pool is not a container");

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller);
        config.setRebalancer(thirdParty);
    }

    // given the pool is not a liquidity container
    //   [X] it reverts with CCIPTokenPoolConfig_NotLiquidityContainer
    // The burn/mint rig: the immutable probe result gates the whole liquidity surface, and
    // the gate is also what keeps the lock/release-typed call from reverting raw on a pool
    // without the selector.
    function test_givenPoolIsNotLiquidityContainer_reverts()
        public
        givenBurnMintPoolRig
        givenEnabled
    {
        assertFalse(config.isLiquidityContainer(), "the burn/mint pool is not a container");

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_NotLiquidityContainer.selector
            )
        );
        vm.prank(admin);
        config.setRebalancer(thirdParty);
    }

    // given the pool is not a liquidity container
    //   given the pool is owned by an unrelated third party
    //     [X] it reverts with CCIPTokenPoolConfig_NotLiquidityContainer
    // Pins the order: the container gate answers before the pool is called at all
    function test_givenPoolIsNotLiquidityContainer_givenPoolOwnedByThirdParty_reverts()
        public
        givenBurnMintPoolRig
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        assertEq(burnMintPool.owner(), thirdParty, "the third party should own the pool");

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_NotLiquidityContainer.selector
            )
        );
        vm.prank(admin);
        config.setRebalancer(thirdParty);
    }

    // given the pool is owned by an unrelated third party
    //   [X] it reverts with OnlyCallableByOwner
    function test_givenPoolOwnedByThirdParty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        address candidate = makeAddr("rebalancerCandidate");

        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.setRebalancer(candidate);

        assertEq(pool.getRebalancer(), address(0), "the pool rebalancer should be unchanged");
    }

    // when the caller holds the admin role
    //   [X] the pool reports the new rebalancer through getRebalancer
    //   [X] it emits PoolRebalancerSet
    //   [X] the pool emits no event of its own
    // The config event is the only log of the change (the pool is silent); the absence claim
    // needs vm.recordLogs.
    function test_whenCallerIsAdmin() public givenEnabled givenPoolOwnershipAccepted {
        address candidate = makeAddr("rebalancerCandidate");
        assertEq(pool.getRebalancer(), address(0), "the pool rebalancer should start unset");

        vm.recordLogs();
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolRebalancerSet(candidate);
        vm.prank(admin);
        config.setRebalancer(candidate);

        assertEq(pool.getRebalancer(), candidate, "the pool rebalancer should be the candidate");

        // The pool writes its rebalancer silently, so the config event is the only log of the
        // change; the expected event emitted by this test contract is filtered out by emitter
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(
            _countLogsFrom(logs, address(pool)),
            0,
            "the pool should emit no event of its own"
        );
        assertEq(
            _countLogsFrom(logs, address(config)),
            1,
            "the config should emit exactly one event"
        );
    }

    // when the rebalancer is the zero address
    //   [X] it clears the rebalancer and emits PoolRebalancerSet with zero
    // Zero is a meaningful value here; a non-zero rebalancer is set first
    function test_whenRebalancerIsZeroAddress() public givenEnabled givenPoolOwnershipAccepted {
        address candidate = makeAddr("rebalancerCandidate");

        vm.prank(admin);
        config.setRebalancer(candidate);
        assertEq(pool.getRebalancer(), candidate, "the pool rebalancer should be the candidate");

        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolRebalancerSet(address(0));
        vm.prank(admin);
        config.setRebalancer(address(0));

        assertEq(pool.getRebalancer(), address(0), "the pool rebalancer should be cleared");
    }

    // when the value equals the current rebalancer
    //   [X] it writes and emits PoolRebalancerSet again
    function test_whenValueEqualsCurrentValue() public givenEnabled givenPoolOwnershipAccepted {
        address candidate = makeAddr("rebalancerCandidate");

        vm.prank(admin);
        config.setRebalancer(candidate);

        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolRebalancerSet(candidate);
        vm.prank(admin);
        config.setRebalancer(candidate);

        assertEq(pool.getRebalancer(), candidate, "the pool rebalancer should be unchanged");
    }

    // when the rebalancer is any address
    //   [X] the pool reports that address
    // No candidate validation exists; EOAs are legal. Fuzzed over the address domain.
    function test_whenRebalancerIsAnyAddress(
        address rebalancer_
    ) public givenEnabled givenPoolOwnershipAccepted {
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolRebalancerSet(rebalancer_);
        vm.prank(admin);
        config.setRebalancer(rebalancer_);

        assertEq(pool.getRebalancer(), rebalancer_, "the pool rebalancer should be the argument");
    }

    // given a rebalancer was set
    //   [X] the holder can withdraw liquidity from the pool
    // The observable effect of the write beyond the getter: the pool's rebalancer gate opens
    // for the new holder. The pool is funded with OHM first.
    function test_givenRebalancerSet_holderCanWithdrawLiquidity()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address rebalancer = makeAddr("liquidityRebalancer");
        // 1 OHM in base units at 9 decimals
        uint256 funding = 1_000_000_000;
        ohm.mint(address(pool), funding);

        // Before the write the pool rejects the holder by name
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.Unauthorized.selector, rebalancer)
        );
        vm.prank(rebalancer);
        pool.withdrawLiquidity(funding);

        vm.prank(admin);
        config.setRebalancer(rebalancer);

        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPLiquidityContainer.LiquidityRemoved(rebalancer, funding);
        vm.prank(rebalancer);
        pool.withdrawLiquidity(funding);

        assertEq(ohm.balanceOf(rebalancer), funding, "the holder should hold the withdrawn OHM");
        assertEq(ohm.balanceOf(address(pool)), 0, "the pool should hold no OHM afterwards");
    }
}
