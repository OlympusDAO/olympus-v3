// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPLiquidityContainer} from "src/external/bridge/ICCIPLiquidityContainer.sol";
import {ICCIPLockReleaseTokenPool} from "src/external/bridge/ICCIPLockReleaseTokenPool.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";

// Contracts
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPTokenPoolConfigTest} from "./CCIPTokenPoolConfigTest.sol";

contract CCIPTokenPoolConfigTests_transferLiquidity is CCIPTokenPoolConfigTest {
    /// @notice The default transfer amount: 0.25 OHM in base units (9 decimals).
    uint256 internal constant TRANSFER_AMOUNT = 250_000_000;

    // given the policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.transferLiquidity(makeAddr("someSource"), TRANSFER_AMOUNT);
    }

    // given the policy is disabled
    //   when the caller does not hold the admin role
    //     [X] it reverts with NotEnabled
    function test_givenDisabled_whenCallerIsNotAdmin_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.transferLiquidity(makeAddr("someSource"), TRANSFER_AMOUNT);
    }

    // when the caller does not hold the admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // The fuzz excludes the admin account and the zero address
    function test_whenCallerIsNotAdmin_reverts(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted givenLiquiditySourceConfigured {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(0));

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        config.transferLiquidity(address(sourcePool), TRANSFER_AMOUNT);
    }

    // given the config operator is set
    //   when the caller is the config operator
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Role asymmetry: the route delegate cannot move treasury liquidity
    function test_whenCallerIsConfigOperator_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenConfigOperatorSet
        givenLiquiditySourceConfigured
    {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(operator);
        config.transferLiquidity(address(sourcePool), TRANSFER_AMOUNT);
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsBridgeAdmin_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenLiquiditySourceConfigured
    {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeAdmin);
        config.transferLiquidity(address(sourcePool), TRANSFER_AMOUNT);
    }

    // when the caller holds only the emergency role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsEmergency_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenLiquiditySourceConfigured
    {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(emergency);
        config.transferLiquidity(address(sourcePool), TRANSFER_AMOUNT);
    }

    // when the caller does not hold the admin role
    //   when the amount is zero
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Pins the masking order: the role check answers before the validation
    function test_whenCallerIsNotAdmin_whenAmountIsZero_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller);
        config.transferLiquidity(makeAddr("someSource"), 0);
    }

    // given the pool is not a liquidity container
    //   [X] it reverts with CCIPTokenPoolConfig_NotLiquidityContainer
    // The burn/mint rig: the immutable probe result gates the liquidity surface
    function test_givenPoolIsNotLiquidityContainer_reverts()
        public
        givenBurnMintPoolRig
        givenEnabled
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_NotLiquidityContainer.selector
            )
        );
        vm.prank(admin);
        config.transferLiquidity(makeAddr("someSource"), TRANSFER_AMOUNT);
    }

    // given the pool is not a liquidity container
    //   when the from address is zero
    //     [X] it reverts with CCIPTokenPoolConfig_NotLiquidityContainer
    // Pins the order: the container gate answers before the argument checks
    function test_givenPoolIsNotLiquidityContainer_whenFromIsZero_reverts()
        public
        givenBurnMintPoolRig
        givenEnabled
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_NotLiquidityContainer.selector
            )
        );
        vm.prank(admin);
        config.transferLiquidity(address(0), TRANSFER_AMOUNT);
    }

    // when the from address is zero
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidAddress("from")
    function test_whenFromIsZero_reverts() public givenEnabled givenPoolOwnershipAccepted {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidAddress.selector,
                "from"
            )
        );
        vm.prank(admin);
        config.transferLiquidity(address(0), TRANSFER_AMOUNT);
    }

    // when the from address is zero
    //   when the amount is zero
    //     [X] it reverts with CCIPTokenPoolConfig_InvalidAddress("from")
    // Pins the order: the address check answers before the amount check
    function test_whenFromIsZero_whenAmountIsZero_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidAddress.selector,
                "from"
            )
        );
        vm.prank(admin);
        config.transferLiquidity(address(0), 0);
    }

    // when the amount is zero
    //   [X] it reverts with CCIPTokenPoolConfig_ZeroAmount
    // Chainlink accepts a zero amount and would emit transfer events for nothing; the
    // config-only check closes the gap.
    function test_whenAmountIsZero_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenLiquiditySourceConfigured
    {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolConfig.CCIPTokenPoolConfig_ZeroAmount.selector)
        );
        vm.prank(admin);
        config.transferLiquidity(address(sourcePool), 0);
    }

    // when the amount is zero
    //   given the pool is owned by an unrelated third party
    //     [X] it reverts with CCIPTokenPoolConfig_ZeroAmount
    // Pins the order: the config validation answers before the pool's owner check
    function test_whenAmountIsZero_givenPoolOwnedByThirdParty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolConfig.CCIPTokenPoolConfig_ZeroAmount.selector)
        );
        vm.prank(admin);
        config.transferLiquidity(makeAddr("someSource"), 0);
    }

    // given the pool is owned by an unrelated third party
    //   [X] it reverts with OnlyCallableByOwner
    function test_givenPoolOwnedByThirdParty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenLiquiditySourceConfigured
        givenPoolOwnedByThirdParty
    {
        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.transferLiquidity(address(sourcePool), TRANSFER_AMOUNT);
    }

    // when the from address holds no code
    //   [X] it reverts with empty revert data
    // Chainlink performs no code check on the source; the void call to an EOA fails on the
    // compiler's extcodesize check. Pinned as documented behavior, not a typed error.
    function test_whenFromHasNoCode_reverts() public givenEnabled givenPoolOwnershipAccepted {
        address codelessSource = makeAddr("codelessSource");

        // The empty byte string matches only a revert with no data: no typed error exists on
        // this path, and this is the single permitted empty revert match of the suite
        vm.expectRevert(bytes(""));
        vm.prank(admin);
        config.transferLiquidity(codelessSource, TRANSFER_AMOUNT);
    }

    // given the source pool's rebalancer is not the primary pool
    //   [X] it reverts with Unauthorized carrying the primary pool address
    // The error names the pool (the withdrawLiquidity caller), not the config or the user
    function test_givenFromRebalancerIsNotPool_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenLiquiditySourceRebalancerUnset
    {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.Unauthorized.selector, address(pool))
        );
        vm.prank(admin);
        config.transferLiquidity(address(sourcePool), TRANSFER_AMOUNT);
    }

    // when the amount exceeds the source balance
    //   [X] it reverts with InsufficientLiquidity
    // The failing boundary side: amount is the source balance plus one
    function test_whenAmountExceedsFromBalance_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenLiquiditySourceConfigured
    {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPLockReleaseTokenPool.InsufficientLiquidity.selector)
        );
        vm.prank(admin);
        config.transferLiquidity(address(sourcePool), SOURCE_POOL_FUNDING + 1);
    }

    // when the amount is the uint256 maximum
    //   [X] it reverts with InsufficientLiquidity
    function test_whenAmountIsMax_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenLiquiditySourceConfigured
    {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPLockReleaseTokenPool.InsufficientLiquidity.selector)
        );
        vm.prank(admin);
        config.transferLiquidity(address(sourcePool), type(uint256).max);
    }

    // when the caller holds the admin role
    //   [X] the source balance decreases by the amount
    //   [X] the primary pool balance increases by the amount
    //   [X] the config balance stays zero
    //   [X] the source emits LiquidityRemoved, the pool LiquidityTransferred and the config
    //       PoolLiquidityTransferred
    // The tokens move directly between the pools; the three-way delta pins the absence of
    // any residue on the config.
    function test_whenCallerIsAdmin()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenLiquiditySourceConfigured
    {
        uint256 sourceBalanceBefore = ohm.balanceOf(address(sourcePool));
        uint256 poolBalanceBefore = ohm.balanceOf(address(pool));

        // The withdrawal on the source emits first, then the pool, then the config
        vm.expectEmit(true, true, true, true, address(sourcePool));
        emit ICCIPLiquidityContainer.LiquidityRemoved(address(pool), TRANSFER_AMOUNT);
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPLockReleaseTokenPool.LiquidityTransferred(address(sourcePool), TRANSFER_AMOUNT);
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolLiquidityTransferred(address(sourcePool), TRANSFER_AMOUNT);
        vm.prank(admin);
        config.transferLiquidity(address(sourcePool), TRANSFER_AMOUNT);

        // Source: 1_000_000_000 - 250_000_000 = 750_000_000 base units (9 decimals)
        assertEq(
            ohm.balanceOf(address(sourcePool)),
            sourceBalanceBefore - TRANSFER_AMOUNT,
            "the source balance should decrease by the amount"
        );
        // Pool: 0 + 250_000_000 = 250_000_000 base units (9 decimals)
        assertEq(
            ohm.balanceOf(address(pool)),
            poolBalanceBefore + TRANSFER_AMOUNT,
            "the pool balance should increase by the amount"
        );
        assertEq(ohm.balanceOf(address(config)), 0, "no tokens should land on the config policy");
    }

    // when the amount equals the source balance
    //   [X] it drains the source exactly
    // The passing boundary side: the pool-side check is balance strictly below amount
    function test_whenAmountEqualsFromBalance()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenLiquiditySourceConfigured
    {
        uint256 poolBalanceBefore = ohm.balanceOf(address(pool));

        vm.prank(admin);
        config.transferLiquidity(address(sourcePool), SOURCE_POOL_FUNDING);

        // Source: 1_000_000_000 - 1_000_000_000 = 0 base units; the exact drain passes
        // because the pool-side check is balance < amount, not balance <= amount
        assertEq(
            ohm.balanceOf(address(sourcePool)),
            0,
            "the source should be drained exactly to zero"
        );
        assertEq(
            ohm.balanceOf(address(pool)),
            poolBalanceBefore + SOURCE_POOL_FUNDING,
            "the pool should receive the full source balance"
        );
    }

    // given a partial transfer occurred
    //   [X] a second transfer moves the remaining balance
    //   [X] the deltas accumulate and the source ends drained exactly
    // Repeatability: nothing on the path is one-shot, and the second call composes with the
    // state the first one left behind.
    function test_givenPartialTransferOccurred()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenLiquiditySourceConfigured
    {
        uint256 poolBalanceBefore = ohm.balanceOf(address(pool));

        vm.prank(admin);
        config.transferLiquidity(address(sourcePool), TRANSFER_AMOUNT);

        // Remainder after the partial transfer:
        // 1_000_000_000 - 250_000_000 = 750_000_000 base units (9 decimals)
        uint256 remainder = SOURCE_POOL_FUNDING - TRANSFER_AMOUNT;
        assertEq(
            ohm.balanceOf(address(sourcePool)),
            remainder,
            "the partial transfer should leave the remainder on the source"
        );

        vm.prank(admin);
        config.transferLiquidity(address(sourcePool), remainder);

        // Accumulated deltas: 250_000_000 + 750_000_000 = 1_000_000_000 base units moved
        assertEq(
            ohm.balanceOf(address(sourcePool)),
            0,
            "the second transfer should drain the source"
        );
        assertEq(
            ohm.balanceOf(address(pool)),
            poolBalanceBefore + SOURCE_POOL_FUNDING,
            "the pool should accumulate both transfers"
        );
        assertEq(ohm.balanceOf(address(config)), 0, "no tokens should land on the config policy");
    }

    // when the from address is the primary pool itself
    //   [X] it succeeds as a self-transfer no-op with unchanged balances
    //   [X] all three events are still emitted
    // Aliasing: the primary pool is set as its own rebalancer first; without that the call
    // reverts with Unauthorized.
    function test_whenFromIsThePoolItself() public givenEnabled givenPoolOwnershipAccepted {
        // The primary pool becomes its own rebalancer through the config, and holds a balance
        // for the self-withdrawal to pass its own balance check
        vm.prank(admin);
        config.setRebalancer(address(pool));
        ohm.mint(address(pool), TRANSFER_AMOUNT);

        uint256 poolBalanceBefore = ohm.balanceOf(address(pool));

        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPLiquidityContainer.LiquidityRemoved(address(pool), TRANSFER_AMOUNT);
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPLockReleaseTokenPool.LiquidityTransferred(address(pool), TRANSFER_AMOUNT);
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolLiquidityTransferred(address(pool), TRANSFER_AMOUNT);
        vm.prank(admin);
        config.transferLiquidity(address(pool), TRANSFER_AMOUNT);

        assertEq(
            ohm.balanceOf(address(pool)),
            poolBalanceBefore,
            "the self-transfer should leave the pool balance unchanged"
        );
        assertEq(ohm.balanceOf(address(config)), 0, "no tokens should land on the config policy");
    }
}
