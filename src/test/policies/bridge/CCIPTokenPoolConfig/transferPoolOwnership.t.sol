// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";

// Contracts
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPTokenPoolConfigTest} from "./CCIPTokenPoolConfigTest.sol";

contract CCIPTokenPoolConfigTests_transferPoolOwnership is CCIPTokenPoolConfigTest {
    // given the policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.transferPoolOwnership(thirdParty);
    }

    // given the policy is disabled
    //   when the caller does not hold the admin role
    //     [X] it reverts with NotEnabled
    function test_givenDisabled_whenCallerIsNotAdmin_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.transferPoolOwnership(thirdParty);
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
        config.transferPoolOwnership(thirdParty);
    }

    // given the config operator is set
    //   when the caller is the config operator
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Role asymmetry: the route delegate cannot move the root authority
    function test_whenCallerIsConfigOperator_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenConfigOperatorSet
    {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(operator);
        config.transferPoolOwnership(thirdParty);
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsBridgeAdmin_reverts() public givenEnabled givenPoolOwnershipAccepted {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeAdmin);
        config.transferPoolOwnership(thirdParty);
    }

    // when the caller holds only the emergency role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled givenPoolOwnershipAccepted {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(emergency);
        config.transferPoolOwnership(thirdParty);
    }

    // when the caller does not hold the admin role
    //   when the new owner is the zero address
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Pins the masking order: the role check answers before the zero check
    function test_whenCallerIsNotAdmin_whenNewOwnerIsZero_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller);
        config.transferPoolOwnership(address(0));
    }

    // when the new owner is the zero address
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidAddress("newOwner")
    // Chainlink's Ownable2Step accepts a zero proposal; the config-only check closes the gap
    function test_whenNewOwnerIsZero_reverts() public givenEnabled givenPoolOwnershipAccepted {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidAddress.selector,
                "newOwner"
            )
        );
        vm.prank(admin);
        config.transferPoolOwnership(address(0));

        assertEq(pool.owner(), address(config), "the pool owner should be unchanged");
    }

    // given the pool is owned by an unrelated third party
    //   when the new owner is the zero address
    //     [X] it reverts with CCIPTokenPoolConfig_InvalidAddress("newOwner")
    // Pins the order: the config validates the argument before the pool checks its caller
    function test_givenPoolOwnedByThirdParty_whenNewOwnerIsZero_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidAddress.selector,
                "newOwner"
            )
        );
        vm.prank(admin);
        config.transferPoolOwnership(address(0));
    }

    // given the pool is owned by an unrelated third party
    //   [X] it reverts with OnlyCallableByOwner
    function test_givenPoolOwnedByThirdParty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        address candidate = makeAddr("ownershipCandidate");
        assertEq(pool.owner(), thirdParty, "the third party should own the pool");

        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.transferPoolOwnership(candidate);
    }

    // given the pool is owned by an unrelated third party
    //   when the new owner is the config itself
    //     [X] it reverts with OnlyCallableByOwner
    // Pins the order: the pool's owner check answers before the self-transfer check
    function test_givenPoolOwnedByThirdParty_whenNewOwnerIsConfig_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        address configAddress = address(config);

        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.transferPoolOwnership(configAddress);
    }

    // when the new owner is the config itself
    //   [X] it reverts with CannotTransferToSelf
    function test_whenNewOwnerIsConfig_reverts() public givenEnabled givenPoolOwnershipAccepted {
        address configAddress = address(config);

        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.CannotTransferToSelf.selector));
        vm.prank(admin);
        config.transferPoolOwnership(configAddress);

        assertEq(pool.owner(), configAddress, "the pool owner should be unchanged");
    }

    // when the caller holds the admin role
    //   [X] the pool owner is unchanged (ownership does not move on propose)
    //   [X] the pool emits OwnershipTransferRequested
    //   [X] it emits PoolOwnershipTransferRequested with the new owner
    //   [X] the proposed owner can accept and only then becomes the owner
    // The two-step promise: the pending state is observable only through who can accept
    function test_whenCallerIsAdmin() public givenEnabled givenPoolOwnershipAccepted {
        assertEq(pool.owner(), address(config), "the config should own the pool");

        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.OwnershipTransferRequested(address(config), thirdParty);
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolOwnershipTransferRequested(thirdParty);
        vm.prank(admin);
        config.transferPoolOwnership(thirdParty);

        assertEq(pool.owner(), address(config), "the proposal should not move the ownership");

        vm.prank(thirdParty);
        pool.acceptOwnership();

        assertEq(pool.owner(), thirdParty, "the acceptance should move the ownership");
    }

    // when the new owner is any address
    //   [X] it proposes that address
    // Fuzzed over the valid domain (not zero, not the config); EOAs are legal candidates:
    // no code check exists and a stranded proposal is overwritable.
    function test_whenNewOwnerIsAnyAddress(
        address newOwner_
    ) public givenEnabled givenPoolOwnershipAccepted {
        vm.assume(newOwner_ != address(0));
        vm.assume(newOwner_ != address(config));

        // The pool writes its pending owner and emits in the same statement, so the pool event
        // is the observable proof of the proposal: Ownable2Step exposes no pending getter
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.OwnershipTransferRequested(address(config), newOwner_);
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolOwnershipTransferRequested(newOwner_);
        vm.prank(admin);
        config.transferPoolOwnership(newOwner_);

        assertEq(pool.owner(), address(config), "the proposal should not move the ownership");
    }

    // given a pending transfer exists
    //   [X] the later proposal overwrites the earlier one
    //   [X] the earlier proposed owner can no longer accept
    //   [X] the later proposed owner can accept
    // The documented correction mechanism for a mistaken transfer
    function test_givenPendingTransferExists() public givenEnabled givenPoolOwnershipAccepted {
        address correctedOwner = makeAddr("correctedOwner");

        vm.prank(admin);
        config.transferPoolOwnership(thirdParty);

        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolOwnershipTransferRequested(correctedOwner);
        vm.prank(admin);
        config.transferPoolOwnership(correctedOwner);

        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.MustBeProposedOwner.selector));
        vm.prank(thirdParty);
        pool.acceptOwnership();

        assertEq(pool.owner(), address(config), "the config should still own the pool");

        vm.prank(correctedOwner);
        pool.acceptOwnership();

        assertEq(pool.owner(), correctedOwner, "the later proposal should govern");
    }

    // given the ownership was transferred and the recipient accepted
    //   [X] a route function reverts with OnlyCallableByOwner
    //   [X] setChainRateLimits reverts with Unauthorized
    // The documented consequence of a completed migration: the config keeps no pool
    // authority in either flavor of the pool's caller checks.
    function test_givenOwnershipTransferredAndAccepted()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.prank(admin);
        config.transferPoolOwnership(thirdParty);
        vm.prank(thirdParty);
        pool.acceptOwnership();
        assertEq(pool.owner(), thirdParty, "the third party should own the pool");

        // The route functions call the pool as its owner
        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_B));

        // The rate limiter setter accepts the owner or the rate limit admin, and names the
        // rejected caller: the config, which is now neither
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
