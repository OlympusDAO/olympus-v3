// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";

// Contracts
import {CCIPTokenPoolConfigTest} from "./CCIPTokenPoolConfigTest.sol";

contract CCIPTokenPoolConfigTests_setChainRateLimits is CCIPTokenPoolConfigTest {
    // ========== LIFECYCLE AND AUTHORIZATION ========== //

    // given the policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );
    }

    // given the policy is disabled
    //   when the caller is not authorized
    //     [X] it reverts with NotEnabled
    function test_givenDisabled_whenCallerIsNotAuthorized_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );
    }

    // when the caller holds none of the rate limiter role, the operator and the admin
    //   [X] it reverts with NotAuthorised
    // The fuzz excludes the admin, the operator, the bridge rate limiter and the zero address
    function test_whenCallerIsNotAuthorized_reverts(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted givenConfigOperatorSet givenChainAdded {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != operator);
        vm.assume(caller_ != bridgeRateLimiter);
        vm.assume(caller_ != address(0));

        _expectRevertNotAuthorised();
        vm.prank(caller_);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with NotAuthorised
    // The sharpest asymmetry of the contract: the containment-capable bridge admin cannot
    // touch normal rate limits, so it cannot restore what it contained.
    function test_whenCallerIsBridgeAdmin_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        _expectRevertNotAuthorised();
        vm.prank(bridgeAdmin);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );
    }

    // when the caller holds only the emergency role
    //   [X] it reverts with NotAuthorised
    function test_whenCallerIsEmergency_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        _expectRevertNotAuthorised();
        vm.prank(emergency);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );
    }

    // given the config operator is unset
    //   when the caller is the zero address
    //     [X] it reverts with NotAuthorised
    // _isConfigOperator rejects the zero address
    function test_givenOperatorUnset_whenCallerIsZeroAddress_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        assertEq(config.configOperator(), address(0), "the operator should be unset");

        _expectRevertNotAuthorised();
        vm.prank(address(0));
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );
    }

    // when the caller is not authorized
    //   when the route does not exist
    //     [X] it reverts with NotAuthorised
    // Pins the masking order: authorization answers before validation
    function test_whenCallerIsNotAuthorized_whenRouteMissing_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address caller = makeAddr("unauthorizedCaller");
        assertFalse(pool.isSupportedChain(CHAIN_SELECTOR_A), "the route should not exist");

        _expectRevertNotAuthorised();
        vm.prank(caller);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );
    }

    // ========== VALIDATION REVERTS (mirror parity folded into each) ========== //

    // when the route does not exist
    //   [X] it reverts with NonExistentChain carrying the selector
    //   [X] validateSetChainRateLimits reverts with the same error
    function test_whenRouteDoesNotExist_reverts() public givenEnabled givenPoolOwnershipAccepted {
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.NonExistentChain.selector,
            CHAIN_SELECTOR_A
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );

        vm.expectRevert(err);
        config.validateSetChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );
    }

    // when the route does not exist
    //   when the outbound config is disabled
    //     [X] it reverts with NonExistentChain
    // Pins the order: the existence check runs before the config checks
    function test_whenRouteDoesNotExist_whenConfigInvalid_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_A)
        );
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, _disabledConfig(), _defaultInboundConfig());
    }

    // when the outbound config is disabled
    //   [X] it reverts with CCIPTokenPoolConfig_RateLimiterDisabled
    //   [X] validateSetChainRateLimits reverts with the same error
    // The input is {false, 0, 0}, which the pool itself would accept as an unlimited route:
    // the config-only check keeps every active route limited.
    function test_whenOutboundConfigIsDisabled_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RateLimiterDisabled.selector
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, _disabledConfig(), _defaultInboundConfig());

        vm.expectRevert(err);
        config.validateSetChainRateLimits(
            CHAIN_SELECTOR_A,
            _disabledConfig(),
            _defaultInboundConfig()
        );
    }

    // when the inbound config is disabled
    //   [X] it reverts with CCIPTokenPoolConfig_RateLimiterDisabled
    //   [X] validateSetChainRateLimits reverts with the same error
    function test_whenInboundConfigIsDisabled_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RateLimiterDisabled.selector
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, _defaultOutboundConfig(), _disabledConfig());

        vm.expectRevert(err);
        config.validateSetChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _disabledConfig()
        );
    }

    // when the outbound rate is zero
    //   [X] it reverts with InvalidRateLimitRate carrying the outbound config
    //   [X] validateSetChainRateLimits reverts with the same error
    function test_whenOutboundRateIsZero_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        ICCIPRateLimiter.Config memory outbound = _rateLimiterConfig(
            true,
            DEFAULT_OUTBOUND_CAPACITY,
            0
        );
        bytes memory err = abi.encodeWithSelector(
            ICCIPRateLimiter.InvalidRateLimitRate.selector,
            outbound
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, outbound, _defaultInboundConfig());

        vm.expectRevert(err);
        config.validateSetChainRateLimits(CHAIN_SELECTOR_A, outbound, _defaultInboundConfig());
    }

    // when the outbound rate equals the outbound capacity
    //   [X] it reverts with InvalidRateLimitRate carrying the outbound config
    //   [X] validateSetChainRateLimits reverts with the same error
    // The failing side of the strict rate < capacity boundary
    function test_whenOutboundRateEqualsCapacity_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        ICCIPRateLimiter.Config memory outbound = _rateLimiterConfig(
            true,
            DEFAULT_OUTBOUND_CAPACITY,
            DEFAULT_OUTBOUND_CAPACITY
        );
        bytes memory err = abi.encodeWithSelector(
            ICCIPRateLimiter.InvalidRateLimitRate.selector,
            outbound
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, outbound, _defaultInboundConfig());

        vm.expectRevert(err);
        config.validateSetChainRateLimits(CHAIN_SELECTOR_A, outbound, _defaultInboundConfig());
    }

    // when the outbound config is enabled with zero capacity and zero rate
    //   [X] it reverts with InvalidRateLimitRate
    //   [X] validateSetChainRateLimits reverts with the same error
    // {true, 0, 0} fails through the rate == 0 half of the compound predicate
    function test_whenOutboundConfigIsEnabledWithZeroCapacity_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        ICCIPRateLimiter.Config memory outbound = _rateLimiterConfig(true, 0, 0);
        bytes memory err = abi.encodeWithSelector(
            ICCIPRateLimiter.InvalidRateLimitRate.selector,
            outbound
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, outbound, _defaultInboundConfig());

        vm.expectRevert(err);
        config.validateSetChainRateLimits(CHAIN_SELECTOR_A, outbound, _defaultInboundConfig());
    }

    // when the inbound rate is zero
    //   [X] it reverts with InvalidRateLimitRate carrying the inbound config
    //   [X] validateSetChainRateLimits reverts with the same error
    function test_whenInboundRateIsZero_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        ICCIPRateLimiter.Config memory inbound = _rateLimiterConfig(
            true,
            DEFAULT_INBOUND_CAPACITY,
            0
        );
        bytes memory err = abi.encodeWithSelector(
            ICCIPRateLimiter.InvalidRateLimitRate.selector,
            inbound
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, _defaultOutboundConfig(), inbound);

        vm.expectRevert(err);
        config.validateSetChainRateLimits(CHAIN_SELECTOR_A, _defaultOutboundConfig(), inbound);
    }

    // when the inbound rate equals the inbound capacity
    //   [X] it reverts with InvalidRateLimitRate carrying the inbound config
    //   [X] validateSetChainRateLimits reverts with the same error
    function test_whenInboundRateEqualsCapacity_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        ICCIPRateLimiter.Config memory inbound = _rateLimiterConfig(
            true,
            DEFAULT_INBOUND_CAPACITY,
            DEFAULT_INBOUND_CAPACITY
        );
        bytes memory err = abi.encodeWithSelector(
            ICCIPRateLimiter.InvalidRateLimitRate.selector,
            inbound
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, _defaultOutboundConfig(), inbound);

        vm.expectRevert(err);
        config.validateSetChainRateLimits(CHAIN_SELECTOR_A, _defaultOutboundConfig(), inbound);
    }

    // when both configs are invalid
    //   [X] it reverts with InvalidRateLimitRate carrying the outbound config
    // Pins the validation order: the outbound config is checked before the inbound one
    function test_whenBothConfigsAreInvalid_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        ICCIPRateLimiter.Config memory outbound = _rateLimiterConfig(true, 10_000, 0);
        ICCIPRateLimiter.Config memory inbound = _rateLimiterConfig(true, 20_000, 0);

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPRateLimiter.InvalidRateLimitRate.selector, outbound)
        );
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // ========== POOL-SIDE REVERTS ========== //

    // given the pool is owned by an unrelated third party
    //   [X] it reverts with Unauthorized carrying the config address
    // The pool names the config, not the user, as the rejected caller; the config is neither
    // the owner nor the rate limit admin here.
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
        vm.prank(admin);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _rateLimiterConfig(true, 5_000, 50),
            _rateLimiterConfig(true, 6_000, 60)
        );
    }

    // ========== SUCCESSES ========== //

    // when the caller is an admin
    //   [X] both buckets carry the new configs
    //   [X] it emits RouteRateLimitsSet with the previous and the new configs
    //   [X] validateSetChainRateLimits returns for the same input before the call
    function test_whenCallerIsAdmin()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        ICCIPRateLimiter.Config memory outbound = _rateLimiterConfig(true, 5_000, 50);
        ICCIPRateLimiter.Config memory inbound = _rateLimiterConfig(true, 6_000, 60);
        config.validateSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);

        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.RouteRateLimitsSet(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig(),
            outbound,
            inbound
        );
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);

        // The buckets start full at 10_000 and 20_000; lowering the capacities clamps each
        // fill to min(newCapacity, tokens), which is the new capacity in both directions
        _assertBucket(
            _outboundBucket(CHAIN_SELECTOR_A),
            true,
            5_000,
            50,
            5_000,
            "outbound after the write"
        );
        _assertBucket(
            _inboundBucket(CHAIN_SELECTOR_A),
            true,
            6_000,
            60,
            6_000,
            "inbound after the write"
        );
    }

    // when the caller is the config operator
    //   [X] it sets both configs
    function test_whenCallerIsConfigOperator()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenConfigOperatorSet
        givenChainAdded
    {
        ICCIPRateLimiter.Config memory outbound = _rateLimiterConfig(true, 5_000, 50);
        ICCIPRateLimiter.Config memory inbound = _rateLimiterConfig(true, 6_000, 60);

        vm.prank(operator);
        config.setChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);

        _assertConfigEq(_toConfig(_outboundBucket(CHAIN_SELECTOR_A)), outbound, "outbound config");
        _assertConfigEq(_toConfig(_inboundBucket(CHAIN_SELECTOR_A)), inbound, "inbound config");
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it sets both configs
    // The third authorized class: the direct, non-timelocked rate limit operator
    function test_whenCallerIsBridgeRateLimiter()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        ICCIPRateLimiter.Config memory outbound = _rateLimiterConfig(true, 5_000, 50);
        ICCIPRateLimiter.Config memory inbound = _rateLimiterConfig(true, 6_000, 60);

        vm.prank(bridgeRateLimiter);
        config.setChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);

        _assertConfigEq(_toConfig(_outboundBucket(CHAIN_SELECTOR_A)), outbound, "outbound config");
        _assertConfigEq(_toConfig(_inboundBucket(CHAIN_SELECTOR_A)), inbound, "inbound config");
    }

    // given the pool is owned by a third party and the config is the pool rate limit admin
    //   [X] it sets both configs
    // The split-authority state: the route functions revert on this pool while the rate
    // limiter setter passes through the rateLimitAdmin half of the pool check.
    function test_givenConfigIsRateLimitAdminOnly()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPoolOwnedByThirdParty
        givenConfigIsRateLimitAdmin
    {
        ICCIPRateLimiter.Config memory outbound = _rateLimiterConfig(true, 5_000, 50);
        ICCIPRateLimiter.Config memory inbound = _rateLimiterConfig(true, 6_000, 60);
        assertEq(pool.owner(), thirdParty, "the third party should own the pool");
        assertEq(
            pool.getRateLimitAdmin(),
            address(config),
            "the config should be the pool rate limit admin"
        );

        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);

        _assertConfigEq(_toConfig(_outboundBucket(CHAIN_SELECTOR_A)), outbound, "outbound config");

        // The route functions stay gated on ownership, which the config no longer holds
        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_B));
    }

    // when the rate equals the capacity minus one
    //   [X] it sets both configs
    // The passing side of the strict boundary, in both directions at once
    function test_whenRateEqualsCapacityMinusOne()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        ICCIPRateLimiter.Config memory outbound = _rateLimiterConfig(
            true,
            DEFAULT_OUTBOUND_CAPACITY,
            DEFAULT_OUTBOUND_CAPACITY - 1
        );
        ICCIPRateLimiter.Config memory inbound = _rateLimiterConfig(
            true,
            DEFAULT_INBOUND_CAPACITY,
            DEFAULT_INBOUND_CAPACITY - 1
        );

        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);

        _assertConfigEq(_toConfig(_outboundBucket(CHAIN_SELECTOR_A)), outbound, "outbound config");
        _assertConfigEq(_toConfig(_inboundBucket(CHAIN_SELECTOR_A)), inbound, "inbound config");
    }

    // when both configs are the minimum enabled {true, 2, 1}
    //   [X] it sets both configs
    // Equal to the containment constant; the route then reads as contained
    function test_whenConfigIsMinimumEnabled()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, _containmentConfig(), _containmentConfig());

        // The buckets were full at 10_000 and 20_000; the capacity of two clamps both fills to
        // min(2, tokens) = 2
        _assertBucket(
            _outboundBucket(CHAIN_SELECTOR_A),
            true,
            2,
            1,
            2,
            "outbound at the minimum enabled config"
        );
        _assertBucket(
            _inboundBucket(CHAIN_SELECTOR_A),
            true,
            2,
            1,
            2,
            "inbound at the minimum enabled config"
        );
        assertTrue(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the route should read as contained afterwards"
        );
    }

    // when the capacity is the uint128 maximum
    //   [X] it sets both configs
    // Rate is type(uint128).max - 1; the fill stays at its previous level (never raised)
    function test_whenCapacityIsMax()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        ICCIPRateLimiter.Config memory maxConfig = _rateLimiterConfig(
            true,
            type(uint128).max,
            type(uint128).max - 1
        );

        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, maxConfig, maxConfig);

        // The fills stay at min(type(uint128).max, tokens) = tokens, the levels the route was
        // added with: 10_000 outbound and 20_000 inbound
        _assertBucket(
            _outboundBucket(CHAIN_SELECTOR_A),
            true,
            type(uint128).max,
            type(uint128).max - 1,
            DEFAULT_OUTBOUND_CAPACITY,
            "outbound at the uint128 maximum capacity"
        );
        _assertBucket(
            _inboundBucket(CHAIN_SELECTOR_A),
            true,
            type(uint128).max,
            type(uint128).max - 1,
            DEFAULT_INBOUND_CAPACITY,
            "inbound at the uint128 maximum capacity"
        );
    }

    // when the values equal the current configs
    //   [X] it writes and emits RouteRateLimitsSet with identical previous and new configs
    // Writing the values that are already set succeeds rather than reverting
    function test_whenValuesEqualCurrent()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.RouteRateLimitsSet(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig(),
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );
        vm.prank(admin);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );

        _assertBucket(
            _outboundBucket(CHAIN_SELECTOR_A),
            true,
            DEFAULT_OUTBOUND_CAPACITY,
            DEFAULT_OUTBOUND_RATE,
            DEFAULT_OUTBOUND_CAPACITY,
            "outbound after the identical write"
        );
    }

    // when the new capacity is below the current fill
    //   [X] the fill is clamped down to the new capacity
    // The pool sets tokens to min(newCapacity, tokens)
    function test_whenCapacityIsLoweredBelowFill()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        // The outbound bucket is full at its capacity of 10_000 base units
        assertEq(
            _outboundBucket(CHAIN_SELECTOR_A).tokens,
            DEFAULT_OUTBOUND_CAPACITY,
            "the outbound bucket should start full"
        );

        vm.prank(admin);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _rateLimiterConfig(true, 100, 10),
            _defaultInboundConfig()
        );

        // fill = min(newCapacity, previousTokens) = min(100, 10_000) = 100 base units
        _assertBucket(
            _outboundBucket(CHAIN_SELECTOR_A),
            true,
            100,
            10,
            100,
            "outbound after the capacity cut"
        );
    }

    // when the capacity is raised
    //   [X] the fill stays at its previous level
    // Raising a capacity never refills the bucket; throughput returns only over time
    function test_whenCapacityIsRaised()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        // Drain the outbound bucket to 5_000 base units in this block, leaving the inbound one
        // at its full 20_000
        _setBucketFills(CHAIN_SELECTOR_A, 5_000, DEFAULT_INBOUND_CAPACITY);
        assertEq(
            _outboundBucket(CHAIN_SELECTOR_A).tokens,
            5_000,
            "the outbound fill should be drained to 5_000"
        );

        vm.prank(admin);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _rateLimiterConfig(true, 50_000, 500),
            _defaultInboundConfig()
        );

        // fill = min(newCapacity, previousTokens) = min(50_000, 5_000) = 5_000 base units: the
        // raise leaves the fill untouched
        _assertBucket(
            _outboundBucket(CHAIN_SELECTOR_A),
            true,
            50_000,
            500,
            5_000,
            "outbound after the capacity raise"
        );
    }

    // given a bucket was drained
    //   [X] the event's previous fields carry the config values, not the fill
    // RouteRateLimitsSet reports isEnabled, capacity and rate of the projected bucket; the
    // drained tokens value must not leak into the previous configs.
    function test_givenBucketDrained()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        // Drain both buckets to 1_000 base units without touching their configurations
        _setBucketFills(CHAIN_SELECTOR_A, 1_000, 1_000);
        ICCIPRateLimiter.Config memory outbound = _rateLimiterConfig(true, 5_000, 50);
        ICCIPRateLimiter.Config memory inbound = _rateLimiterConfig(true, 6_000, 60);

        // The previous fields are the configurations {true, 10_000, 100} and
        // {true, 20_000, 200}, not the drained fill of 1_000
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.RouteRateLimitsSet(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig(),
            outbound,
            inbound
        );
        vm.prank(admin);
        config.setChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);

        // fill = min(newCapacity, previousTokens) = min(5_000, 1_000) = 1_000 base units
        _assertBucket(
            _outboundBucket(CHAIN_SELECTOR_A),
            true,
            5_000,
            50,
            1_000,
            "outbound after the write"
        );
    }

    // given the route is contained
    //   [X] it restores the approved configs
    //   [X] the fill resumes from two units and is not raised by the restore
    //   [X] isChainDisabled reports false afterwards
    // The documented recovery path after disableChain
    function test_givenRouteContained()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenRouteContained
    {
        // Containment clamped both fills to the capacity of two base units
        assertTrue(config.isChainDisabled(CHAIN_SELECTOR_A), "the route should be contained");

        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.RouteRateLimitsSet(
            CHAIN_SELECTOR_A,
            _containmentConfig(),
            _containmentConfig(),
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );
        vm.prank(admin);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );

        // fill = min(newCapacity, previousTokens) = min(10_000, 2) = 2 base units: the restore
        // returns the capacity and the rate, never the fill
        _assertBucket(
            _outboundBucket(CHAIN_SELECTOR_A),
            true,
            DEFAULT_OUTBOUND_CAPACITY,
            DEFAULT_OUTBOUND_RATE,
            2,
            "outbound after the restore"
        );
        _assertBucket(
            _inboundBucket(CHAIN_SELECTOR_A),
            true,
            DEFAULT_INBOUND_CAPACITY,
            DEFAULT_INBOUND_RATE,
            2,
            "inbound after the restore"
        );
        assertFalse(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the route should no longer read as contained"
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

        vm.prank(admin);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _rateLimiterConfig(true, 5_000, 50),
            _rateLimiterConfig(true, 6_000, 60)
        );

        _assertRouteEqualsSnapshot(CHAIN_SELECTOR_B, routeBBefore, "route B");
    }

    // ========== MIRROR-ONLY CASES ========== //

    // given the policy is disabled
    //   [X] validateSetChainRateLimits returns for a valid input
    function test_validateSetChainRateLimits_givenDisabled()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenDisabled
    {
        assertFalse(config.isEnabled(), "the policy should be disabled");

        config.validateSetChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );
    }

    // when the mirror caller is any address
    //   [X] validateSetChainRateLimits returns for a valid input
    function test_validateSetChainRateLimits_whenCallerIsAnyAddress(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted givenChainAdded {
        vm.prank(caller_);
        config.validateSetChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );
    }

    // given the pool is owned by an unrelated third party
    //   [X] validateSetChainRateLimits returns for a valid input
    // The mirror covers validation only; the action would revert with Unauthorized
    function test_validateSetChainRateLimits_givenPoolOwnedByThirdParty()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPoolOwnedByThirdParty
    {
        config.validateSetChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.Unauthorized.selector, address(config))
        );
        vm.prank(admin);
        config.setChainRateLimits(
            CHAIN_SELECTOR_A,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );
    }
}
