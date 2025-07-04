// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

contract DepositRedemptionVaultAuthorizeFacilityTest is DepositRedemptionVaultTest {
    address public testFacility = address(0x123);
    address public testFacilityTwo = address(0x456);

    event FacilityRegistered(address indexed facility);

    // given the caller does not have the admin role
    //  [X] it reverts

    function test_callerNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        // Expect revert
        _expectRoleRevert(bytes32("admin"));

        // Call function
        vm.prank(caller_);
        redemptionVault.authorizeFacility(testFacility);
    }

    // given the facility address is zero
    //  [X] it reverts

    function test_facilityAddressZero_reverts() public {
        // Expect revert
        _expectRevertInvalidFacility(address(0));

        // Call function
        vm.prank(admin);
        redemptionVault.authorizeFacility(address(0));
    }

    // given the facility is already registered
    //  [X] it reverts

    function test_facilityAlreadyRegistered_reverts() public {
        // Expect revert
        _expectRevertFacilityExists(address(cdFacility));

        // Call function
        vm.prank(admin);
        redemptionVault.authorizeFacility(address(cdFacility));
    }

    // given the facility does not implement the IDepositFacility interface
    //  [X] it reverts

    function test_facilityDoesNotImplementIDepositFacility_reverts() public {
        // Expect revert
        _expectRevertInvalidFacility(testFacility);

        // Call function
        vm.prank(admin);
        redemptionVault.authorizeFacility(testFacility);
    }

    // given the facility is not already registered
    //  [X] it registers the facility
    //  [X] it adds the facility to the facilities array
    //  [X] it emits a FacilityRegistered event
    //  [X] it returns true when checking if the facility is registered

    function test_success() public givenFacilityIsDeauthorized(address(cdFacility)) {
        // Expect event
        vm.expectEmit(true, false, false, false);
        emit FacilityRegistered(address(cdFacility));

        // Call function
        vm.prank(admin);
        redemptionVault.authorizeFacility(address(cdFacility));

        // Assert facility is registered
        assertTrue(
            redemptionVault.isRegisteredFacility(address(cdFacility)),
            "Facility should be registered"
        );

        // Assert facility is in the facilities array
        address[] memory facilities = redemptionVault.getRegisteredFacilities();
        bool found = false;
        for (uint256 i = 0; i < facilities.length; i++) {
            if (facilities[i] == address(cdFacility)) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Facility should be in facilities array");
    }

    // given multiple facilities are authorized
    //  [X] all facilities are registered correctly
    //  [X] all facilities are in the facilities array
    //  [X] all facilities return true when checking if registered

    function test_multipleFacilities()
        public
        givenFacilityIsDeauthorized(address(cdFacility))
        givenFacilityIsDeauthorized(address(ydFacility))
    {
        // Authorize first facility
        vm.prank(admin);
        redemptionVault.authorizeFacility(address(cdFacility));

        // Authorize second facility
        vm.prank(admin);
        redemptionVault.authorizeFacility(address(ydFacility));

        // Assert both facilities are registered
        assertTrue(
            redemptionVault.isRegisteredFacility(address(cdFacility)),
            "First facility should be registered"
        );
        assertTrue(
            redemptionVault.isRegisteredFacility(address(ydFacility)),
            "Second facility should be registered"
        );

        // Assert both facilities are in the facilities array
        address[] memory facilities = redemptionVault.getRegisteredFacilities();
        bool foundFirst = false;
        bool foundSecond = false;
        for (uint256 i = 0; i < facilities.length; i++) {
            if (facilities[i] == address(cdFacility)) {
                foundFirst = true;
            }
            if (facilities[i] == address(ydFacility)) {
                foundSecond = true;
            }
        }
        assertTrue(foundFirst, "First facility should be in facilities array");
        assertTrue(foundSecond, "Second facility should be in facilities array");
    }

    // given the facility is authorized and then deauthorized
    //  [X] it can be re-authorized successfully

    function test_reauthorizeAfterDeauthorization()
        public
        givenFacilityIsDeauthorized(address(cdFacility))
    {
        // Authorize facility
        vm.prank(admin);
        redemptionVault.authorizeFacility(address(cdFacility));

        // Deauthorize facility
        vm.prank(admin);
        redemptionVault.deauthorizeFacility(address(cdFacility));

        // Re-authorize facility
        vm.expectEmit(true, false, false, false);
        emit FacilityRegistered(address(cdFacility));

        vm.prank(admin);
        redemptionVault.authorizeFacility(address(cdFacility));

        // Assert facility is registered
        assertTrue(
            redemptionVault.isRegisteredFacility(address(cdFacility)),
            "Facility should be re-registered"
        );
    }
}
