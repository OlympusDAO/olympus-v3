// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Contracts
import {ConfigOperatorSingleStepTest} from "src/test/policies/utils/ConfigOperatorSingleStep/ConfigOperatorSingleStepTest.sol";
import {ConfigOperatorSingleStepDefaultDenyHarness} from "src/test/policies/utils/ConfigOperatorSingleStep/fixtures/ConfigOperatorSingleStepHarness.sol";

contract ConfigOperatorSingleStepSetConfigOperatorTest is ConfigOperatorSingleStepTest {
    // configOperator
    // given the contract has just been deployed
    //  when the config operator is read
    //   then it is unset
    function test_givenNewDeployment_operatorIsUnset() public view {
        assertEq(configOperator.configOperator(), address(0), "config operator");
        assertFalse(configOperator.isConfigOperator(address(0)), "zero address unauthorized");
    }

    // setConfigOperator
    // given the implementation does not override the authorization hook
    //  when any caller sets the config operator
    //   then it reverts and keeps delegated access disabled
    function test_givenDefaultAuthorization_reverts(address caller_, address operator_) public {
        ConfigOperatorSingleStepDefaultDenyHarness defaultDeny = new ConfigOperatorSingleStepDefaultDenyHarness();

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unauthorized.selector, caller_)
        );
        defaultDeny.setConfigOperator(operator_);

        assertEq(defaultDeny.configOperator(), address(0), "config operator");
    }

    // setConfigOperator
    // given the caller is not authorized by the implementation
    //  when the caller sets the config operator
    //   then it reverts and keeps delegated access disabled
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != authorizedCaller);

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unauthorized.selector, caller_)
        );
        configOperator.setConfigOperator(operator);

        assertEq(configOperator.configOperator(), address(0), "config operator");
    }

    // setConfigOperator
    // given the caller is authorized
    //  when the caller sets the config operator
    //   then it stores the operator and emits ConfigOperatorSet
    function test_givenAuthorizedCaller_setsOperator() public {
        vm.expectEmit(true, false, false, true, address(configOperator));
        emit IConfigOperator.ConfigOperatorSet(operator);

        vm.prank(authorizedCaller);
        configOperator.setConfigOperator(operator);

        assertEq(configOperator.configOperator(), operator, "config operator");
        assertTrue(configOperator.isConfigOperator(operator), "operator authorized");
        assertFalse(configOperator.isConfigOperator(other), "other unauthorized");
    }

    // setConfigOperator
    // given an operator is already configured
    //  when the authorized caller sets a different operator
    //   then it replaces the operator immediately without acceptance
    function test_givenExistingOperator_replacesOperator() public {
        vm.prank(authorizedCaller);
        configOperator.setConfigOperator(operator);

        vm.prank(authorizedCaller);
        configOperator.setConfigOperator(other);

        assertEq(configOperator.configOperator(), other, "config operator");
        assertFalse(configOperator.isConfigOperator(operator), "old operator unauthorized");
        assertTrue(configOperator.isConfigOperator(other), "new operator authorized");
    }

    // setConfigOperator
    // given an operator is configured
    //  when the authorized caller sets the zero address
    //   then it revokes delegated access
    function test_givenExistingOperator_givenZeroAddress_revokesOperator() public {
        vm.prank(authorizedCaller);
        configOperator.setConfigOperator(operator);

        vm.expectEmit(true, false, false, true, address(configOperator));
        emit IConfigOperator.ConfigOperatorSet(address(0));
        vm.prank(authorizedCaller);
        configOperator.setConfigOperator(address(0));

        assertEq(configOperator.configOperator(), address(0), "config operator");
        assertFalse(configOperator.isConfigOperator(operator), "old operator unauthorized");
    }

    // _requireConfigOperator
    // given the caller is the configured operator
    //  when the internal guard is used
    //   then it succeeds
    function test_givenCallerIsConfigOperator_guardSucceeds() public {
        vm.prank(authorizedCaller);
        configOperator.setConfigOperator(operator);

        vm.prank(operator);
        configOperator.requireConfigOperator();
    }

    // _requireConfigOperator
    // given the caller is not the configured operator
    //  when the internal guard is used
    //   then it reverts with the rejected caller
    function test_givenCallerIsNotConfigOperator_guardReverts(address caller_) public {
        vm.assume(caller_ != operator);

        vm.prank(authorizedCaller);
        configOperator.setConfigOperator(operator);

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unauthorized.selector, caller_)
        );
        configOperator.requireConfigOperator();
    }
}
