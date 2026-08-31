// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";

import {CCIPBridgeConfigTest} from "./CCIPBridgeConfigTest.sol";

contract CCIPBridgeConfigTests_isChainDisabled is CCIPBridgeConfigTest {
    // when the route does not exist
    //   [X] it reverts with NonExistentChain carrying the selector
    // Deliberate revert instead of false: "no such route" must not read as "route is open".
    // The pool getters would return empty structs for the unknown selector.
    function test_whenRouteDoesNotExist_reverts() public givenEnabled givenPoolOwnershipAccepted {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_A)
        );
        config.isChainDisabled(CHAIN_SELECTOR_A);
    }

    // given the route is contained
    //   [X] it returns true
    function test_givenRouteContained()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenRouteContained
    {
        assertTrue(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the contained route should read as disabled"
        );
    }

    // given the route carries normal limits
    //   [X] it returns false
    function test_givenRouteNormal()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        assertFalse(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the route with normal limits should read as not disabled"
        );
    }

    // given only the outbound bucket is contained
    //   [X] it returns false
    // Reached through setChainRateLimits with the containment shape outbound only; a
    // half-contained route is reported as not disabled.
    function test_givenOnlyOutboundContained()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, _containmentConfig(), _defaultInboundConfig());

        assertFalse(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the half-contained route should read as not disabled"
        );
    }

    // given only the inbound bucket is contained
    //   [X] it returns false
    function test_givenOnlyInboundContained()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, _defaultOutboundConfig(), _containmentConfig());

        assertFalse(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the half-contained route should read as not disabled"
        );
    }

    // given the contained route was drained
    //   [X] it returns true
    // The fill level does not matter: only isEnabled, capacity and rate are compared
    function test_givenContainedRouteDrained()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenRouteContained
    {
        // The contained buckets hold two base units each; real transfers consume the
        // outbound fill down to zero and the inbound fill down to one
        _consumeOutbound(CHAIN_SELECTOR_A, 2);
        _consumeInbound(CHAIN_SELECTOR_A, 1);

        assertTrue(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the drained contained route should still read as disabled"
        );
    }

    // given a normal route was drained to zero
    //   [X] it returns false
    // A drained bucket at a normal config is not contained; the fill is irrelevant on the
    // false side too. Needs the drain helper.
    function test_givenNormalRouteDrained()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        _setBucketFills(CHAIN_SELECTOR_A, 0, 0);

        assertFalse(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the drained route with normal limits should read as not disabled"
        );
    }

    // given the limits were set manually to the containment shape
    //   [X] it returns true
    // {true, 2, 1} written through setChainRateLimits is indistinguishable from containment;
    // at that capacity no transfer passes, so the answer stays operationally correct.
    function test_givenLimitsSetManuallyToContainmentShape()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, _containmentConfig(), _containmentConfig());

        assertTrue(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the manually written containment shape should read as disabled"
        );
    }

    // given a bucket capacity is three with rate one
    //   [X] it returns false
    // The capacity boundary one unit above the containment constant
    function test_givenCapacityIsThree()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        // {true, 3, 1} differs from the containment constant {true, 2, 1} only in the
        // capacity, so the comparison fails on the capacity term alone
        vm.prank(admin);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _rateLimiterConfig(true, 3, 1),
            _rateLimiterConfig(true, 3, 1)
        );

        assertFalse(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the capacity of three should read as not disabled"
        );
    }

    // given the policy is disabled
    //   [X] it answers for a contained route
    // The view carries no lifecycle gate and serves monitors during a freeze
    function test_givenPolicyDisabled()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenRouteContained
        givenDisabled
    {
        assertFalse(config.isEnabled(), "the policy should be disabled");

        assertTrue(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the view should answer while the policy is disabled"
        );
    }
}
