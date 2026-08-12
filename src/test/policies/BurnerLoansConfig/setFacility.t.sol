// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";
import {MockBurnerLoansPolicy} from "src/test/policies/BurnerLoansConfig/fixtures/MockBurnerLoansPolicy.sol";

contract BurnerLoansConfigSetFacilityTest is BurnerLoansTest {
    function test_givenCompatibleFacility_setsFacility() public {
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit IBurnerLoansConfig.FacilitySet(address(burnerLoans));
        vm.prank(admin);
        burnerLoansConfig.setFacility(address(burnerLoans));

        assertEq(burnerLoansConfig.facility(), address(burnerLoans), "Burner Loans facility");
    }

    function test_givenCompatibleFacilityInactive_reverts() public {
        MockBurnerLoansPolicy inactiveFacility = new MockBurnerLoansPolicy(kernel, address(ohm));
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(inactiveFacility)
            )
        );
        vm.prank(admin);
        burnerLoansConfig.setFacility(address(inactiveFacility));
    }

    function test_givenActiveFacilityReportsDifferentKernel_reverts() public {
        MockBurnerLoansPolicy replacement = new MockBurnerLoansPolicy(kernel, address(ohm));
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        burnerLoansConfig.disable("");
        vm.mockCall(
            address(replacement),
            abi.encodeWithSignature("kernel()"),
            abi.encode(makeAddr("otherKernel"))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(replacement)
            )
        );
        burnerLoansConfig.setFacility(address(replacement));
        vm.stopPrank();
    }

    function test_givenActiveFacilityKernelCallReverts_reverts() public {
        MockBurnerLoansPolicy replacement = new MockBurnerLoansPolicy(kernel, address(ohm));
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        burnerLoansConfig.disable("");
        vm.mockCallRevert(
            address(replacement),
            abi.encodeWithSignature("kernel()"),
            bytes("failure")
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(replacement)
            )
        );
        burnerLoansConfig.setFacility(address(replacement));
        vm.stopPrank();
    }

    function test_givenEnabled_reverts() public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(admin);
        burnerLoansConfig.setFacility(address(burnerLoans));
    }

    function test_givenInvalidAddress_reverts(address facility_) public {
        vm.assume(facility_ != address(burnerLoans));
        vm.assume(facility_.code.length == 0);
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                facility_
            )
        );
        vm.prank(admin);
        burnerLoansConfig.setFacility(facility_);
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        burnerLoansConfig.setFacility(address(burnerLoans));
    }
}
