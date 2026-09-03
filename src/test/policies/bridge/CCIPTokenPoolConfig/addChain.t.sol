// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";

import {CCIPTokenPoolConfigTest} from "./CCIPTokenPoolConfigTest.sol";

contract CCIPTokenPoolConfigTests_addChain is CCIPTokenPoolConfigTest {
    // ========== LIFECYCLE AND AUTHORIZATION ========== //

    // given the policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));
    }

    // given the policy is disabled
    //   when the caller is not authorized
    //     [X] it reverts with NotEnabled
    // Pins the masking order: the lifecycle gate answers before the authorization modifier
    function test_givenDisabled_whenCallerIsNotAuthorized_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));
    }

    // when the caller is neither the config operator nor an admin
    //   [X] it reverts with NotAuthorised
    // The fuzz excludes the admin, the operator and the zero address
    function test_whenCallerIsNotAuthorized_reverts(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted givenConfigOperatorSet {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != operator);
        vm.assume(caller_ != address(0));

        _expectRevertNotAuthorised();
        vm.prank(caller_);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with NotAuthorised
    // Role asymmetry: the containment-capable role holds no route authority
    function test_whenCallerIsBridgeAdmin_reverts() public givenEnabled givenPoolOwnershipAccepted {
        _expectRevertNotAuthorised();
        vm.prank(bridgeAdmin);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));
    }

    // when the caller holds only the bridge rate limiter role
    //   [X] it reverts with NotAuthorised
    // Role asymmetry: the rate limit role holds no route authority
    function test_whenCallerIsBridgeRateLimiter_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        _expectRevertNotAuthorised();
        vm.prank(bridgeRateLimiter);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));
    }

    // when the caller holds only the emergency role
    //   [X] it reverts with NotAuthorised
    function test_whenCallerIsEmergency_reverts() public givenEnabled givenPoolOwnershipAccepted {
        _expectRevertNotAuthorised();
        vm.prank(emergency);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));
    }

    // given the config operator is unset
    //   when the caller is the zero address
    //     [X] it reverts with NotAuthorised
    // _isConfigOperator rejects the zero address, so an unset operator does not authorize
    // address(0).
    function test_givenOperatorUnset_whenCallerIsZeroAddress_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        assertEq(config.configOperator(), address(0), "the operator should be unset");

        _expectRevertNotAuthorised();
        vm.prank(address(0));
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));
    }

    // when the caller is not authorized
    //   when the update is invalid
    //     [X] it reverts with NotAuthorised
    // Pins the masking order: authorization answers before any validation
    function test_whenCallerIsNotAuthorized_whenUpdateIsInvalid_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address caller = makeAddr("unauthorizedCaller");
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _disabledConfig();

        _expectRevertNotAuthorised();
        vm.prank(caller);
        config.addChain(update);
    }

    // ========== VALIDATION REVERTS (mirror parity folded into each) ========== //

    // when the outbound rate limiter config is disabled
    //   [X] it reverts with CCIPTokenPoolConfig_RateLimiterDisabled
    //   [X] validateAddChain reverts with the same error
    // The input is {false, 0, 0}, the exact shape the pool itself would accept as "no limit":
    // the config check is the only line of defense.
    function test_whenOutboundRateLimiterIsDisabled_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _disabledConfig();
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RateLimiterDisabled.selector
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addChain(update);

        vm.expectRevert(err);
        config.validateAddChain(update);
    }

    // when the inbound rate limiter config is disabled
    //   [X] it reverts with CCIPTokenPoolConfig_RateLimiterDisabled
    //   [X] validateAddChain reverts with the same error
    function test_whenInboundRateLimiterIsDisabled_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.inboundRateLimiterConfig = _disabledConfig();
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RateLimiterDisabled.selector
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addChain(update);

        vm.expectRevert(err);
        config.validateAddChain(update);
    }

    // when the outbound rate is zero
    //   [X] it reverts with InvalidRateLimitRate carrying the outbound config
    //   [X] validateAddChain reverts with the same error
    function test_whenOutboundRateIsZero_reverts() public givenEnabled givenPoolOwnershipAccepted {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _rateLimiterConfig(true, DEFAULT_OUTBOUND_CAPACITY, 0);
        bytes memory err = abi.encodeWithSelector(
            ICCIPRateLimiter.InvalidRateLimitRate.selector,
            update.outboundRateLimiterConfig
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addChain(update);

        vm.expectRevert(err);
        config.validateAddChain(update);
    }

    // when the outbound rate equals the outbound capacity
    //   [X] it reverts with InvalidRateLimitRate carrying the outbound config
    //   [X] validateAddChain reverts with the same error
    // The failing side of the strict rate < capacity boundary
    function test_whenOutboundRateEqualsCapacity_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _rateLimiterConfig(
            true,
            DEFAULT_OUTBOUND_CAPACITY,
            DEFAULT_OUTBOUND_CAPACITY
        );
        bytes memory err = abi.encodeWithSelector(
            ICCIPRateLimiter.InvalidRateLimitRate.selector,
            update.outboundRateLimiterConfig
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addChain(update);

        vm.expectRevert(err);
        config.validateAddChain(update);
    }

    // when the outbound config is enabled with zero capacity and zero rate
    //   [X] it reverts with InvalidRateLimitRate
    //   [X] validateAddChain reverts with the same error
    // {true, 0, 0} fails through the rate == 0 half of the compound predicate
    function test_whenOutboundRateLimiterIsEnabledWithZeroCapacity_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _rateLimiterConfig(true, 0, 0);
        bytes memory err = abi.encodeWithSelector(
            ICCIPRateLimiter.InvalidRateLimitRate.selector,
            update.outboundRateLimiterConfig
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addChain(update);

        vm.expectRevert(err);
        config.validateAddChain(update);
    }

    // when the inbound rate is zero
    //   [X] it reverts with InvalidRateLimitRate carrying the inbound config
    //   [X] validateAddChain reverts with the same error
    function test_whenInboundRateIsZero_reverts() public givenEnabled givenPoolOwnershipAccepted {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.inboundRateLimiterConfig = _rateLimiterConfig(true, DEFAULT_INBOUND_CAPACITY, 0);
        bytes memory err = abi.encodeWithSelector(
            ICCIPRateLimiter.InvalidRateLimitRate.selector,
            update.inboundRateLimiterConfig
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addChain(update);

        vm.expectRevert(err);
        config.validateAddChain(update);
    }

    // when the inbound rate equals the inbound capacity
    //   [X] it reverts with InvalidRateLimitRate carrying the inbound config
    //   [X] validateAddChain reverts with the same error
    function test_whenInboundRateEqualsCapacity_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.inboundRateLimiterConfig = _rateLimiterConfig(
            true,
            DEFAULT_INBOUND_CAPACITY,
            DEFAULT_INBOUND_CAPACITY
        );
        bytes memory err = abi.encodeWithSelector(
            ICCIPRateLimiter.InvalidRateLimitRate.selector,
            update.inboundRateLimiterConfig
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addChain(update);

        vm.expectRevert(err);
        config.validateAddChain(update);
    }

    // when both rate limiter configs are invalid
    //   [X] it reverts with InvalidRateLimitRate carrying the outbound config
    // Pins the validation order: the outbound config is checked before the inbound one
    function test_whenBothRateLimiterConfigsAreInvalid_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _rateLimiterConfig(true, DEFAULT_OUTBOUND_CAPACITY, 0);
        update.inboundRateLimiterConfig = _rateLimiterConfig(true, DEFAULT_INBOUND_CAPACITY, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPRateLimiter.InvalidRateLimitRate.selector,
                update.outboundRateLimiterConfig
            )
        );
        vm.prank(admin);
        config.addChain(update);
    }

    // when the outbound rate limiter is disabled
    //   when the remote token is empty
    //     [X] it reverts with CCIPTokenPoolConfig_RateLimiterDisabled
    // Pins the pool-order rule: the limiter checks run before the token check
    function test_whenOutboundRateLimiterIsDisabled_whenRemoteTokenIsEmpty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _disabledConfig();
        update.remoteTokenAddress = "";

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RateLimiterDisabled.selector
            )
        );
        vm.prank(admin);
        config.addChain(update);
    }

    // when the remote token is empty
    //   [X] it reverts with ZeroAddressNotAllowed
    //   [X] validateAddChain reverts with the same error
    function test_whenRemoteTokenIsEmpty_reverts() public givenEnabled givenPoolOwnershipAccepted {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.remoteTokenAddress = "";
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.ZeroAddressNotAllowed.selector
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addChain(update);

        vm.expectRevert(err);
        config.validateAddChain(update);
    }

    // given the route already exists
    //   [X] it reverts with ChainAlreadyExists carrying the selector
    //   [X] validateAddChain reverts with the same error
    function test_givenRouteExists_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.ChainAlreadyExists.selector,
            CHAIN_SELECTOR_A
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addChain(update);

        vm.expectRevert(err);
        config.validateAddChain(update);
    }

    // given the route already exists
    //   when the remote pool list is empty
    //     [X] it reverts with ChainAlreadyExists
    // Pins the pool-order rule: the existence check runs before the pool list checks
    function test_givenRouteExists_whenRemotePoolListIsEmpty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.remotePoolAddresses = new bytes[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolAdmin.ChainAlreadyExists.selector,
                CHAIN_SELECTOR_A
            )
        );
        vm.prank(admin);
        config.addChain(update);
    }

    // when the remote pool list is empty
    //   [X] it reverts with CCIPTokenPoolConfig_RemotePoolsEmpty
    //   [X] validateAddChain reverts with the same error
    // The pool accepts an empty list (a route that can never receive); config-only check
    function test_whenRemotePoolListIsEmpty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.remotePoolAddresses = new bytes[](0);
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RemotePoolsEmpty.selector
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addChain(update);

        vm.expectRevert(err);
        config.validateAddChain(update);
    }

    // when a remote pool entry is empty
    //   [X] it reverts with ZeroAddressNotAllowed
    //   [X] validateAddChain reverts with the same error
    // The empty entry sits at index 1 so the loop coverage goes past the first element
    function test_whenARemotePoolEntryIsEmpty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        bytes[] memory remotePools = new bytes[](2);
        remotePools[0] = REMOTE_POOL_ONE;
        remotePools[1] = "";
        update.remotePoolAddresses = remotePools;
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.ZeroAddressNotAllowed.selector
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addChain(update);

        vm.expectRevert(err);
        config.validateAddChain(update);
    }

    // when the remote pool entries contain a duplicate
    //   [X] it reverts with PoolAlreadyAdded carrying the selector and the duplicated entry
    //   [X] validateAddChain reverts with the same error
    // The duplicate is non-adjacent ([X, Y, X]) so the full inner scan is exercised
    function test_whenRemotePoolEntriesAreDuplicated_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        bytes[] memory remotePools = new bytes[](3);
        remotePools[0] = REMOTE_POOL_ONE;
        remotePools[1] = REMOTE_POOL_TWO;
        remotePools[2] = REMOTE_POOL_ONE;
        update.remotePoolAddresses = remotePools;
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.PoolAlreadyAdded.selector,
            CHAIN_SELECTOR_A,
            REMOTE_POOL_ONE
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addChain(update);

        vm.expectRevert(err);
        config.validateAddChain(update);
    }

    // ========== POOL-SIDE REVERTS ========== //

    // given the pool ownership was never accepted
    //   [X] it reverts with OnlyCallableByOwner
    // The pending-owner state: validation passes, the pool call fails
    function test_givenPoolOwnershipNotAccepted_reverts() public givenEnabled {
        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));
    }

    // given the pool is owned by an unrelated third party
    //   [X] it reverts with OnlyCallableByOwner
    // The post-migration state, reached through transferPoolOwnership plus acceptance
    function test_givenPoolOwnedByThirdParty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));
    }

    // ========== SUCCESSES ========== //

    // when the caller is an admin
    //   [X] the pool reports the route as supported
    //   [X] the pool returns the remote token and both remote pools
    //   [X] both buckets carry the supplied configs with tokens equal to capacity
    //   [X] the pool emits RemotePoolAdded per pool and ChainAdded
    //   [X] it emits RouteAdded with the selector and the update
    //   [X] validateAddChain returns for the same input before the call
    // The main happy path: two remote pools, distinct outbound and inbound configs, buckets
    // asserted to start full with lastUpdated at the current timestamp.
    function test_whenCallerIsAdmin() public givenEnabled givenPoolOwnershipAccepted {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        // The mirror returns for the same input before the call
        config.validateAddChain(update);

        uint256 timestamp = vm.getBlockTimestamp();

        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.RemotePoolAdded(CHAIN_SELECTOR_A, REMOTE_POOL_ONE);
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.RemotePoolAdded(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.ChainAdded(
            CHAIN_SELECTOR_A,
            REMOTE_TOKEN,
            update.outboundRateLimiterConfig,
            update.inboundRateLimiterConfig
        );
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.RouteAdded(CHAIN_SELECTOR_A, update);
        vm.prank(admin);
        config.addChain(update);

        assertTrue(
            pool.isSupportedChain(CHAIN_SELECTOR_A),
            "the pool should report the route as supported"
        );
        assertEq(
            pool.getRemoteToken(CHAIN_SELECTOR_A),
            REMOTE_TOKEN,
            "the pool should return the remote token"
        );
        _assertRemotePoolsEq(
            pool.getRemotePools(CHAIN_SELECTOR_A),
            _defaultRemotePools(),
            "remote pools"
        );

        // Both buckets start full: tokens = capacity (10_000 outbound, 20_000 inbound)
        ICCIPRateLimiter.TokenBucket memory outbound = _outboundBucket(CHAIN_SELECTOR_A);
        ICCIPRateLimiter.TokenBucket memory inbound = _inboundBucket(CHAIN_SELECTOR_A);
        _assertBucket(
            outbound,
            true,
            DEFAULT_OUTBOUND_CAPACITY,
            DEFAULT_OUTBOUND_RATE,
            DEFAULT_OUTBOUND_CAPACITY,
            "outbound"
        );
        _assertBucket(
            inbound,
            true,
            DEFAULT_INBOUND_CAPACITY,
            DEFAULT_INBOUND_RATE,
            DEFAULT_INBOUND_CAPACITY,
            "inbound"
        );
        assertEq(outbound.lastUpdated, timestamp, "outbound lastUpdated should be now");
        assertEq(inbound.lastUpdated, timestamp, "inbound lastUpdated should be now");
    }

    // when the caller is the config operator
    //   [X] it adds the route
    function test_whenCallerIsConfigOperator()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenConfigOperatorSet
    {
        vm.prank(operator);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));

        assertTrue(
            pool.isSupportedChain(CHAIN_SELECTOR_A),
            "the operator should be able to add the route"
        );
    }

    // when the remote pool list has a single entry
    //   [X] it adds the route with one accepted remote pool
    function test_whenRemotePoolListHasSingleEntry()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.remotePoolAddresses = _singleRemotePool();

        vm.prank(admin);
        config.addChain(update);

        _assertRemotePoolsEq(
            pool.getRemotePools(CHAIN_SELECTOR_A),
            _singleRemotePool(),
            "remote pools"
        );
    }

    // when the rate equals the capacity minus one
    //   [X] it adds the route
    // The passing side of the strict boundary, in both directions at once
    function test_whenRateEqualsCapacityMinusOne() public givenEnabled givenPoolOwnershipAccepted {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _rateLimiterConfig(
            true,
            DEFAULT_OUTBOUND_CAPACITY,
            DEFAULT_OUTBOUND_CAPACITY - 1
        );
        update.inboundRateLimiterConfig = _rateLimiterConfig(
            true,
            DEFAULT_INBOUND_CAPACITY,
            DEFAULT_INBOUND_CAPACITY - 1
        );

        vm.prank(admin);
        config.addChain(update);

        _assertConfigEq(
            _toConfig(_outboundBucket(CHAIN_SELECTOR_A)),
            update.outboundRateLimiterConfig,
            "outbound config"
        );
        _assertConfigEq(
            _toConfig(_inboundBucket(CHAIN_SELECTOR_A)),
            update.inboundRateLimiterConfig,
            "inbound config"
        );
    }

    // when both rate limiter configs are the minimum enabled {true, 2, 1}
    //   [X] it adds the route
    // The smallest admissible enabled config, identical to the containment constant; the new
    // route immediately reads as contained through isChainDisabled.
    function test_whenRateLimiterIsMinimumEnabled() public givenEnabled givenPoolOwnershipAccepted {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _containmentConfig();
        update.inboundRateLimiterConfig = _containmentConfig();

        vm.prank(admin);
        config.addChain(update);

        assertTrue(
            pool.isSupportedChain(CHAIN_SELECTOR_A),
            "the minimum enabled config should be accepted"
        );
        assertTrue(
            config.isChainDisabled(CHAIN_SELECTOR_A),
            "the {true, 2, 1} route should immediately read as contained"
        );
    }

    // when the capacity is the uint128 maximum
    //   [X] it adds the route with the buckets starting full at type(uint128).max
    // Rate is type(uint128).max - 1 to satisfy the strict boundary
    function test_whenCapacityIsMax() public givenEnabled givenPoolOwnershipAccepted {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _rateLimiterConfig(
            true,
            type(uint128).max,
            type(uint128).max - 1
        );
        update.inboundRateLimiterConfig = _rateLimiterConfig(
            true,
            type(uint128).max,
            type(uint128).max - 1
        );

        vm.prank(admin);
        config.addChain(update);

        assertEq(
            _outboundBucket(CHAIN_SELECTOR_A).tokens,
            type(uint128).max,
            "the outbound bucket should start full at the uint128 maximum"
        );
        assertEq(
            _inboundBucket(CHAIN_SELECTOR_A).tokens,
            type(uint128).max,
            "the inbound bucket should start full at the uint128 maximum"
        );
    }

    // when the remote addresses are not EVM-encoded
    //   [X] it adds the route
    // Family-encoded bytes of arbitrary length (a 32-byte SVM-style token and pool) are
    // accepted; no shape validation exists.
    function test_whenRemoteAddressesAreNotEvmEncoded()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        bytes memory svmToken = abi.encodePacked(keccak256("svm-token"));
        bytes[] memory remotePools = new bytes[](1);
        remotePools[0] = abi.encodePacked(keccak256("svm-pool"));

        vm.prank(admin);
        config.addChain(
            _chainUpdate(
                CHAIN_SELECTOR_A,
                remotePools,
                svmToken,
                _defaultOutboundConfig(),
                _defaultInboundConfig()
            )
        );

        assertEq(
            pool.getRemoteToken(CHAIN_SELECTOR_A),
            svmToken,
            "the 32-byte raw token should be stored verbatim"
        );
        _assertRemotePoolsEq(pool.getRemotePools(CHAIN_SELECTOR_A), remotePools, "remote pools");
    }

    // when the chain selector is any value
    //   [X] it adds the route for that selector
    // Fuzzed over the full uint64 domain, including zero and the maximum
    function test_whenChainSelectorIsAnyValue(
        uint64 chainSelector_
    ) public givenEnabled givenPoolOwnershipAccepted {
        vm.prank(admin);
        config.addChain(_defaultChainUpdate(chainSelector_));

        assertTrue(
            pool.isSupportedChain(chainSelector_),
            "the route should be added for any selector"
        );
    }

    // given another route exists
    //   [X] it adds the new route
    //   [X] the existing route keeps its remote token, pools and bucket state
    function test_givenAnotherRouteExists()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        RouteSnapshot memory routeABefore = _snapshotRoute(CHAIN_SELECTOR_A);

        vm.prank(admin);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_B));

        assertTrue(pool.isSupportedChain(CHAIN_SELECTOR_B), "the new route should be added");
        _assertRouteEqualsSnapshot(CHAIN_SELECTOR_A, routeABefore, "route A");
    }

    // ========== MIRROR-ONLY CASES ========== //

    // given the policy is disabled
    //   [X] validateAddChain returns for a valid input
    // The mirror carries no lifecycle gate; the pool is adopted while enabled, then the
    // policy is disabled again.
    function test_validateAddChain_givenDisabled()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenDisabled
    {
        assertFalse(config.isEnabled(), "the policy should be disabled");

        config.validateAddChain(_defaultChainUpdate(CHAIN_SELECTOR_A));
    }

    // when the mirror caller is any address
    //   [X] validateAddChain returns for a valid input
    // The mirror is a permissionless view; fuzzed caller
    function test_validateAddChain_whenCallerIsAnyAddress(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted {
        vm.prank(caller_);
        config.validateAddChain(_defaultChainUpdate(CHAIN_SELECTOR_A));
    }

    // given the pool is owned by an unrelated third party
    //   [X] validateAddChain returns for a valid input
    // The mirror covers validation only: the action would revert with OnlyCallableByOwner
    function test_validateAddChain_givenPoolOwnedByThirdParty()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        config.validateAddChain(update);

        // The same input fails on the action: the mirror does not repeat the authority check
        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.addChain(update);
    }
}
