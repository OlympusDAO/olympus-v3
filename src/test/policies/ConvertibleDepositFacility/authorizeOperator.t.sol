// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityAuthorizeOperatorTest is ConvertibleDepositFacilityTest {
    event OperatorAuthorized(address indexed operator);

    // ========== TESTS ========== //
    // given the contract is disabled
    //  [X] it reverts

    function test_givenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(admin);
        facility.authorizeOperator(OPERATOR);
    }

    // given the caller does not have the admin role
    //  [X] it reverts

    function test_givenCallerNotAdmin_reverts(address caller_) public givenLocallyActive {
        vm.assume(caller_ != admin);

        // Expect revert
        _expectRoleRevert("admin");

        // Call function
        vm.prank(caller_);
        facility.authorizeOperator(OPERATOR);
    }

    // when the operator address is zero
    //  [X] it reverts

    function test_whenZeroAddress_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertInvalidAddress(address(0));

        // Call function
        vm.prank(admin);
        facility.authorizeOperator(address(0));
    }

    // given the operator address is already authorized
    //  [X] it reverts

    function test_givenAuthorized_reverts()
        public
        givenLocallyActive
        givenOperatorAuthorized(OPERATOR)
    {
        // Expect revert
        _expectRevertInvalidAddress(OPERATOR);

        // Call function
        vm.prank(admin);
        facility.authorizeOperator(OPERATOR);
    }

    // [X] an event is emitted
    // [X] the operator is marked as authorized

    function test_success_fuzz(address operator_) public givenLocallyActive {
        vm.assume(operator_ != address(0));

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit OperatorAuthorized(operator_);

        // Call function
        vm.prank(admin);
        facility.authorizeOperator(operator_);

        // Assert state
        assertEq(
            facility.isAuthorizedOperator(operator_),
            true,
            "isAuthorizedOperator: should be true"
        );
    }
}
