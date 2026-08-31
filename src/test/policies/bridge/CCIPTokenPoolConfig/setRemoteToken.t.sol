// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";

// Contracts
import {Vm} from "@forge-std-1.16.2/Vm.sol";

import {CCIPTokenPoolConfigTest} from "./CCIPTokenPoolConfigTest.sol";

contract CCIPTokenPoolConfigTests_setRemoteToken is CCIPTokenPoolConfigTest {
    /// @notice The replacement token used by most cases; EVM-shaped, distinct from the
    ///         defaults. Set lazily because makeAddr is unavailable at declaration time.
    bytes internal newRemoteToken;

    function setUp() public override {
        super.setUp();
        newRemoteToken = abi.encode(makeAddr("newRemoteToken"));
    }

    // ========== LIFECYCLE AND AUTHORIZATION ========== //

    // given the policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
    }

    // given the policy is disabled
    //   when the caller is not authorized
    //     [X] it reverts with NotEnabled
    function test_givenDisabled_whenCallerIsNotAuthorized_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
    }

    // when the caller is neither the config operator nor an admin
    //   [X] it reverts with NotAuthorised
    // The fuzz excludes the admin, the operator and the zero address
    function test_whenCallerIsNotAuthorized_reverts(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted givenConfigOperatorSet givenChainAdded {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != operator);
        vm.assume(caller_ != address(0));

        _expectRevertNotAuthorised();
        vm.prank(caller_);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with NotAuthorised
    function test_whenCallerIsBridgeAdmin_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        _expectRevertNotAuthorised();
        vm.prank(bridgeAdmin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
    }

    // when the caller holds only the bridge rate limiter role
    //   [X] it reverts with NotAuthorised
    function test_whenCallerIsBridgeRateLimiter_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        _expectRevertNotAuthorised();
        vm.prank(bridgeRateLimiter);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
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
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
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
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
    }

    // ========== VALIDATION REVERTS (mirror parity folded into each) ========== //

    // when the route does not exist
    //   [X] it reverts with NonExistentChain carrying the selector
    //   [X] validateSetRemoteToken reverts with the same error
    // The existence check reads isSupportedChain: getRemoteToken would return empty for an
    // unknown selector instead of reverting.
    function test_whenRouteDoesNotExist_reverts() public givenEnabled givenPoolOwnershipAccepted {
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.NonExistentChain.selector,
            CHAIN_SELECTOR_A
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        vm.expectRevert(err);
        config.validateSetRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
    }

    // when the route does not exist
    //   when the remote token is empty
    //     [X] it reverts with NonExistentChain
    // Pins the order: the existence check runs before the empty-token check
    function test_whenRouteDoesNotExist_whenRemoteTokenIsEmpty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_A)
        );
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, "");
    }

    // when the remote token is empty
    //   [X] it reverts with CCIPTokenPoolConfig_RemoteTokenEmpty
    //   [X] validateSetRemoteToken reverts with the same error
    function test_whenRemoteTokenIsEmpty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RemoteTokenEmpty.selector
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, "");

        vm.expectRevert(err);
        config.validateSetRemoteToken(CHAIN_SELECTOR_A, "");
    }

    // when the remote token equals the current one
    //   [X] it reverts with CCIPTokenPoolConfig_RemoteTokenUnchanged
    //   [X] validateSetRemoteToken reverts with the same error
    // The comparison is byte-exact through keccak256
    function test_whenRemoteTokenIsUnchanged_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RemoteTokenUnchanged.selector
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, REMOTE_TOKEN);

        vm.expectRevert(err);
        config.validateSetRemoteToken(CHAIN_SELECTOR_A, REMOTE_TOKEN);
    }

    // when the remote token equals the current one
    //   given the outbound bucket is disabled
    //     [X] it reverts with CCIPTokenPoolConfig_RemoteTokenUnchanged
    // Pins the order: the unchanged check runs before the bucket check. Needs the
    // pre-handover seed with the outbound bucket disabled.
    function test_whenRemoteTokenIsUnchanged_givenBucketDisabled_reverts()
        public
        givenRouteWithDisabledOutboundBucket
        givenEnabled
        givenPoolOwnershipAccepted
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RemoteTokenUnchanged.selector
            )
        );
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, REMOTE_TOKEN);
    }

    // given the outbound bucket is disabled
    //   [X] it reverts with CCIPTokenPoolConfig_RateLimiterDisabled
    //   [X] validateSetRemoteToken reverts with the same error
    // Only reachable for a route seeded directly on the pool before the handover: the
    // config's own paths reject disabled configs.
    function test_givenOutboundBucketDisabled_reverts()
        public
        givenRouteWithDisabledOutboundBucket
        givenEnabled
        givenPoolOwnershipAccepted
    {
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RateLimiterDisabled.selector
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        vm.expectRevert(err);
        config.validateSetRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
    }

    // given the inbound bucket is disabled
    //   [X] it reverts with CCIPTokenPoolConfig_RateLimiterDisabled
    //   [X] validateSetRemoteToken reverts with the same error
    // The pre-handover seed with only the inbound direction disabled
    function test_givenInboundBucketDisabled_reverts()
        public
        givenRouteWithDisabledInboundBucket
        givenEnabled
        givenPoolOwnershipAccepted
    {
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RateLimiterDisabled.selector
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        vm.expectRevert(err);
        config.validateSetRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
    }

    // ========== POOL-SIDE REVERTS ========== //

    // given the pool is owned by an unrelated third party
    //   [X] it reverts with OnlyCallableByOwner
    // Validation passes on views; the applyChainUpdates call fails
    function test_givenPoolOwnedByThirdParty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPoolOwnedByThirdParty
    {
        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
    }

    // given the config is only the pool rate limit admin
    //   [X] it reverts with OnlyCallableByOwner
    // The rate limiter split does not unlock route replacement: applyChainUpdates is
    // owner-only even though the two setChainRateLimiterConfig calls would pass.
    function test_givenConfigIsRateLimitAdminOnly_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPoolOwnedByThirdParty
        givenConfigIsRateLimitAdmin
    {
        assertEq(
            pool.getRateLimitAdmin(),
            address(config),
            "the config should be the rate limit admin"
        );

        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
    }

    // ========== SUCCESSES ========== //

    // when the caller is an admin
    //   [X] the pool returns the new remote token
    //   [X] both remote pools remain accepted
    //   [X] both bucket configs are unchanged (isEnabled, capacity, rate)
    //   [X] both fills remain full
    //   [X] it emits RemoteTokenSet with the previous and the new token
    //   [X] validateSetRemoteToken returns for the same input before the call
    // The main happy path over full buckets and two remote pools
    function test_whenCallerIsAdmin()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        // The mirror returns for the same input before the call
        config.validateSetRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.RemoteTokenSet(CHAIN_SELECTOR_A, REMOTE_TOKEN, newRemoteToken);
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        assertEq(
            pool.getRemoteToken(CHAIN_SELECTOR_A),
            newRemoteToken,
            "the pool should return the new remote token"
        );
        _assertRemotePoolsEq(
            pool.getRemotePools(CHAIN_SELECTOR_A),
            _defaultRemotePools(),
            "remote pools"
        );

        // Full fills are preserved: the previous fill equals the capacity, the temporary
        // clamp capacity equals the fill, and the restore keeps min(capacity, fill)
        _assertBucket(
            _outboundBucket(CHAIN_SELECTOR_A),
            true,
            DEFAULT_OUTBOUND_CAPACITY,
            DEFAULT_OUTBOUND_RATE,
            DEFAULT_OUTBOUND_CAPACITY,
            "outbound"
        );
        _assertBucket(
            _inboundBucket(CHAIN_SELECTOR_A),
            true,
            DEFAULT_INBOUND_CAPACITY,
            DEFAULT_INBOUND_RATE,
            DEFAULT_INBOUND_CAPACITY,
            "inbound"
        );
    }

    // when the caller is the config operator
    //   [X] it replaces the remote token
    function test_whenCallerIsConfigOperator()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenConfigOperatorSet
        givenChainAdded
    {
        vm.prank(operator);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        assertEq(
            pool.getRemoteToken(CHAIN_SELECTOR_A),
            newRemoteToken,
            "the operator should be able to replace the remote token"
        );
    }

    // given the buckets are partially drained
    //   [X] the outbound fill is restored exactly
    //   [X] the inbound fill is restored exactly at its own, different level
    // Fill levels at and above two units are preserved to the unit; the asymmetric levels
    // prove per-direction restoration. Needs the fill-manipulation helper.
    function test_givenBucketsPartiallyDrained()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        // Outbound drain: clamp {true, 5_000, 1} sets tokens = min(5_000, 10_000) = 5_000,
        // the restore {true, 10_000, 100} keeps min(10_000, 5_000) = 5_000 base units.
        // Inbound drain likewise to 7_000 base units. Same block, so no refill.
        _setBucketFills(CHAIN_SELECTOR_A, 5_000, 7_000);

        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        // Replacement refills both buckets to capacity; the temporary clamp then writes
        // capacity = max(previous, 2): outbound max(5_000, 2) = 5_000, inbound
        // max(7_000, 2) = 7_000; the restore keeps min(capacity, clamped fill), so the
        // outbound fill is 5_000 and the inbound fill 7_000, each at its own level
        assertEq(
            _outboundBucket(CHAIN_SELECTOR_A).tokens,
            5_000,
            "the outbound fill should be restored exactly"
        );
        assertEq(
            _inboundBucket(CHAIN_SELECTOR_A).tokens,
            7_000,
            "the inbound fill should be restored exactly at its own level"
        );
    }

    // given a bucket fill is zero
    //   [X] the fill is restored as two units
    // The floor: a level below the smallest enabled capacity cannot be expressed
    function test_givenBucketFillIsZero()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        // Outbound drain to zero: clamp to 2 units, then a real transfer consumes 2
        _setBucketFills(CHAIN_SELECTOR_A, 0, DEFAULT_INBOUND_CAPACITY);

        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        // The temporary clamp capacity is max(0, 2) = 2, the smallest enabled capacity at
        // rate 1, so the zero fill is restored as two base units
        assertEq(
            _outboundBucket(CHAIN_SELECTOR_A).tokens,
            2,
            "the zero fill should be restored as two units"
        );
    }

    // given a bucket fill is one
    //   [X] the fill is restored as two units
    function test_givenBucketFillIsOne()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        // Outbound drain to one: clamp to 2 units, then a real transfer consumes 1
        _setBucketFills(CHAIN_SELECTOR_A, 1, DEFAULT_INBOUND_CAPACITY);

        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        // The temporary clamp capacity is max(1, 2) = 2, so the fill of one is raised to two
        assertEq(
            _outboundBucket(CHAIN_SELECTOR_A).tokens,
            2,
            "the fill of one should be restored as two units"
        );
    }

    // given a bucket fill is exactly two
    //   [X] the fill is restored as exactly two units
    // The boundary sits at the floor itself: max(2, 2) = 2, preserved rather than raised
    function test_givenBucketFillIsTwo()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        _setBucketFills(CHAIN_SELECTOR_A, 2, DEFAULT_INBOUND_CAPACITY);

        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        // max(2, 2) = 2: the boundary fill is preserved exactly, not raised
        assertEq(
            _outboundBucket(CHAIN_SELECTOR_A).tokens,
            2,
            "the fill of two should be preserved exactly"
        );
    }

    // given time passed since the buckets were drained
    //   [X] the restored fill equals the projected level including the refill
    // The buckets are read projected to the current block, not at their stored values; a
    // skip between the drain and the call adds rate * dt to the preserved level.
    function test_givenTimePassedSinceDrain()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        _setBucketFills(CHAIN_SELECTOR_A, 5_000, DEFAULT_INBOUND_CAPACITY);
        skip(10);

        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        // The outbound bucket is read projected to now: 5_000 + 10 s * 100 units/s = 6_000
        // base units, and that projected level is what the clamp preserves
        assertEq(
            _outboundBucket(CHAIN_SELECTOR_A).tokens,
            6_000,
            "the restored fill should include the elapsed refill"
        );
    }

    // given the route is contained
    //   [X] it replaces the remote token
    //   [X] both buckets keep the containment config
    //   [X] isChainDisabled remains true
    // The containment config is enabled, so it passes the bucket check; containment survives
    // a token change.
    function test_givenRouteContained()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenRouteContained
    {
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        assertEq(
            pool.getRemoteToken(CHAIN_SELECTOR_A),
            newRemoteToken,
            "the remote token should be replaced"
        );
        // The contained bucket is {true, 2, 1} with fill 2 (full at its capacity), so the
        // replacement refill, the clamp to max(2, 2) = 2 and the restore all keep 2
        _assertBucket(_outboundBucket(CHAIN_SELECTOR_A), true, 2, 1, 2, "outbound");
        _assertBucket(_inboundBucket(CHAIN_SELECTOR_A), true, 2, 1, 2, "inbound");
        assertTrue(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the route should stay contained after the token change"
        );
    }

    // given the route has no remote pools
    //   [X] it replaces the remote token and carries the empty set forward
    // Only reachable for a route seeded before the handover; pins the recorded decision not
    // to reject an empty set here.
    function test_givenRouteHasNoRemotePools()
        public
        givenRouteWithNoRemotePools
        givenEnabled
        givenPoolOwnershipAccepted
    {
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        assertEq(
            pool.getRemoteToken(CHAIN_SELECTOR_A),
            newRemoteToken,
            "the remote token should be replaced"
        );
        assertEq(
            pool.getRemotePools(CHAIN_SELECTOR_A).length,
            0,
            "the empty remote pool set should be carried forward"
        );
    }

    // when the remote token differs in a single byte
    //   [X] it replaces the remote token
    // The passing side of the byte-exact unchanged check
    function test_whenRemoteTokenDiffersInOneByte()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        bytes memory alteredToken = REMOTE_TOKEN;
        alteredToken[31] = bytes1(uint8(alteredToken[31]) ^ 0x01);

        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, alteredToken);

        assertEq(
            pool.getRemoteToken(CHAIN_SELECTOR_A),
            alteredToken,
            "the one-byte difference should pass the unchanged check"
        );
    }

    // when the remote token has a different length
    //   [X] it replaces the remote token
    // A 64-byte family-encoded value over the 32-byte ABI-encoded EVM current token; no
    // shape validation exists
    function test_whenRemoteTokenHasDifferentLength()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        bytes memory longToken = abi.encodePacked(
            keccak256("family-token-one"),
            keccak256("family-token-two")
        );
        assertEq(longToken.length, 64, "the replacement token should be 64 bytes long");
        assertEq(REMOTE_TOKEN.length, 32, "the current token should be 32 bytes long");

        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, longToken);

        assertEq(
            pool.getRemoteToken(CHAIN_SELECTOR_A),
            longToken,
            "the different-length token should be stored verbatim"
        );
    }

    // [X] the pool emits ChainRemoved without any RemotePoolRemoved
    // [X] then RemotePoolAdded per pool followed by ChainAdded
    // [X] then two ConfigChanged and one ChainConfigured carrying the temporary configs
    // [X] then two ConfigChanged and one ChainConfigured carrying the original configs
    // [X] then the config emits RemoteTokenSet
    // The documented event sequence, asserted in order over recorded logs; the temporary
    // ChainConfigured carries {true, max(previousTokens, 2), 1} per direction.
    function test_eventSequenceMatchesDocumentation()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        // Full buckets: the temporary configs are {true, 10_000, 1} and {true, 20_000, 1}
        ICCIPRateLimiter.Config memory temporaryOutbound = _rateLimiterConfig(
            true,
            DEFAULT_OUTBOUND_CAPACITY,
            1
        );
        ICCIPRateLimiter.Config memory temporaryInbound = _rateLimiterConfig(
            true,
            DEFAULT_INBOUND_CAPACITY,
            1
        );

        vm.recordLogs();
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 11, "the call should emit exactly eleven events");
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(
                logs[i].topics[0] != ICCIPTokenPoolAdmin.RemotePoolRemoved.selector,
                "no RemotePoolRemoved should be emitted for the dropped set"
            );
        }

        // 1. ChainRemoved(selector) on the pool
        _assertLogHeader(
            logs[0],
            address(pool),
            ICCIPTokenPoolAdmin.ChainRemoved.selector,
            "log 0"
        );
        assertEq(abi.decode(logs[0].data, (uint64)), CHAIN_SELECTOR_A, "log 0: selector");

        // 2-3. RemotePoolAdded per accepted pool, in the enumerable set order
        _assertLogHeader(
            logs[1],
            address(pool),
            ICCIPTokenPoolAdmin.RemotePoolAdded.selector,
            "log 1"
        );
        assertEq(logs[1].topics[1], bytes32(uint256(CHAIN_SELECTOR_A)), "log 1: selector topic");
        assertEq(abi.decode(logs[1].data, (bytes)), REMOTE_POOL_ONE, "log 1: remote pool");
        _assertLogHeader(
            logs[2],
            address(pool),
            ICCIPTokenPoolAdmin.RemotePoolAdded.selector,
            "log 2"
        );
        assertEq(abi.decode(logs[2].data, (bytes)), REMOTE_POOL_TWO, "log 2: remote pool");

        // 4. ChainAdded with the new token and the original configs
        _assertLogHeader(logs[3], address(pool), ICCIPTokenPoolAdmin.ChainAdded.selector, "log 3");
        {
            (
                uint64 selector,
                bytes memory remoteToken,
                ICCIPRateLimiter.Config memory outbound,
                ICCIPRateLimiter.Config memory inbound
            ) = abi.decode(
                    logs[3].data,
                    (uint64, bytes, ICCIPRateLimiter.Config, ICCIPRateLimiter.Config)
                );
            assertEq(selector, CHAIN_SELECTOR_A, "log 3: selector");
            assertEq(remoteToken, newRemoteToken, "log 3: remote token");
            _assertConfigEq(outbound, _defaultOutboundConfig(), "log 3: outbound");
            _assertConfigEq(inbound, _defaultInboundConfig(), "log 3: inbound");
        }

        // 5-7. The first setChainRateLimiterConfig call: two ConfigChanged carrying the
        // temporary configs, then ChainConfigured with both
        _assertLogHeader(logs[4], address(pool), ICCIPRateLimiter.ConfigChanged.selector, "log 4");
        _assertConfigEq(
            abi.decode(logs[4].data, (ICCIPRateLimiter.Config)),
            temporaryOutbound,
            "log 4: temporary outbound"
        );
        _assertLogHeader(logs[5], address(pool), ICCIPRateLimiter.ConfigChanged.selector, "log 5");
        _assertConfigEq(
            abi.decode(logs[5].data, (ICCIPRateLimiter.Config)),
            temporaryInbound,
            "log 5: temporary inbound"
        );
        _assertLogHeader(
            logs[6],
            address(pool),
            ICCIPTokenPoolAdmin.ChainConfigured.selector,
            "log 6"
        );
        {
            (
                uint64 selector,
                ICCIPRateLimiter.Config memory outbound,
                ICCIPRateLimiter.Config memory inbound
            ) = abi.decode(
                    logs[6].data,
                    (uint64, ICCIPRateLimiter.Config, ICCIPRateLimiter.Config)
                );
            assertEq(selector, CHAIN_SELECTOR_A, "log 6: selector");
            _assertConfigEq(outbound, temporaryOutbound, "log 6: temporary outbound");
            _assertConfigEq(inbound, temporaryInbound, "log 6: temporary inbound");
        }

        // 8-10. The second setChainRateLimiterConfig call: the original configs
        _assertLogHeader(logs[7], address(pool), ICCIPRateLimiter.ConfigChanged.selector, "log 7");
        _assertConfigEq(
            abi.decode(logs[7].data, (ICCIPRateLimiter.Config)),
            _defaultOutboundConfig(),
            "log 7: original outbound"
        );
        _assertLogHeader(logs[8], address(pool), ICCIPRateLimiter.ConfigChanged.selector, "log 8");
        _assertConfigEq(
            abi.decode(logs[8].data, (ICCIPRateLimiter.Config)),
            _defaultInboundConfig(),
            "log 8: original inbound"
        );
        _assertLogHeader(
            logs[9],
            address(pool),
            ICCIPTokenPoolAdmin.ChainConfigured.selector,
            "log 9"
        );
        {
            (
                uint64 selector,
                ICCIPRateLimiter.Config memory outbound,
                ICCIPRateLimiter.Config memory inbound
            ) = abi.decode(
                    logs[9].data,
                    (uint64, ICCIPRateLimiter.Config, ICCIPRateLimiter.Config)
                );
            assertEq(selector, CHAIN_SELECTOR_A, "log 9: selector");
            _assertConfigEq(outbound, _defaultOutboundConfig(), "log 9: original outbound");
            _assertConfigEq(inbound, _defaultInboundConfig(), "log 9: original inbound");
        }

        // 11. RemoteTokenSet on the config closes the sequence
        _assertLogHeader(
            logs[10],
            address(config),
            ICCIPTokenPoolConfig.RemoteTokenSet.selector,
            "log 10"
        );
        assertEq(logs[10].topics[1], bytes32(uint256(CHAIN_SELECTOR_A)), "log 10: selector topic");
        (bytes memory previousToken, bytes memory currentToken) = abi.decode(
            logs[10].data,
            (bytes, bytes)
        );
        assertEq(previousToken, REMOTE_TOKEN, "log 10: previous token");
        assertEq(currentToken, newRemoteToken, "log 10: new token");
    }

    // given another route exists
    //   [X] the sibling route keeps its token, pools, configs and fills
    function test_givenAnotherRouteExists()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenSecondChainAdded
    {
        RouteSnapshot memory routeBBefore = _snapshotRoute(CHAIN_SELECTOR_B);

        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        _assertRouteEqualsSnapshot(CHAIN_SELECTOR_B, routeBBefore, "route B");
    }

    // ========== MIRROR-ONLY CASES ========== //

    // given the policy is disabled
    //   [X] validateSetRemoteToken returns for a valid input
    function test_validateSetRemoteToken_givenDisabled()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenDisabled
    {
        config.validateSetRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
    }

    // when the mirror caller is any address
    //   [X] validateSetRemoteToken returns for a valid input
    function test_validateSetRemoteToken_whenCallerIsAnyAddress(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted givenChainAdded {
        vm.prank(caller_);
        config.validateSetRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
    }

    // given the pool is owned by an unrelated third party
    //   [X] validateSetRemoteToken returns for a valid input
    // The mirror covers validation only; the action would revert with OnlyCallableByOwner
    function test_validateSetRemoteToken_givenPoolOwnedByThirdParty()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPoolOwnedByThirdParty
    {
        config.validateSetRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);

        // The same input fails on the action: the mirror does not repeat the authority check
        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.setRemoteToken(CHAIN_SELECTOR_A, newRemoteToken);
    }

    // ========== LOCAL LOG HELPERS ========== //

    /// @notice Asserts the emitter and the topic zero of one recorded log.
    function _assertLogHeader(
        Vm.Log memory log_,
        address emitter_,
        bytes32 topicZero_,
        string memory label_
    ) internal pure {
        assertEq(log_.emitter, emitter_, string.concat(label_, ": emitter"));
        assertEq(log_.topics[0], topicZero_, string.concat(label_, ": topic zero"));
    }
}
