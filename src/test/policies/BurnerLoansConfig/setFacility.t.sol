// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";
import {MockBurnerLoansPolicy} from "src/test/policies/BurnerLoansConfig/fixtures/MockBurnerLoansPolicy.sol";

contract BurnerLoansConfigSetFacilityTest is BurnerLoansTest {
    BurnerLoansConfig internal unlinkedConfig;

    function setUp() public override {
        super.setUp();

        unlinkedConfig = new BurnerLoansConfig(kernel, IERC20(address(ohm)));
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(unlinkedConfig));
    }

    function test_givenCompatibleFacility_setsFacility() public {
        vm.expectEmit(true, false, false, true, address(unlinkedConfig));
        emit IBurnerLoansConfig.FacilitySet(address(burnerLoans));
        vm.prank(admin);
        unlinkedConfig.setFacility(address(burnerLoans));

        assertEq(unlinkedConfig.facility(), address(burnerLoans), "Burner Loans facility");
    }

    function test_givenCompatibleFacilityInactive_reverts() public {
        MockBurnerLoansPolicy inactiveFacility = new MockBurnerLoansPolicy(kernel, address(ohm));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(inactiveFacility)
            )
        );
        vm.prank(admin);
        unlinkedConfig.setFacility(address(inactiveFacility));
    }

    function test_givenFacilityAlreadySet_whenSettingCompatibleFacility_reverts() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        MockBurnerLoansPolicy replacement = new MockBurnerLoansPolicy(kernel, address(ohm));

        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        burnerLoansConfig.disable("");

        vm.expectRevert(IBurnerLoansConfig.BurnerLoansConfig_FacilityAlreadySet.selector);
        burnerLoansConfig.setFacility(address(replacement));
        vm.stopPrank();

        assertEq(burnerLoansConfig.facility(), address(burnerLoans), "Burner Loans facility");
        assertEq(burnerLoansConfig.marketId(address(usds)), marketId, "Burner Loans market");
    }

    function test_givenActiveFacilityReportsDifferentKernel_reverts() public {
        MockBurnerLoansPolicy replacement = new MockBurnerLoansPolicy(kernel, address(ohm));
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
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
        unlinkedConfig.setFacility(address(replacement));
        vm.stopPrank();
    }

    function test_givenActiveFacilityKernelCallReverts_reverts() public {
        MockBurnerLoansPolicy replacement = new MockBurnerLoansPolicy(kernel, address(ohm));
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
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
        unlinkedConfig.setFacility(address(replacement));
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

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                facility_
            )
        );
        vm.prank(admin);
        unlinkedConfig.setFacility(facility_);
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        unlinkedConfig.setFacility(address(burnerLoans));
    }
}
