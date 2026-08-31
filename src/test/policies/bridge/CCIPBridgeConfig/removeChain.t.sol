// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";

// Contracts
import {Vm} from "@forge-std-1.16.2/Vm.sol";

import {CCIPBridgeConfigTest} from "./CCIPBridgeConfigTest.sol";

contract CCIPBridgeConfigTests_removeChain is CCIPBridgeConfigTest {
    // given the policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.removeChain(CHAIN_SELECTOR_A);
    }

    // given the policy is disabled
    //   when the caller is not authorized
    //     [X] it reverts with NotEnabled
    function test_givenDisabled_whenCallerIsNotAuthorized_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.removeChain(CHAIN_SELECTOR_A);
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
        config.removeChain(CHAIN_SELECTOR_A);
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with NotAuthorised
    // Role asymmetry: an emergency actor contains a route, it cannot remove it
    function test_whenCallerIsBridgeAdmin_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        _expectRevertNotAuthorised();
        vm.prank(bridgeAdmin);
        config.removeChain(CHAIN_SELECTOR_A);
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
        config.removeChain(CHAIN_SELECTOR_A);
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
        config.removeChain(CHAIN_SELECTOR_A);
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
        config.removeChain(CHAIN_SELECTOR_A);
    }

    // when the route does not exist
    //   [X] it reverts with NonExistentChain carrying the selector
    //   [X] validateRemoveChain reverts with the same error
    function test_whenRouteDoesNotExist_reverts() public givenEnabled givenPoolOwnershipAccepted {
        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.NonExistentChain.selector,
            CHAIN_SELECTOR_A
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.removeChain(CHAIN_SELECTOR_A);

        vm.expectRevert(err);
        config.validateRemoveChain(CHAIN_SELECTOR_A);
    }

    // given the route was already removed
    //   [X] it reverts with NonExistentChain
    //   [X] validateRemoveChain reverts with the same error
    // The second producer state of the missing route: a double removal is not idempotent
    function test_givenRouteRemoved_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.prank(admin);
        config.removeChain(CHAIN_SELECTOR_A);

        bytes memory err = abi.encodeWithSelector(
            ICCIPTokenPoolAdmin.NonExistentChain.selector,
            CHAIN_SELECTOR_A
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.removeChain(CHAIN_SELECTOR_A);

        vm.expectRevert(err);
        config.validateRemoveChain(CHAIN_SELECTOR_A);
    }

    // given the pool is owned by an unrelated third party
    //   when the route does not exist
    //     [X] it reverts with NonExistentChain
    // Pins the masking order: the config validates the route before the pool checks its
    // caller, the inverse of the containment functions.
    function test_givenPoolOwnedByThirdParty_whenRouteDoesNotExist_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_A)
        );
        vm.prank(admin);
        config.removeChain(CHAIN_SELECTOR_A);
    }

    // given the pool is owned by an unrelated third party
    //   [X] it reverts with OnlyCallableByOwner
    // The route was added before the ownership migration
    function test_givenPoolOwnedByThirdParty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPoolOwnedByThirdParty
    {
        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.removeChain(CHAIN_SELECTOR_A);

        assertTrue(pool.isSupportedChain(CHAIN_SELECTOR_A), "the route should still exist");
    }

    // when the caller is an admin
    //   [X] the pool reports the route as unsupported
    //   [X] the pool returns an empty remote token and an empty remote pool list
    //   [X] the pool emits ChainRemoved
    //   [X] it emits RouteRemoved with the selector
    //   [X] no RemotePoolRemoved event is emitted for the dropped remote pools
    //   [X] validateRemoveChain reverts with NonExistentChain afterwards
    // The absence claims (no RemotePoolRemoved; every getter empty) need vm.recordLogs. The
    // post-state mirror flip is the parity assertion.
    function test_whenCallerIsAdmin()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        assertEq(
            pool.getRemotePools(CHAIN_SELECTOR_A).length,
            2,
            "the route should start with two remote pools"
        );

        vm.recordLogs();
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.ChainRemoved(CHAIN_SELECTOR_A);
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPBridgeConfig.RouteRemoved(CHAIN_SELECTOR_A);
        vm.prank(admin);
        config.removeChain(CHAIN_SELECTOR_A);

        assertFalse(pool.isSupportedChain(CHAIN_SELECTOR_A), "the route should be unsupported");
        assertEq(pool.getRemoteToken(CHAIN_SELECTOR_A), "", "the remote token should be empty");
        assertEq(
            pool.getRemotePools(CHAIN_SELECTOR_A).length,
            0,
            "the remote pool list should be empty"
        );
        _assertBucket(
            _outboundBucket(CHAIN_SELECTOR_A),
            false,
            0,
            0,
            0,
            "outbound after the removal"
        );
        _assertBucket(
            _inboundBucket(CHAIN_SELECTOR_A),
            false,
            0,
            0,
            0,
            "inbound after the removal"
        );

        // The pool drops the remote pool set silently: only ChainRemoved is emitted for it
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(
            _countLogs(logs, address(pool), ICCIPTokenPoolAdmin.RemotePoolRemoved.selector),
            0,
            "the pool should emit no RemotePoolRemoved on a route removal"
        );
        assertEq(
            _countLogs(logs, address(pool), ICCIPTokenPoolAdmin.ChainRemoved.selector),
            1,
            "the pool should emit ChainRemoved exactly once"
        );

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_A)
        );
        config.validateRemoveChain(CHAIN_SELECTOR_A);
    }

    // when the caller is the config operator
    //   [X] it removes the route
    function test_whenCallerIsConfigOperator()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenConfigOperatorSet
        givenChainAdded
    {
        vm.prank(operator);
        config.removeChain(CHAIN_SELECTOR_A);

        assertFalse(
            pool.isSupportedChain(CHAIN_SELECTOR_A),
            "the operator should be able to remove the route"
        );
    }

    // given another route exists
    //   [X] it removes only the targeted route
    //   [X] the sibling route keeps its remote token, pools and buckets
    function test_givenAnotherRouteExists()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenSecondChainAdded
    {
        RouteSnapshot memory routeBBefore = _snapshotRoute(CHAIN_SELECTOR_B);

        vm.prank(admin);
        config.removeChain(CHAIN_SELECTOR_A);

        assertFalse(pool.isSupportedChain(CHAIN_SELECTOR_A), "route A should be removed");
        assertTrue(pool.isSupportedChain(CHAIN_SELECTOR_B), "route B should still exist");
        _assertRouteEqualsSnapshot(CHAIN_SELECTOR_B, routeBBefore, "route B");
    }

    // given the route is contained
    //   [X] it removes the route entirely
    // A contained route is removable; deletion is the exit from containment by removal
    function test_givenRouteContained()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenRouteContained
    {
        assertTrue(config.isChainDisabled(CHAIN_SELECTOR_A), "the route should be contained");

        vm.prank(admin);
        config.removeChain(CHAIN_SELECTOR_A);

        assertFalse(pool.isSupportedChain(CHAIN_SELECTOR_A), "the route should be removed");
        assertEq(
            pool.getRemotePools(CHAIN_SELECTOR_A).length,
            0,
            "the remote pool list should be empty"
        );
    }

    // given the route was re-added after a removal
    //   [X] it removes the route again
    // The full add-remove-add-remove cycle; the second removal behaves like the first
    function test_givenRouteReAddedAfterRemoval()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.prank(admin);
        config.removeChain(CHAIN_SELECTOR_A);

        vm.prank(admin);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));
        assertTrue(pool.isSupportedChain(CHAIN_SELECTOR_A), "the route should be re-added");

        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPBridgeConfig.RouteRemoved(CHAIN_SELECTOR_A);
        vm.prank(admin);
        config.removeChain(CHAIN_SELECTOR_A);

        assertFalse(pool.isSupportedChain(CHAIN_SELECTOR_A), "the route should be removed again");
    }

    // given the policy is disabled
    //   [X] validateRemoveChain returns for an existing route
    // The mirror carries no lifecycle gate; the route is added while enabled first
    function test_validateRemoveChain_givenDisabled()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenDisabled
    {
        assertFalse(config.isEnabled(), "the policy should be disabled");

        config.validateRemoveChain(CHAIN_SELECTOR_A);
    }

    // when the mirror caller is any address
    //   [X] validateRemoveChain returns for an existing route
    function test_validateRemoveChain_whenCallerIsAnyAddress(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted givenChainAdded {
        vm.prank(caller_);
        config.validateRemoveChain(CHAIN_SELECTOR_A);
    }

    // given the pool is owned by an unrelated third party
    //   [X] validateRemoveChain returns for an existing route
    // The mirror covers validation only; the action would revert with OnlyCallableByOwner
    function test_validateRemoveChain_givenPoolOwnedByThirdParty()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPoolOwnedByThirdParty
    {
        config.validateRemoveChain(CHAIN_SELECTOR_A);

        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.removeChain(CHAIN_SELECTOR_A);
    }
}
