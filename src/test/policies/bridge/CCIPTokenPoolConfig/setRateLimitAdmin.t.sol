// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";

// Contracts
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPTokenPoolConfigTest} from "./CCIPTokenPoolConfigTest.sol";

contract CCIPTokenPoolConfigTests_setRateLimitAdmin is CCIPTokenPoolConfigTest {
    // given the policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.setRateLimitAdmin(thirdParty);
    }

    // given the policy is disabled
    //   when the caller does not hold the admin role
    //     [X] it reverts with NotEnabled
    function test_givenDisabled_whenCallerIsNotAdmin_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.setRateLimitAdmin(thirdParty);
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
        config.setRateLimitAdmin(thirdParty);
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
        config.setRateLimitAdmin(thirdParty);
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsBridgeAdmin_reverts() public givenEnabled givenPoolOwnershipAccepted {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeAdmin);
        config.setRateLimitAdmin(thirdParty);
    }

    // when the caller holds only the bridge rate limiter role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // The policy-side rate limit role cannot appoint the pool-side rate limit admin; the
    // similar names invite exactly this mistake.
    function test_whenCallerIsBridgeRateLimiter_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeRateLimiter);
        config.setRateLimitAdmin(bridgeRateLimiter);
    }

    // when the caller holds only the emergency role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled givenPoolOwnershipAccepted {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(emergency);
        config.setRateLimitAdmin(thirdParty);
    }

    // when the caller does not hold the admin role
    //   given the pool is owned by an unrelated third party
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Pins the masking order: the role check answers before the pool's owner check
    function test_whenCallerIsNotAdmin_givenPoolOwnedByThirdParty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller);
        config.setRateLimitAdmin(caller);
    }

    // given the pool is owned by an unrelated third party
    //   [X] it reverts with OnlyCallableByOwner
    function test_givenPoolOwnedByThirdParty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.setRateLimitAdmin(thirdParty);

        assertEq(pool.getRateLimitAdmin(), address(0), "the rate limit admin should be unchanged");
    }

    // when the caller holds the admin role
    //   [X] the pool reports the new admin through getRateLimitAdmin
    //   [X] the pool emits RateLimitAdminSet
    //   [X] it emits PoolRateLimitAdminSet
    function test_whenCallerIsAdmin() public givenEnabled givenPoolOwnershipAccepted {
        address rateLimitAdmin = makeAddr("poolRateLimitAdmin");
        assertEq(pool.getRateLimitAdmin(), address(0), "the rate limit admin should start unset");

        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.RateLimitAdminSet(rateLimitAdmin);
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolRateLimitAdminSet(rateLimitAdmin);
        vm.prank(admin);
        config.setRateLimitAdmin(rateLimitAdmin);

        assertEq(
            pool.getRateLimitAdmin(),
            rateLimitAdmin,
            "the rate limit admin should be the new holder"
        );
    }

    // when the rate limit admin is the zero address
    //   [X] it clears the role and emits both events with zero
    //   [X] the former holder can no longer write pool limits directly
    // Zero is the intended steady state; clearing revokes the direct pool-side bypass. A
    // non-zero holder is set first.
    function test_whenRateLimitAdminIsZeroAddress()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        address rateLimitAdmin = makeAddr("poolRateLimitAdmin");
        vm.prank(admin);
        config.setRateLimitAdmin(rateLimitAdmin);

        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.RateLimitAdminSet(address(0));
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolRateLimitAdminSet(address(0));
        vm.prank(admin);
        config.setRateLimitAdmin(address(0));

        assertEq(pool.getRateLimitAdmin(), address(0), "the rate limit admin should be cleared");

        // The pool names the rejected caller: the former holder is now neither the owner nor
        // the rate limit admin
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.Unauthorized.selector, rateLimitAdmin)
        );
        vm.prank(rateLimitAdmin);
        ICCIPTokenPoolAdmin(address(pool)).setChainRateLimiterConfig(
            CHAIN_SELECTOR_A,
            _containmentConfig(),
            _containmentConfig()
        );
    }

    // when the value equals the current rate limit admin
    //   [X] it writes and emits both events again
    function test_whenValueEqualsCurrentValue() public givenEnabled givenPoolOwnershipAccepted {
        address rateLimitAdmin = makeAddr("poolRateLimitAdmin");
        vm.prank(admin);
        config.setRateLimitAdmin(rateLimitAdmin);

        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.RateLimitAdminSet(rateLimitAdmin);
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolRateLimitAdminSet(rateLimitAdmin);
        vm.prank(admin);
        config.setRateLimitAdmin(rateLimitAdmin);

        assertEq(
            pool.getRateLimitAdmin(),
            rateLimitAdmin,
            "the rate limit admin should be unchanged"
        );
    }

    // when the rate limit admin is any address
    //   [X] the pool reports that address
    // No candidate validation exists. Fuzzed over the address domain.
    function test_whenRateLimitAdminIsAnyAddress(
        address rateLimitAdmin_
    ) public givenEnabled givenPoolOwnershipAccepted {
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolRateLimitAdminSet(rateLimitAdmin_);
        vm.prank(admin);
        config.setRateLimitAdmin(rateLimitAdmin_);

        assertEq(
            pool.getRateLimitAdmin(),
            rateLimitAdmin_,
            "the rate limit admin should be the argument"
        );
    }

    // given the pool is a burn/mint pool
    //   [X] it sets the rate limit admin
    // Unlike setRebalancer and transferLiquidity, no liquidity-container gate exists: the
    // rate limit admin is a base TokenPool role. Pins the sibling asymmetry.
    function test_givenPoolIsBurnMintPool()
        public
        givenBurnMintPoolRig
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address rateLimitAdmin = makeAddr("poolRateLimitAdmin");
        assertFalse(config.isLiquidityContainer(), "the burn/mint pool is not a container");
        assertEq(burnMintPool.owner(), address(config), "the config should own the pool");

        vm.expectEmit(true, true, true, true, address(burnMintPool));
        emit ICCIPTokenPoolAdmin.RateLimitAdminSet(rateLimitAdmin);
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolRateLimitAdminSet(rateLimitAdmin);
        vm.prank(admin);
        config.setRateLimitAdmin(rateLimitAdmin);

        assertEq(
            burnMintPool.getRateLimitAdmin(),
            rateLimitAdmin,
            "the burn/mint pool should report the new rate limit admin"
        );
    }

    // given a rate limit admin was set
    //   [X] the holder can call setChainRateLimiterConfig on the pool directly
    // The documented bypass: the holder writes limits with none of the config's enabled gate,
    // validation or events, which is why the role is expected to stay zero.
    function test_givenRateLimitAdminSet_holderCanWritePoolLimitsDirectly()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        address rateLimitAdmin = makeAddr("poolRateLimitAdmin");
        vm.prank(admin);
        config.setRateLimitAdmin(rateLimitAdmin);

        // The disabled shape {false, 0, 0} is one the config's own validation rejects
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RateLimiterDisabled.selector
            )
        );
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, _disabledConfig(), _disabledConfig());

        // The holder writes the same shape straight on the pool
        vm.prank(rateLimitAdmin);
        ICCIPTokenPoolAdmin(address(pool)).setChainRateLimiterConfig(
            CHAIN_SELECTOR_A,
            _disabledConfig(),
            _disabledConfig()
        );

        _assertBucket(
            _outboundBucket(CHAIN_SELECTOR_A),
            false,
            0,
            0,
            0,
            "outbound after the direct write"
        );
        _assertBucket(
            _inboundBucket(CHAIN_SELECTOR_A),
            false,
            0,
            0,
            0,
            "inbound after the direct write"
        );
    }

    // when the rate limit admin is the config itself
    //   [X] the pool reports the config
    //   [X] the rate limiter and containment functions keep working after an ownership
    //       migration
    // The aliasing case that builds the split-authority state the other passes lean on
    function test_whenRateLimitAdminIsConfigItself()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        address configAddress = address(config);

        vm.prank(admin);
        config.setRateLimitAdmin(configAddress);
        assertEq(
            pool.getRateLimitAdmin(),
            configAddress,
            "the rate limit admin should be the config"
        );

        // The ownership moves away, leaving the config with the rate limit authority only
        vm.prank(admin);
        config.transferPoolOwnership(thirdParty);
        vm.prank(thirdParty);
        pool.acceptOwnership();
        assertEq(pool.owner(), thirdParty, "the third party should own the pool");

        // The rate limit function still reaches the pool
        vm.prank(admin);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _rateLimiterConfig(true, 5_000, 50),
            _rateLimiterConfig(true, 6_000, 60)
        );
        _assertBucket(
            _outboundBucket(CHAIN_SELECTOR_A),
            true,
            5_000,
            50,
            5_000,
            "outbound after the rate limit write"
        );

        // The containment function still reaches the pool
        vm.prank(emergency);
        config.disableChain(CHAIN_SELECTOR_A);

        assertTrue(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the route should be contained after the migration"
        );

        // The route functions, which the pool gates on ownership, no longer do
        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_B));
    }
}
