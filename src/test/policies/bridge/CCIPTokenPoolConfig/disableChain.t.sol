// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";

import {CCIPTokenPoolConfigTest} from "./CCIPTokenPoolConfigTest.sol";

contract CCIPTokenPoolConfigTests_disableChain is CCIPTokenPoolConfigTest {
    // when the caller holds none of the four containment roles
    //   [X] it reverts with NotAuthorised
    // The fuzz excludes the emergency, admin, bridge admin and bridge rate limiter accounts
    // and the zero address.
    function test_whenCallerIsNotAuthorized_reverts(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted givenChainAdded {
        vm.assume(caller_ != emergency);
        vm.assume(caller_ != admin);
        vm.assume(caller_ != bridgeAdmin);
        vm.assume(caller_ != bridgeRateLimiter);
        vm.assume(caller_ != address(0));

        _expectRevertNotAuthorised();
        vm.prank(caller_);
        config.disableChain(CHAIN_SELECTOR_A);
    }

    // given the config operator is set
    //   when the caller is the config operator
    //     [X] it reverts with NotAuthorised
    // Role asymmetry: the operator configures routes but holds no containment authority
    function test_whenCallerIsConfigOperator_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenConfigOperatorSet
        givenChainAdded
    {
        _expectRevertNotAuthorised();
        vm.prank(operator);
        config.disableChain(CHAIN_SELECTOR_A);
    }

    // given the pool is owned by an unrelated third party
    //   when the route does not exist
    //     [X] it reverts with Unauthorized carrying the config address
    // Pins the pool-side masking: the pool checks its caller before the chain, so the
    // missing-route error is hidden behind the authorization error, unlike the route
    // functions which validate the route first.
    function test_givenPoolOwnedByThirdParty_whenRouteDoesNotExist_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        assertFalse(pool.isSupportedChain(CHAIN_SELECTOR_A), "the route should not exist");

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.Unauthorized.selector, address(config))
        );
        vm.prank(emergency);
        config.disableChain(CHAIN_SELECTOR_A);
    }

    // given the pool is owned by an unrelated third party
    //   [X] it reverts with Unauthorized carrying the config address
    function test_givenPoolOwnedByThirdParty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPoolOwnedByThirdParty
    {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.Unauthorized.selector, address(config))
        );
        vm.prank(emergency);
        config.disableChain(CHAIN_SELECTOR_A);
    }

    // when the route does not exist
    //   [X] it reverts with NonExistentChain carrying the selector
    // The error comes from the pool: the config performs no route check of its own
    function test_whenRouteDoesNotExist_reverts() public givenEnabled givenPoolOwnershipAccepted {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_A)
        );
        vm.prank(emergency);
        config.disableChain(CHAIN_SELECTOR_A);
    }

    // when the caller holds the emergency role
    //   [X] both buckets hold {true, 2, 1}
    //   [X] the full fills are clamped down to two units
    //   [X] isChainDisabled reports true
    //   [X] the pool emits ChainConfigured and it emits RouteDisabled
    // The main containment path with the full assertions
    function test_whenCallerIsEmergency()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.ChainConfigured(
            CHAIN_SELECTOR_A,
            _containmentConfig(),
            _containmentConfig()
        );
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.RouteDisabled(CHAIN_SELECTOR_A);
        vm.prank(emergency);
        config.disableChain(CHAIN_SELECTOR_A);

        // Both fills clamp from full down to the new capacity:
        // outbound min(2, 10_000) = 2, inbound min(2, 20_000) = 2 base units
        _assertBucket(_outboundBucket(CHAIN_SELECTOR_A), true, 2, 1, 2, "outbound");
        _assertBucket(_inboundBucket(CHAIN_SELECTOR_A), true, 2, 1, 2, "inbound");
        assertTrue(config.isChainDisabled(CHAIN_SELECTOR_A), "the route should read as disabled");
    }

    // when the caller holds the admin role
    //   [X] it contains the route
    function test_whenCallerIsAdmin()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.prank(admin);
        config.disableChain(CHAIN_SELECTOR_A);

        assertTrue(config.isChainDisabled(CHAIN_SELECTOR_A), "the admin should contain the route");
    }

    // when the caller holds the bridge admin role
    //   [X] it contains the route
    function test_whenCallerIsBridgeAdmin()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.prank(bridgeAdmin);
        config.disableChain(CHAIN_SELECTOR_A);

        assertTrue(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the bridge admin should contain the route"
        );
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it contains the route
    function test_whenCallerIsBridgeRateLimiter()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.prank(bridgeRateLimiter);
        config.disableChain(CHAIN_SELECTOR_A);

        assertTrue(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the bridge rate limiter should contain the route"
        );
    }

    // given the policy is disabled
    //   [X] it contains the route
    // No givenEnabled modifier exists on the containment functions: the emergency surface
    // survives the control-plane freeze, and the freeze-then-contain order works.
    function test_givenPolicyDisabled()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenDisabled
    {
        assertFalse(config.isEnabled(), "the policy should be disabled");

        vm.prank(emergency);
        config.disableChain(CHAIN_SELECTOR_A);

        assertTrue(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "containment should work while the policy is disabled"
        );
    }

    // given the policy was deactivated in the kernel
    //   [X] it contains the route
    // The cached ROLES keeps authorizing after DeactivatePolicy
    function test_givenPolicyDeactivatedInKernel()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPolicyDeactivatedInKernel
    {
        assertFalse(config.isActive(), "the policy should be deactivated in the kernel");

        vm.prank(emergency);
        config.disableChain(CHAIN_SELECTOR_A);

        assertTrue(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "containment should survive the kernel deactivation"
        );
    }

    // given the policy has never been enabled
    //   given the config is the pool rate limit admin
    //     [X] it contains the route
    // Before the first enable the config cannot own the pool (acceptance requires the
    // enabled policy), so this state is reachable only through the rate limit admin path;
    // the route is seeded directly on the pool.
    function test_givenNeverEnabled_givenConfigIsRateLimitAdmin()
        public
        givenConfigIsRateLimitAdmin
    {
        assertEq(config.lastTransitionAt(), 0, "the policy should never have been enabled");
        assertEq(pool.owner(), address(this), "the test contract should still own the pool");

        _seedRouteOnPool(
            CHAIN_SELECTOR_A,
            _defaultRemotePools(),
            REMOTE_TOKEN,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );

        vm.prank(emergency);
        config.disableChain(CHAIN_SELECTOR_A);

        assertTrue(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the rate limit admin path should contain the route before the first enable"
        );
    }

    // given the route is already contained
    //   [X] it succeeds, writes the same values and emits RouteDisabled again
    // Containment is idempotent; the pool also re-emits ChainConfigured
    function test_givenRouteAlreadyContained()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenRouteContained
    {
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.ChainConfigured(
            CHAIN_SELECTOR_A,
            _containmentConfig(),
            _containmentConfig()
        );
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.RouteDisabled(CHAIN_SELECTOR_A);
        vm.prank(emergency);
        config.disableChain(CHAIN_SELECTOR_A);

        _assertBucket(_outboundBucket(CHAIN_SELECTOR_A), true, 2, 1, 2, "outbound");
        assertTrue(config.isChainDisabled(CHAIN_SELECTOR_A), "the route should stay disabled");
    }

    // given a bucket fill is below two units
    //   [X] the fill stays at its level and is not raised to two
    // The clamp is min(2, tokens): containment never refills. Needs the drain helper.
    function test_givenBucketFillBelowTwo()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        // The outbound fill is drained to one base unit; the inbound bucket stays full
        _setBucketFills(CHAIN_SELECTOR_A, 1, DEFAULT_INBOUND_CAPACITY);

        vm.prank(emergency);
        config.disableChain(CHAIN_SELECTOR_A);

        // Outbound: min(2, 1) = 1, so containment preserves the drained level instead of
        // refilling it; inbound: min(2, 20_000) = 2 base units. Same block, so no refill
        // lands between the drain and the containment.
        _assertBucket(_outboundBucket(CHAIN_SELECTOR_A), true, 2, 1, 1, "outbound");
        _assertBucket(_inboundBucket(CHAIN_SELECTOR_A), true, 2, 1, 2, "inbound");
    }

    // given the pool is owned by a third party and the config is the rate limit admin
    //   [X] it contains the route
    // Containment survives a pool ownership migration through the rate limit admin path
    function test_givenConfigIsRateLimitAdminOnly()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPoolOwnedByThirdParty
        givenConfigIsRateLimitAdmin
    {
        assertEq(pool.owner(), thirdParty, "the third party should own the pool");
        assertEq(
            pool.getRateLimitAdmin(),
            address(config),
            "the config should be the rate limit admin"
        );

        vm.prank(emergency);
        config.disableChain(CHAIN_SELECTOR_A);

        assertTrue(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "containment should survive the ownership migration"
        );
    }

    // given another route exists
    //   [X] the sibling route keeps its configs and fills
    function test_givenAnotherRouteExists()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenSecondChainAdded
    {
        RouteSnapshot memory routeBBefore = _snapshotRoute(CHAIN_SELECTOR_B);

        vm.prank(emergency);
        config.disableChain(CHAIN_SELECTOR_A);

        _assertRouteEqualsSnapshot(CHAIN_SELECTOR_B, routeBBefore, "route B");
        assertFalse(config.isChainDisabled(CHAIN_SELECTOR_B), "the sibling route should stay live");
    }

    // [X] the buckets after containment equal getDisabledRateLimiterConfig()
    // Read-back parity between the containment write and the advertised constant
    function test_matchesDisabledRateLimiterConfigView()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.prank(emergency);
        config.disableChain(CHAIN_SELECTOR_A);

        ICCIPRateLimiter.Config memory advertised = config.getDisabledRateLimiterConfig();
        _assertConfigEq(
            _toConfig(_outboundBucket(CHAIN_SELECTOR_A)),
            advertised,
            "outbound vs advertised"
        );
        _assertConfigEq(
            _toConfig(_inboundBucket(CHAIN_SELECTOR_A)),
            advertised,
            "inbound vs advertised"
        );
    }
}
