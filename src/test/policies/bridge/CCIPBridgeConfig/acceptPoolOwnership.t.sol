// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";

// Contracts
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPBridgeConfigTest} from "./CCIPBridgeConfigTest.sol";

contract CCIPBridgeConfigTests_acceptPoolOwnership is CCIPBridgeConfigTest {
    // given the policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.acceptPoolOwnership();

        assertEq(pool.owner(), address(this), "the pool owner should be unchanged");
    }

    // given the policy is disabled
    //   when the caller does not hold the admin role
    //     [X] it reverts with NotEnabled
    // Pins the masking order: the lifecycle gate answers before the role check
    function test_givenDisabled_whenCallerIsNotAdmin_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.acceptPoolOwnership();
    }

    // when the caller does not hold the admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // The fuzz excludes the admin account and the zero address
    function test_whenCallerIsNotAdmin_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(0));

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        config.acceptPoolOwnership();
    }

    // given the config operator is set
    //   when the caller is the config operator
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Role asymmetry: the route delegate cannot complete the root-authority handover
    function test_whenCallerIsConfigOperator_reverts() public givenEnabled givenConfigOperatorSet {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(operator);
        config.acceptPoolOwnership();
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsBridgeAdmin_reverts() public givenEnabled {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeAdmin);
        config.acceptPoolOwnership();
    }

    // when the caller holds only the emergency role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(emergency);
        config.acceptPoolOwnership();
    }

    // when the caller does not hold the admin role
    //   given no pending transfer exists
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Pins the masking order: the role check answers before the pool error
    function test_whenCallerIsNotAdmin_givenNoPendingTransfer_reverts()
        public
        givenPendingOwnershipCleared
        givenEnabled
    {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller);
        config.acceptPoolOwnership();
    }

    // given no pending transfer exists
    //   [X] it reverts with MustBeProposedOwner
    // The pool owner cleared the pending slot by proposing the zero address
    function test_givenNoPendingTransfer_reverts()
        public
        givenPendingOwnershipCleared
        givenEnabled
    {
        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.MustBeProposedOwner.selector));
        vm.prank(admin);
        config.acceptPoolOwnership();

        assertEq(pool.owner(), address(this), "the pool owner should be unchanged");
    }

    // given the pending owner is an unrelated third party
    //   [X] it reverts with MustBeProposedOwner
    function test_givenPendingOwnerIsThirdParty_reverts()
        public
        givenPendingOwnershipToThirdParty
        givenEnabled
    {
        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.MustBeProposedOwner.selector));
        vm.prank(admin);
        config.acceptPoolOwnership();

        assertEq(pool.owner(), address(this), "the pool owner should be unchanged");
    }

    // given the config already owns the pool
    //   [X] it reverts with MustBeProposedOwner
    // Acceptance clears the pending slot, so a double accept fails; the NatSpec names this
    // case explicitly.
    function test_givenAlreadyOwned_reverts() public givenEnabled givenPoolOwnershipAccepted {
        assertEq(pool.owner(), address(config), "the config should own the pool");

        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.MustBeProposedOwner.selector));
        vm.prank(admin);
        config.acceptPoolOwnership();

        assertEq(pool.owner(), address(config), "the config should still own the pool");
    }

    // when the caller holds the admin role
    //   [X] the pool owner becomes the config
    //   [X] the pool emits OwnershipTransferred
    //   [X] it emits PoolOwnershipAccepted with the pool address
    //   [X] a pool-calling function succeeds afterwards
    // The main handover; the unlock assertion uses a route call that failed before acceptance
    function test_whenCallerIsAdmin() public givenEnabled {
        assertEq(pool.owner(), address(this), "the test contract should own the pool");

        // Before the handover the pool rejects the config as a caller, so the route function
        // fails past its own validation
        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));

        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.OwnershipTransferred(address(this), address(config));
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPBridgeConfig.PoolOwnershipAccepted(address(pool));
        vm.prank(admin);
        config.acceptPoolOwnership();

        assertEq(pool.owner(), address(config), "the pool owner should be the config");

        // The same route call now reaches the pool as its owner
        vm.prank(admin);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));

        assertTrue(
            pool.isSupportedChain(CHAIN_SELECTOR_A),
            "the route should be configured after the handover"
        );
    }

    // given the ownership was migrated away and proposed back
    //   [X] it accepts the ownership again
    // The full round trip: transferPoolOwnership away, the recipient accepts, then proposes
    // the config, and the config accepts again.
    function test_givenOwnershipReProposedAfterMigration()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        vm.prank(admin);
        config.transferPoolOwnership(thirdParty);
        vm.prank(thirdParty);
        pool.acceptOwnership();
        assertEq(pool.owner(), thirdParty, "the third party should own the pool");

        vm.prank(thirdParty);
        pool.transferOwnership(address(config));

        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPBridgeConfig.PoolOwnershipAccepted(address(pool));
        vm.prank(admin);
        config.acceptPoolOwnership();

        assertEq(pool.owner(), address(config), "the config should own the pool again");
    }

    // given the pending slot was overwritten in favor of the config
    //   [X] it accepts the ownership
    // The owner proposed a third party first and the config second; the latest proposal
    // governs.
    function test_givenPendingOverwrittenToConfig()
        public
        givenPendingOwnershipToThirdParty
        givenEnabled
    {
        // The test contract still owns the pool and proposes the config after the third party
        pool.transferOwnership(address(config));

        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPBridgeConfig.PoolOwnershipAccepted(address(pool));
        vm.prank(admin);
        config.acceptPoolOwnership();

        assertEq(pool.owner(), address(config), "the pool owner should be the config");

        // The overwritten proposal is dead: the third party cannot accept afterwards
        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.MustBeProposedOwner.selector));
        vm.prank(thirdParty);
        pool.acceptOwnership();
    }
}
