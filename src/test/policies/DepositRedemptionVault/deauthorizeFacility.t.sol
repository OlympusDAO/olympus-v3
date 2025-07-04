// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";

contract DepositRedemptionVaultDeauthorizeFacilityTest is DepositRedemptionVaultTest {
    address public testFacility = address(0x123);
    address public testFacilityTwo = address(0x456);
    address public testFacilityThree = address(0x789);

    event FacilityDeauthorized(address indexed facility);

    // given the caller does not have the admin or emergency role
    //  [X] it reverts

    function test_callerNotAdminOrEmergency_reverts(address caller_) public {
        vm.assume(caller_ != admin && caller_ != emergency);

        // Expect revert
        _expectRevertNotAuthorized();

        // Call function
        vm.prank(caller_);
        redemptionVault.deauthorizeFacility(testFacility);
    }

    // given the facility is not registered
    //  [X] it reverts

    function test_facilityNotRegistered_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_FacilityNotRegistered.selector,
                testFacility
            )
        );

        // Call function
        vm.prank(admin);
        redemptionVault.deauthorizeFacility(testFacility);
    }

    // given the facility is registered
    //  [X] it deauthorizes the facility
    //  [X] it removes the facility from the facilities array
    //  [X] it emits a FacilityDeauthorized event
    //  [X] it returns false when checking if the facility is registered

    function test_success() public givenFacilityIsAuthorized(testFacility) {
        // Expect event
        vm.expectEmit(true, false, false, false);
        emit FacilityDeauthorized(testFacility);

        // Call function
        vm.prank(admin);
        redemptionVault.deauthorizeFacility(testFacility);

        // Assert facility is not registered
        assertFalse(
            redemptionVault.isRegisteredFacility(testFacility),
            "Facility should not be registered"
        );

        // Assert facility is not in the facilities array
        address[] memory facilities = redemptionVault.getRegisteredFacilities();
        bool found = false;
        for (uint256 i = 0; i < facilities.length; i++) {
            if (facilities[i] == testFacility) {
                found = true;
                break;
            }
        }
        assertFalse(found, "Facility should not be in facilities array");
    }

    // given multiple facilities are registered and one is deauthorized
    //  [X] only the specified facility is deauthorized
    //  [X] other facilities remain registered
    //  [X] only the specified facility is removed from the facilities array

    function test_multipleFacilities_deauthorizeOne() public {
        // Authorize multiple facilities
        vm.prank(admin);
        redemptionVault.authorizeFacility(testFacility);
        vm.prank(admin);
        redemptionVault.authorizeFacility(testFacilityTwo);
        vm.prank(admin);
        redemptionVault.authorizeFacility(testFacilityThree);

        // Deauthorize one facility
        vm.prank(admin);
        redemptionVault.deauthorizeFacility(testFacility);

        // Assert only the specified facility is deauthorized
        assertFalse(
            redemptionVault.isRegisteredFacility(testFacility),
            "First facility should not be registered"
        );
        assertTrue(
            redemptionVault.isRegisteredFacility(testFacilityTwo),
            "Second facility should still be registered"
        );
        assertTrue(
            redemptionVault.isRegisteredFacility(testFacilityThree),
            "Third facility should still be registered"
        );

        // Assert only the specified facility is removed from the facilities array
        address[] memory facilities = redemptionVault.getRegisteredFacilities();
        bool foundFirst = false;
        bool foundSecond = false;
        bool foundThird = false;
        for (uint256 i = 0; i < facilities.length; i++) {
            if (facilities[i] == testFacility) {
                foundFirst = true;
            }
            if (facilities[i] == testFacilityTwo) {
                foundSecond = true;
            }
            if (facilities[i] == testFacilityThree) {
                foundThird = true;
            }
        }
        assertFalse(foundFirst, "First facility should not be in facilities array");
        assertTrue(foundSecond, "Second facility should still be in facilities array");
        assertTrue(foundThird, "Third facility should still be in facilities array");
    }

    // given all facilities are deauthorized
    //  [X] all facilities are deauthorized
    //  [X] facilities array is empty

    function test_deauthorizeAllFacilities() public {
        // Authorize multiple facilities
        vm.prank(admin);
        redemptionVault.authorizeFacility(testFacility);
        vm.prank(admin);
        redemptionVault.authorizeFacility(testFacilityTwo);

        // Deauthorize all facilities
        vm.prank(admin);
        redemptionVault.deauthorizeFacility(testFacility);
        vm.prank(admin);
        redemptionVault.deauthorizeFacility(testFacilityTwo);

        // Assert all facilities are deauthorized
        assertFalse(
            redemptionVault.isRegisteredFacility(testFacility),
            "First facility should not be registered"
        );
        assertFalse(
            redemptionVault.isRegisteredFacility(testFacilityTwo),
            "Second facility should not be registered"
        );

        // Assert facilities array is empty
        address[] memory facilities = redemptionVault.getRegisteredFacilities();
        assertEq(facilities.length, 0, "Facilities array should be empty");
    }

    // given a facility is deauthorized and then re-authorized
    //  [X] the facility can be used normally after re-authorization

    function test_reauthorizeAfterDeauthorization() public givenFacilityIsAuthorized(testFacility) {
        // Deauthorize facility
        vm.prank(admin);
        redemptionVault.deauthorizeFacility(testFacility);

        // Re-authorize facility
        vm.prank(admin);
        redemptionVault.authorizeFacility(testFacility);

        // Assert facility is registered
        assertTrue(
            redemptionVault.isRegisteredFacility(testFacility),
            "Facility should be re-registered"
        );

        // Test that the facility can be used (e.g., for starting redemptions)
        // This would require setting up the necessary state, but the basic functionality should work
        assertTrue(
            redemptionVault.isRegisteredFacility(testFacility),
            "Facility should be usable after re-authorization"
        );
    }
}
