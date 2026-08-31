// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Contracts
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPBridgeConfigTest} from "./CCIPBridgeConfigTest.sol";

contract CCIPBridgeConfigTests_setConfigOperator is CCIPBridgeConfigTest {
    // given the policy is disabled
    //   [X] it reverts with NotEnabled
    // The lifecycle gate lives inside the authorization hook of the mix-in setter
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.setConfigOperator(operator);
    }

    // given the policy is disabled
    //   when the caller does not hold the admin role
    //     [X] it reverts with NotEnabled
    // Pins the masking order inside the hook: givenEnabled runs before onlyAdminRole
    function test_givenDisabled_whenCallerIsNotAdmin_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.setConfigOperator(operator);
    }

    // when the caller does not hold the admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // The mix-in's ConfigOperator_Unauthorized is dead through this policy: the hook reverts
    // with the role error instead of returning false. The fuzz excludes the admin account and
    // the zero address.
    function test_whenCallerIsNotAdmin_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(0));

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        config.setConfigOperator(operator);
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsBridgeAdmin_reverts() public givenEnabled {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeAdmin);
        config.setConfigOperator(operator);
    }

    // when the caller holds only the emergency role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(emergency);
        config.setConfigOperator(operator);
    }

    // given the config operator is set
    //   when the caller is the config operator
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Self-rotation is denied: the operator cannot rotate or revoke itself
    function test_whenCallerIsConfigOperator_reverts() public givenEnabled givenConfigOperatorSet {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(operator);
        config.setConfigOperator(makeAddr("selfPickedSuccessor"));
    }

    // when the parameters are valid
    //   [X] it sets configOperator to the new address
    //   [X] it emits ConfigOperatorSet with the new address
    // The grant is immediate: no acceptance step exists
    function test_whenParametersAreValid() public givenEnabled {
        vm.expectEmit(true, true, true, true, address(config));
        emit IConfigOperator.ConfigOperatorSet(operator);
        vm.prank(admin);
        config.setConfigOperator(operator);

        assertEq(config.configOperator(), operator, "the config operator should be set");
    }

    // when the operator is the zero address
    //   [X] it sets configOperator to zero
    //   [X] it emits ConfigOperatorSet with the zero address
    // Zero is a meaningful value here: it revokes delegated access rather than reverting
    function test_whenOperatorIsZeroAddress() public givenEnabled givenConfigOperatorSet {
        vm.expectEmit(true, true, true, true, address(config));
        emit IConfigOperator.ConfigOperatorSet(address(0));
        vm.prank(admin);
        config.setConfigOperator(address(0));

        assertEq(config.configOperator(), address(0), "the config operator should be revoked");
    }

    // when the operator equals the current value
    //   [X] it writes and emits ConfigOperatorSet
    // Writing the value that is already set succeeds rather than reverting
    function test_whenValueEqualsCurrentValue() public givenEnabled givenConfigOperatorSet {
        assertEq(config.configOperator(), operator, "the operator should already be set");

        vm.expectEmit(true, true, true, true, address(config));
        emit IConfigOperator.ConfigOperatorSet(operator);
        vm.prank(admin);
        config.setConfigOperator(operator);

        assertEq(config.configOperator(), operator, "the config operator should stay set");
    }

    // given an operator is set
    //   when a different operator is supplied
    //     [X] it sets configOperator to the new address
    //     [X] it emits ConfigOperatorSet with the new address
    // Rotation replaces the previous operator immediately
    function test_givenOperatorSet_whenOperatorIsReplaced()
        public
        givenEnabled
        givenConfigOperatorSet
    {
        address newOperator = makeAddr("newOperator");

        vm.expectEmit(true, true, true, true, address(config));
        emit IConfigOperator.ConfigOperatorSet(newOperator);
        vm.prank(admin);
        config.setConfigOperator(newOperator);

        assertEq(config.configOperator(), newOperator, "the new operator should be set");
    }

    // when the operator is the admin account itself
    //   [X] it sets configOperator to the admin
    // Address aliasing: no self-appointment check exists, and the two authority classes of the
    // route functions collapse into one account.
    function test_whenOperatorIsAdmin() public givenEnabled {
        vm.prank(admin);
        config.setConfigOperator(admin);

        assertEq(config.configOperator(), admin, "the admin should be set as the operator");
    }

    // given an operator is set
    //   [X] the operator passes the route function authorization immediately
    // The delegation grant takes effect in the same block. The probe calls a route entry point
    // and distinguishes NotAuthorised from the first validation error.
    function test_givenOperatorSet_operatorIsAuthorizedForRouteFunctions()
        public
        givenEnabled
        givenConfigOperatorSet
    {
        assertTrue(
            _isAuthorizedForRouteFunctions(operator),
            "the operator should pass the route authorization in the same block"
        );
    }

    // given the operator was revoked
    //   [X] the former operator fails the route function authorization
    // With configOperator at zero, _isConfigOperator rejects every caller, so revocation is
    // effective immediately.
    function test_givenOperatorRevoked_formerOperatorIsNotAuthorized()
        public
        givenEnabled
        givenConfigOperatorSet
    {
        vm.prank(admin);
        config.setConfigOperator(address(0));

        assertFalse(
            _isAuthorizedForRouteFunctions(operator),
            "the former operator should fail the route authorization after revocation"
        );
    }

    // given the operator was rotated
    //   [X] the former operator fails the route function authorization
    //   [X] the new operator passes the route function authorization
    // Rotation moves the delegation atomically; the former holder keeps nothing
    function test_givenOperatorRotated_formerOperatorIsNotAuthorized()
        public
        givenEnabled
        givenConfigOperatorSet
    {
        address newOperator = makeAddr("newOperator");
        vm.prank(admin);
        config.setConfigOperator(newOperator);

        assertFalse(
            _isAuthorizedForRouteFunctions(operator),
            "the former operator should fail the route authorization after rotation"
        );
        assertTrue(
            _isAuthorizedForRouteFunctions(newOperator),
            "the new operator should pass the route authorization after rotation"
        );
    }
}
