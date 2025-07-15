// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityAuthorizeOperatorTest is ConvertibleDepositFacilityTest {
    event OperatorDeauthorized(address indexed operator);

    // ========== TESTS ========== //
    // given the contract is disabled
    //  [X] it reverts

    function test_givenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(admin);
        facility.deauthorizeOperator(OPERATOR);
    }

    // given the caller does not have the admin or emergency role
    //  [X] it reverts

    function test_givenCallerNotAdminNorEmergency_reverts(
        address caller_
    ) public givenLocallyActive {
        vm.assume(caller_ != admin && caller_ != emergency);

        // Expect revert
        _expectRevertNotAuthorized();

        // Call function
        vm.prank(caller_);
        facility.deauthorizeOperator(OPERATOR);
    }

    // given the operator address is not already authorized
    //  [X] it reverts

    function test_givenAddressNotAuthorized_reverts(address operator_) public givenLocallyActive {
        // Expect revert
        _expectRevertInvalidAddress(operator_);

        // Call function
        vm.prank(admin);
        facility.deauthorizeOperator(operator_);
    }

    // [X] an event is emitted
    // [X] the operator is marked as deauthorized

    function test_success(
        bool isAdmin
    ) public givenLocallyActive givenOperatorAuthorized(OPERATOR) {
        address caller = isAdmin ? admin : emergency;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit OperatorDeauthorized(OPERATOR);

        // Call function
        vm.prank(caller);
        facility.deauthorizeOperator(OPERATOR);

        // Assert state
        assertEq(facility.isAuthorizedOperator(OPERATOR), false, "isAuthorizedOperator");
    }
}
