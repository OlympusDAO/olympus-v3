// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";

// Contracts
import {CCIPBridgeConfigTest} from "./CCIPBridgeConfigTest.sol";

contract CCIPBridgeConfigTests_removeRemotePool is CCIPBridgeConfigTest {
    // given the policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE);
    }

    // given the policy is disabled
    //   when the caller is not authorized
    //     [X] it reverts with NotEnabled
    function test_givenDisabled_whenCallerIsNotAuthorized_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE);
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
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE);
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
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE);
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
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE);
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
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE);
    }

    // when the caller is not authorized
    //   when the route does not exist
    //     [X] it reverts with NotAuthorised
    function test_whenCallerIsNotAuthorized_whenRouteMissing_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address caller = makeAddr("unauthorizedCaller");
        assertFalse(pool.isSupportedChain(CHAIN_SELECTOR_A), "the route should not exist");

        _expectRevertNotAuthorised();
        vm.prank(caller);
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE);
    }

    // when the route does not exist
    //   [X] it reverts with NonExistentChain carrying the selector
    //   [X] validateRemoveRemotePool reverts with the same error
    function test_whenRouteDoesNotExist_reverts() public givenEnabled givenPoolOwnershipAccepted {
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.NonExistentChain.selector,
            CHAIN_SELECTOR_A
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE);

        vm.expectRevert(err);
        config.validateRemoveRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE);
    }

    // when the route does not exist
    //   when the entry is not accepted anywhere
    //     [X] it reverts with NonExistentChain
    // Pins the order: the existence check runs before the membership check
    function test_whenRouteDoesNotExist_whenEntryNotAccepted_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        bytes memory strangerPool = abi.encode(makeAddr("strangerRemotePool"));

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_A)
        );
        vm.prank(admin);
        config.removeRemotePool(CHAIN_SELECTOR_A, strangerPool);
    }

    // when the remote pool is not accepted for the route
    //   [X] it reverts with InvalidRemotePoolForChain carrying the selector and the entry
    //   [X] validateRemoveRemotePool reverts with the same error
    function test_whenRemotePoolIsNotAccepted_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        bytes memory strangerPool = abi.encode(makeAddr("strangerRemotePool"));
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.InvalidRemotePoolForChain.selector,
            CHAIN_SELECTOR_A,
            strangerPool
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.removeRemotePool(CHAIN_SELECTOR_A, strangerPool);

        vm.expectRevert(err);
        config.validateRemoveRemotePool(CHAIN_SELECTOR_A, strangerPool);
    }

    // when the remote pool is empty
    //   [X] it reverts with InvalidRemotePoolForChain
    //   [X] validateRemoveRemotePool reverts with the same error
    // Empty bytes are not special-cased here: they are simply not a member. The sibling
    // addRemotePool raises ZeroAddressNotAllowed instead; the asymmetry is deliberate and
    // pinned.
    function test_whenRemotePoolIsEmpty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.InvalidRemotePoolForChain.selector,
            CHAIN_SELECTOR_A,
            ""
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.removeRemotePool(CHAIN_SELECTOR_A, "");

        vm.expectRevert(err);
        config.validateRemoveRemotePool(CHAIN_SELECTOR_A, "");

        // The sibling function answers the same argument with a dedicated error
        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.ZeroAddressNotAllowed.selector));
        config.validateAddRemotePool(CHAIN_SELECTOR_A, "");
    }

    // given the remote pool was already removed
    //   [X] it reverts with InvalidRemotePoolForChain
    //   [X] validateRemoveRemotePool reverts with the same error
    // The second producer of the non-member state: a double removal is not idempotent
    function test_givenRemotePoolAlreadyRemoved_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.prank(admin);
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);

        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.InvalidRemotePoolForChain.selector,
            CHAIN_SELECTOR_A,
            REMOTE_POOL_TWO
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);

        vm.expectRevert(err);
        config.validateRemoveRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);
    }

    // given the route has a single accepted pool
    //   [X] it reverts with CCIPBridgeConfig_LastRemotePool carrying the selector
    //   [X] validateRemoveRemotePool reverts with the same error
    // The config-only check: the pool itself would let the set be emptied, silently killing
    // the route's inbound traffic.
    function test_givenRouteHasSinglePool_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAddedWithSinglePool
    {
        assertEq(
            pool.getRemotePools(CHAIN_SELECTOR_A).length,
            1,
            "the route should have a single accepted pool"
        );
        bytes memory err = abi.encodeWithSelector(
            ICCIPBridgeConfig.CCIPBridgeConfig_LastRemotePool.selector,
            CHAIN_SELECTOR_A
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE);

        vm.expectRevert(err);
        config.validateRemoveRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE);

        assertTrue(
            pool.isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE),
            "the sole entry should still be accepted"
        );
    }

    // given the route has a single accepted pool
    //   when the entry is not the accepted one
    //     [X] it reverts with InvalidRemotePoolForChain
    // Pins the order: membership answers before the last-pool check
    function test_givenRouteHasSinglePool_whenEntryNotAccepted_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAddedWithSinglePool
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolAdmin.InvalidRemotePoolForChain.selector,
                CHAIN_SELECTOR_A,
                REMOTE_POOL_TWO
            )
        );
        vm.prank(admin);
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);
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
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);

        assertTrue(
            pool.isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO),
            "the entry should still be accepted"
        );
    }

    // when the caller is an admin
    //   [X] isRemotePool reports the entry as no longer accepted
    //   [X] getRemotePools returns only the surviving entry
    //   [X] the pool emits RemotePoolRemoved
    //   [X] it emits RouteRemotePoolRemoved
    //   [X] validateRemoveRemotePool for the removed entry reverts afterwards
    // The main happy path on the two-entry route: the boundary pass side (one entry remains)
    function test_whenCallerIsAdmin()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.RemotePoolRemoved(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPBridgeConfig.RouteRemotePoolRemoved(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);
        vm.prank(admin);
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);

        assertFalse(
            pool.isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO),
            "the removed entry should no longer be accepted"
        );
        assertTrue(
            pool.isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_ONE),
            "the surviving entry should still be accepted"
        );
        _assertRemotePoolsEq(
            pool.getRemotePools(CHAIN_SELECTOR_A),
            _singleRemotePool(),
            "remote pools after the removal"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolAdmin.InvalidRemotePoolForChain.selector,
                CHAIN_SELECTOR_A,
                REMOTE_POOL_TWO
            )
        );
        config.validateRemoveRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);
    }

    // when the caller is the config operator
    //   [X] it removes the remote pool
    function test_whenCallerIsConfigOperator()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenConfigOperatorSet
        givenChainAdded
    {
        vm.prank(operator);
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);

        assertFalse(
            pool.isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO),
            "the operator should be able to remove the entry"
        );
    }

    // given another route accepts the same bytes
    //   [X] it removes the entry from this route only
    //   [X] the sibling route still accepts the same bytes
    function test_givenAnotherRouteHasSameBytes()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenSecondChainAdded
    {
        // Route B accepts REMOTE_POOL_B alone, so the shared entry is added to it as a second
        // member: removing the shared bytes from route A must not touch route B
        vm.prank(admin);
        config.addRemotePool(CHAIN_SELECTOR_B, REMOTE_POOL_TWO);
        RouteSnapshot memory routeBBefore = _snapshotRoute(CHAIN_SELECTOR_B);

        vm.prank(admin);
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);

        assertFalse(
            pool.isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO),
            "route A should no longer accept the shared entry"
        );
        assertTrue(
            pool.isRemotePool(CHAIN_SELECTOR_B, REMOTE_POOL_TWO),
            "route B should still accept the shared entry"
        );
        _assertRouteEqualsSnapshot(CHAIN_SELECTOR_B, routeBBefore, "route B");
    }

    // given the policy is disabled
    //   [X] validateRemoveRemotePool returns for a valid input
    function test_validateRemoveRemotePool_givenDisabled()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenDisabled
    {
        assertFalse(config.isEnabled(), "the policy should be disabled");

        config.validateRemoveRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);
    }

    // when the mirror caller is any address
    //   [X] validateRemoveRemotePool returns for a valid input
    function test_validateRemoveRemotePool_whenCallerIsAnyAddress(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted givenChainAdded {
        vm.prank(caller_);
        config.validateRemoveRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);
    }

    // given the pool is owned by an unrelated third party
    //   [X] validateRemoveRemotePool returns for a valid input
    // The mirror covers validation only; the action would revert with OnlyCallableByOwner
    function test_validateRemoveRemotePool_givenPoolOwnedByThirdParty()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPoolOwnedByThirdParty
    {
        config.validateRemoveRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);

        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.removeRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);
    }
}
