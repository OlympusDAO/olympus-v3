// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";
import {ICCIPTokenPoolConfigTimelock} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Contracts
import {CCIPTokenPoolConfig} from "src/policies/bridge/CCIPTokenPoolConfig.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPTokenPoolConfigTest} from "./CCIPTokenPoolConfigTest.sol";

contract CCIPTokenPoolConfigTests_setConfigOperator is CCIPTokenPoolConfigTest {
    // ========== FILE-LOCAL HELPERS ========== //

    /// @dev The mix-in's error for a rotation to the operator already set
    function _expectRevertConfigOperatorUnchanged() internal {
        vm.expectRevert(abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unchanged.selector));
    }

    /// @dev The policy's error for a candidate that is not a timelock bound to this config
    function _expectRevertInvalidConfigOperator(address candidate_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidConfigOperator.selector,
                candidate_
            )
        );
    }

    /// @dev A timelock bound to a second config over the rig's pool: it advertises the
    ///      timelock interface but reports the other config
    function _timelockOfAnotherConfig() internal returns (address foreignTimelock) {
        CCIPTokenPoolConfig otherConfig = _newConfig(address(pool), GRACE_PERIOD);
        return address(_newTimelockFor(address(otherConfig)));
    }

    // ========== TESTS ========== //

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
    // Fuzzed over every address: the lifecycle error answers before any caller check
    function test_givenDisabled_whenCallerIsNotAdmin_reverts(address caller_) public {
        _expectRevertNotEnabled();
        vm.prank(caller_);
        config.setConfigOperator(operator);
    }

    // given the policy is disabled
    //   when the operator equals the current value
    //     [X] it reverts with NotEnabled
    // Pins the masking order: the hook's lifecycle gate answers before the mix-in's unchanged
    // check. The operator is set while enabled, then the policy is disabled.
    function test_givenDisabled_whenValueEqualsCurrentValue_reverts()
        public
        givenEnabled
        givenConfigOperatorSet
        givenDisabled
    {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.setConfigOperator(operator);
    }

    // given the policy is disabled
    //   when the operator holds no code
    //     [X] it reverts with NotEnabled
    // Pins the masking order: the lifecycle gate answers before the candidate check
    function test_givenDisabled_whenOperatorHoldsNoCode_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.setConfigOperator(thirdParty);
    }

    // when the caller does not hold the admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // The mix-in's ConfigOperator_Unauthorized is dead through this policy: the hook reverts
    // with the role error instead of returning false. The fuzz excludes the admin account.
    function test_whenCallerIsNotAdmin_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != admin);

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        config.setConfigOperator(operator);
    }

    // when the caller does not hold the admin role
    //   when the operator equals the current value
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Pins the masking order: the hook's role check answers before the mix-in's unchanged check
    // The fuzz excludes the admin account
    function test_whenCallerIsNotAdmin_whenValueEqualsCurrentValue_reverts(
        address caller_
    ) public givenEnabled givenConfigOperatorSet {
        vm.assume(caller_ != admin);

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        config.setConfigOperator(operator);
    }

    // when the caller does not hold the admin role
    //   when the operator holds no code
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Pins the masking order: the role gate answers before the candidate check. The fuzz
    // excludes the admin account.
    function test_whenCallerIsNotAdmin_whenOperatorHoldsNoCode_reverts(
        address caller_
    ) public givenEnabled {
        vm.assume(caller_ != admin);

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        config.setConfigOperator(thirdParty);
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

    // when the operator holds no code
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidConfigOperator carrying the candidate
    //   [X] the operator stays unset
    // Fuzzed over the codeless addresses other than zero: an account that cannot answer the
    // ERC165 probe is rejected, the mistyped-address case
    function test_whenOperatorHoldsNoCode_reverts(address candidate_) public givenEnabled {
        vm.assume(candidate_ != address(0));
        vm.assume(candidate_.code.length == 0);

        _expectRevertInvalidConfigOperator(candidate_);
        vm.prank(admin);
        config.setConfigOperator(candidate_);

        assertEq(config.configOperator(), address(0), "the config operator should stay unset");
    }

    // when the operator is a contract that does not answer ERC165
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidConfigOperator carrying the candidate
    // The token holds code but no supportsInterface; the ERC165 probe fails
    function test_whenOperatorDoesNotAnswerERC165_reverts() public givenEnabled {
        address candidate = address(ohm);

        _expectRevertInvalidConfigOperator(candidate);
        vm.prank(admin);
        config.setConfigOperator(candidate);
    }

    // when the operator is a contract that does not advertise the timelock interface
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidConfigOperator carrying the candidate
    // The pool answers ERC165 but not ICCIPTokenPoolConfigTimelock
    function test_whenOperatorDoesNotAdvertiseTimelockInterface_reverts() public givenEnabled {
        address candidate = address(pool);

        _expectRevertInvalidConfigOperator(candidate);
        vm.prank(admin);
        config.setConfigOperator(candidate);
    }

    // when the operator is a timelock bound to another config
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidConfigOperator carrying the candidate
    // The candidate advertises the interface and reports the other config; the binding check
    // mirrors the one the timelock constructor makes in the other direction
    function test_whenOperatorIsTimelockOfAnotherConfig_reverts() public givenEnabled {
        address candidate = _timelockOfAnotherConfig();

        _expectRevertInvalidConfigOperator(candidate);
        vm.prank(admin);
        config.setConfigOperator(candidate);

        assertEq(config.configOperator(), address(0), "the config operator should stay unset");
    }

    // given an operator is set
    //   when the operator is a timelock bound to another config
    //     [X] it reverts with CCIPTokenPoolConfig_InvalidConfigOperator carrying the candidate
    //     [X] the current operator stays set
    // The candidate check runs after the mix-in's write, and the revert undoes the write
    function test_givenOperatorSet_whenOperatorIsTimelockOfAnotherConfig_reverts()
        public
        givenEnabled
        givenConfigOperatorSet
    {
        address candidate = _timelockOfAnotherConfig();

        _expectRevertInvalidConfigOperator(candidate);
        vm.prank(admin);
        config.setConfigOperator(candidate);

        assertEq(config.configOperator(), operator, "the current operator should stay set");
    }

    // when the parameters are valid
    //   [X] it sets configOperator to the new address
    //   [X] it emits ConfigOperatorSet with the new address
    // The grant is immediate: no acceptance step exists. The candidate is the timelock bound
    // to this config, unactivated and disabled: its lifecycle plays no part in the acceptance.
    function test_whenParametersAreValid() public givenEnabled {
        assertFalse(operatorTimelock.isEnabled(), "the candidate timelock should be disabled");
        assertFalse(
            kernel.isPolicyActive(operatorTimelock),
            "the candidate timelock should be unactivated"
        );
        assertEq(
            operatorTimelock.config(),
            address(config),
            "the candidate timelock should be bound to this config"
        );

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
    //   [X] it reverts with ConfigOperator_Unchanged
    // Writing the value that is already set reverts in the mix-in, after the hook: a call that
    // lands always changes state
    function test_whenValueEqualsCurrentValue_reverts() public givenEnabled givenConfigOperatorSet {
        assertEq(config.configOperator(), operator, "the operator should already be set");

        _expectRevertConfigOperatorUnchanged();
        vm.prank(admin);
        config.setConfigOperator(operator);

        assertEq(config.configOperator(), operator, "the config operator should stay set");
    }

    // when the operator equals the current value
    //   given the current operator no longer reports this config
    //     [X] it reverts with ConfigOperator_Unchanged
    // Pins the check order: the mix-in's unchanged check answers before the candidate check.
    // A set operator always passes the candidate check, since config() is immutable, so the
    // answer of config() is mocked to another address to make the order observable.
    function test_whenValueEqualsCurrentValue_givenOperatorReportsAnotherConfig_reverts()
        public
        givenEnabled
        givenConfigOperatorSet
    {
        vm.mockCall(
            operator,
            abi.encodeWithSelector(ICCIPTokenPoolConfigTimelock.config.selector),
            abi.encode(makeAddr("anotherConfig"))
        );
        assertTrue(
            ICCIPTokenPoolConfigTimelock(operator).config() != address(config),
            "the mocked operator should report another config"
        );

        _expectRevertConfigOperatorUnchanged();
        vm.prank(admin);
        config.setConfigOperator(operator);

        vm.clearMockedCalls();
        assertEq(config.configOperator(), operator, "the config operator should stay set");
    }

    // when the operator is the zero address
    //   given no operator is set
    //     [X] it reverts with ConfigOperator_Unchanged
    // Zero is a value in its own right: revoking an operator that is already unset is an
    // unchanged write, not a no-op
    function test_whenOperatorIsZeroAddress_givenOperatorUnset_reverts() public givenEnabled {
        assertEq(config.configOperator(), address(0), "the operator should start unset");

        _expectRevertConfigOperatorUnchanged();
        vm.prank(admin);
        config.setConfigOperator(address(0));

        assertEq(config.configOperator(), address(0), "the config operator should stay unset");
    }

    // given an operator is set
    //   when a different operator is supplied
    //     [X] it sets configOperator to the new address
    //     [X] it emits ConfigOperatorSet with the new address
    // Rotation replaces the previous operator immediately; the successor is a second timelock
    // bound to this config
    function test_givenOperatorSet_whenOperatorIsReplaced()
        public
        givenEnabled
        givenConfigOperatorSet
    {
        address newOperator = address(_newTimelockFor(address(config)));

        vm.expectEmit(true, true, true, true, address(config));
        emit IConfigOperator.ConfigOperatorSet(newOperator);
        vm.prank(admin);
        config.setConfigOperator(newOperator);

        assertEq(config.configOperator(), newOperator, "the new operator should be set");
    }

    // when the operator is the admin account itself
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidConfigOperator carrying the admin
    // The admin account holds no code, so the two authority classes of the route functions
    // cannot collapse into one account through this setter
    function test_whenOperatorIsAdmin_reverts() public givenEnabled {
        _expectRevertInvalidConfigOperator(admin);
        vm.prank(admin);
        config.setConfigOperator(admin);

        assertEq(config.configOperator(), address(0), "the config operator should stay unset");
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
        address newOperator = address(_newTimelockFor(address(config)));
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
