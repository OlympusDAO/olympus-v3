// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";

// Contracts
import {CCIPBridgeConfigTest} from "./CCIPBridgeConfigTest.sol";

contract CCIPBridgeConfigTests_addRemotePool is CCIPBridgeConfigTest {
    // given the policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.addRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);
    }

    // given the policy is disabled
    //   when the caller is not authorized
    //     [X] it reverts with NotEnabled
    function test_givenDisabled_whenCallerIsNotAuthorized_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.addRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);
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
        config.addRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);
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
        config.addRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);
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
        config.addRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);
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
        config.addRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);
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
        config.addRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);
    }

    // when the route does not exist
    //   [X] it reverts with NonExistentChain carrying the selector
    //   [X] validateAddRemotePool reverts with the same error
    function test_whenRouteDoesNotExist_reverts() public givenEnabled givenPoolOwnershipAccepted {
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.NonExistentChain.selector,
            CHAIN_SELECTOR_A
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);

        vm.expectRevert(err);
        config.validateAddRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);
    }

    // when the route does not exist
    //   when the remote pool is empty
    //     [X] it reverts with NonExistentChain
    // Pins the order: the existence check runs before the empty-entry check
    function test_whenRouteDoesNotExist_whenRemotePoolIsEmpty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_A)
        );
        vm.prank(admin);
        config.addRemotePool(CHAIN_SELECTOR_A, "");
    }

    // when the remote pool is empty
    //   [X] it reverts with ZeroAddressNotAllowed
    //   [X] validateAddRemotePool reverts with the same error
    function test_whenRemotePoolIsEmpty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.ZeroAddressNotAllowed.selector
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addRemotePool(CHAIN_SELECTOR_A, "");

        vm.expectRevert(err);
        config.validateAddRemotePool(CHAIN_SELECTOR_A, "");
    }

    // when the remote pool is already accepted for the route
    //   [X] it reverts with PoolAlreadyAdded carrying the selector and the entry
    //   [X] validateAddRemotePool reverts with the same error
    function test_whenRemotePoolAlreadyAccepted_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.PoolAlreadyAdded.selector,
            CHAIN_SELECTOR_A,
            REMOTE_POOL_ONE
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.addRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE);

        vm.expectRevert(err);
        config.validateAddRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE);
    }

    // given the pool is owned by an unrelated third party
    //   [X] it reverts with OnlyCallableByOwner
    function test_givenPoolOwnedByThirdParty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPoolOwnedByThirdParty
    {
        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.addRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);

        assertFalse(
            pool.isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B),
            "the entry should not be accepted"
        );
    }

    // when the caller is an admin
    //   [X] isRemotePool reports the new entry as accepted
    //   [X] getRemotePools returns the previous entries and the new one
    //   [X] the pool emits RemotePoolAdded
    //   [X] it emits RouteRemotePoolAdded
    //   [X] validateAddRemotePool returns for the same input before the call
    // The main happy path; the previously accepted pools must remain accepted
    function test_whenCallerIsAdmin()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        bytes memory newRemotePool = abi.encode(makeAddr("remotePoolThree"));
        config.validateAddRemotePool(CHAIN_SELECTOR_A, newRemotePool);

        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.RemotePoolAdded(CHAIN_SELECTOR_A, newRemotePool);
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPBridgeConfig.RouteRemotePoolAdded(CHAIN_SELECTOR_A, newRemotePool);
        vm.prank(admin);
        config.addRemotePool(CHAIN_SELECTOR_A, newRemotePool);

        assertTrue(
            pool.isRemotePool(CHAIN_SELECTOR_A, newRemotePool),
            "the new entry should be accepted"
        );
        assertTrue(
            pool.isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE),
            "the first entry should still be accepted"
        );
        assertTrue(
            pool.isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO),
            "the second entry should still be accepted"
        );

        bytes[] memory expectedPools = new bytes[](3);
        expectedPools[0] = REMOTE_POOL_ONE;
        expectedPools[1] = REMOTE_POOL_TWO;
        expectedPools[2] = newRemotePool;
        _assertRemotePoolsEq(
            pool.getRemotePools(CHAIN_SELECTOR_A),
            expectedPools,
            "remote pools after the add"
        );
    }

    // when the caller is the config operator
    //   [X] it adds the remote pool
    function test_whenCallerIsConfigOperator()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenConfigOperatorSet
        givenChainAdded
    {
        vm.prank(operator);
        config.addRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);

        assertTrue(
            pool.isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B),
            "the operator should be able to add the entry"
        );
    }

    // when the remote pool is not EVM-encoded
    //   [X] it adds the entry
    // A 32-byte SVM-style value; no shape validation exists
    function test_whenRemotePoolIsNotEvmEncoded()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        // 32 raw bytes, the shape a non-EVM family uses for an account address
        bytes memory familyEncodedPool = abi.encodePacked(keccak256("svmRemotePool"));
        assertEq(familyEncodedPool.length, 32, "the family-encoded value should be 32 bytes");

        vm.prank(admin);
        config.addRemotePool(CHAIN_SELECTOR_A, familyEncodedPool);

        assertTrue(
            pool.isRemotePool(CHAIN_SELECTOR_A, familyEncodedPool),
            "the family-encoded entry should be accepted"
        );
    }

    // when the remote pool is a single byte
    //   [X] it adds the entry
    // The smallest non-empty value: the pass side adjacent to the emptiness check. Only
    // emptiness is validated, so the one-byte entry is stored verbatim like any other shape.
    function test_whenRemotePoolIsOneByte()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        bytes memory oneByteEntry = hex"01";
        assertEq(oneByteEntry.length, 1, "the entry should be one byte long");
        config.validateAddRemotePool(CHAIN_SELECTOR_A, oneByteEntry);

        vm.prank(admin);
        config.addRemotePool(CHAIN_SELECTOR_A, oneByteEntry);

        assertTrue(
            pool.isRemotePool(CHAIN_SELECTOR_A, oneByteEntry),
            "the one-byte entry should be accepted"
        );
    }

    // given the remote pool was removed earlier
    //   [X] it adds the entry again
    // The remove-then-re-add round trip on the same bytes
    function test_givenRemotePoolRemovedEarlier()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.prank(admin);
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);
        assertFalse(
            pool.isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO),
            "the entry should be removed"
        );

        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPBridgeConfig.RouteRemotePoolAdded(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);
        vm.prank(admin);
        config.addRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);

        assertTrue(
            pool.isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO),
            "the entry should be accepted again"
        );
    }

    // given another route accepts the same bytes
    //   [X] it adds the entry for this route
    //   [X] the sibling route's set is unchanged
    // The accepted sets are per route; identical bytes may serve two routes
    function test_givenAnotherRouteHasSameBytes()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenSecondChainAdded
    {
        assertTrue(
            pool.isRemotePool(CHAIN_SELECTOR_B, REMOTE_POOL_B),
            "route B should accept the shared entry"
        );
        RouteSnapshot memory routeBBefore = _snapshotRoute(CHAIN_SELECTOR_B);

        vm.prank(admin);
        config.addRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);

        assertTrue(
            pool.isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B),
            "route A should accept the shared entry too"
        );
        _assertRouteEqualsSnapshot(CHAIN_SELECTOR_B, routeBBefore, "route B");
    }

    // given the policy is disabled
    //   [X] validateAddRemotePool returns for a valid input
    function test_validateAddRemotePool_givenDisabled()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenDisabled
    {
        assertFalse(config.isEnabled(), "the policy should be disabled");

        config.validateAddRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);
    }

    // when the mirror caller is any address
    //   [X] validateAddRemotePool returns for a valid input
    function test_validateAddRemotePool_whenCallerIsAnyAddress(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted givenChainAdded {
        vm.prank(caller_);
        config.validateAddRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);
    }

    // given the pool is owned by an unrelated third party
    //   [X] validateAddRemotePool returns for a valid input
    // The mirror covers validation only; the action would revert with OnlyCallableByOwner
    function test_validateAddRemotePool_givenPoolOwnedByThirdParty()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPoolOwnedByThirdParty
    {
        config.validateAddRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);

        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.addRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_B);
    }
}
