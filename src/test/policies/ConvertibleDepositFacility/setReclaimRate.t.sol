// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract SetReclaimRateCDFTest is ConvertibleDepositFacilityTest {
    // given the caller does not have the admin role
    //  [X] it reverts
    // given the contract is inactive
    //  [X] it sets the reclaim rate on CDEPO
    // [X] it sets the reclaim rate on CDEPO

    function test_callerNotAdmin_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("cd_admin"))
        );

        // Call function
        vm.prank(auctioneer);
        facility.setReclaimRate(99e2);
    }

    function test_contractInactive() public {
        // Call function
        vm.prank(admin);
        facility.setReclaimRate(99e2);

        // Assert
        assertEq(convertibleDepository.reclaimRate(), 99e2);
    }

    function test_setReclaimRate() public givenLocallyActive {
        // Call function
        vm.prank(admin);
        facility.setReclaimRate(99e2);

        // Assert
        assertEq(convertibleDepository.reclaimRate(), 99e2);
    }
}
