// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {IYieldDepositFacility} from "src/policies/interfaces/IYieldDepositFacility.sol";

contract SetYieldFeeYDFTest is YieldDepositFacilityTest {
    event YieldFeeSet(uint16 yieldFee);

    // given the contract is disabled
    //  [X] it reverts
    // given the caller is not an admin
    //  [X] it reverts
    // given the yield fee is greater than 100e2
    //  [X] it reverts
    // [X] it sets the yield fee
    // [X] it emits a YieldFeeSet event

    function test_givenDisabled_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));

        // Call the function
        vm.prank(admin);
        yieldDepositFacility.setYieldFee(100e2);
    }

    function test_givenCallerIsNotAdmin_reverts() public givenLocallyActive {
        // Expect revert
        _expectRoleRevert("admin");

        // Call the function
        vm.prank(recipient);
        yieldDepositFacility.setYieldFee(100e2);
    }

    function test_givenYieldFeeGreaterThan100e2_reverts() public givenLocallyActive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IYieldDepositFacility.YDF_InvalidArgs.selector, "yield fee")
        );

        // Call the function
        vm.prank(admin);
        yieldDepositFacility.setYieldFee(100e2 + 1);
    }

    function test_success(uint16 yieldFee) public givenLocallyActive {
        yieldFee = uint16(bound(yieldFee, 0, 100e2));

        // Expect event to be emitted
        vm.expectEmit(true, true, true, true);
        emit YieldFeeSet(yieldFee);

        // Call the function
        vm.prank(admin);
        yieldDepositFacility.setYieldFee(yieldFee);

        // Assert
        assertEq(yieldDepositFacility.getYieldFee(), yieldFee);
    }
}
