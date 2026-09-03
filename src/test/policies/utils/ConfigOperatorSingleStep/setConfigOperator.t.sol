// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

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
        assertEq(_configOperator.configOperator(), address(0), "config operator");
        assertFalse(_configOperator.isConfigOperator(address(0)), "zero address unauthorized");
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
        vm.assume(caller_ != _authorizedCaller);

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unauthorized.selector, caller_)
        );
        _configOperator.setConfigOperator(_operator);

        assertEq(_configOperator.configOperator(), address(0), "config operator");
    }

    // setConfigOperator
    // given the caller is authorized
    //  when the caller sets the config operator
    //   then it stores the operator and emits ConfigOperatorSet
    function test_givenAuthorizedCaller_setsOperator() public {
        vm.expectEmit(true, false, false, true, address(_configOperator));
        emit IConfigOperator.ConfigOperatorSet(_operator);

        vm.prank(_authorizedCaller);
        _configOperator.setConfigOperator(_operator);

        assertEq(_configOperator.configOperator(), _operator, "config operator");
        assertTrue(_configOperator.isConfigOperator(_operator), "operator authorized");
        assertFalse(_configOperator.isConfigOperator(_other), "other unauthorized");
    }

    // setConfigOperator
    // given an operator is already configured
    //  when the authorized caller sets a different operator
    //   then it replaces the operator immediately without acceptance
    function test_givenExistingOperator_replacesOperator() public givenExistingOperator {
        vm.prank(_authorizedCaller);
        _configOperator.setConfigOperator(_other);

        assertEq(_configOperator.configOperator(), _other, "config operator");
        assertFalse(_configOperator.isConfigOperator(_operator), "old operator unauthorized");
        assertTrue(_configOperator.isConfigOperator(_other), "new operator authorized");
    }

    // setConfigOperator
    // given an operator is configured
    //  when the authorized caller sets the zero address
    //   then it revokes delegated access
    function test_givenExistingOperator_givenZeroAddress_revokesOperator()
        public
        givenExistingOperator
    {
        vm.expectEmit(true, false, false, true, address(_configOperator));
        emit IConfigOperator.ConfigOperatorSet(address(0));
        vm.prank(_authorizedCaller);
        _configOperator.setConfigOperator(address(0));

        assertEq(_configOperator.configOperator(), address(0), "config operator");
        assertFalse(_configOperator.isConfigOperator(_operator), "old operator unauthorized");
    }
}
