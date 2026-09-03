// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions, Kernel, Keycode, Module, Policy, toKeycode} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {OlympusFixedTermLoan} from "src/modules/FLOAN/OlympusFixedTermLoan.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";
import {MockConfigUnsupportedFloan, MockConfigUnsupportedRoles} from "src/test/policies/BurnerLoansConfig/fixtures/MockConfigModules.sol";
import {MockBurnerLoansPolicy} from "src/test/policies/BurnerLoansConfig/fixtures/MockBurnerLoansPolicy.sol";

contract BurnerLoansConfigConfigureDependenciesTest is BurnerLoansTest {
    // configureDependencies
    // given config activated
    //  when configureDependencies is called
    //   then it sets modules and preserves the immutable OHM dependency
    function test_givenConfigActivated_configureDependencies_setsRolesModule() public view {
        assertEq(address(burnerLoansConfig.ROLES()), address(roles), "ROLES");
        assertEq(burnerLoansConfig.ohm(), address(ohm), "OHM");
    }

    // configureDependencies
    // given FLOAN is not installed
    //  when Config is activated
    //   then activation reverts for the missing module
    function test_givenFloanMissing_reverts() public {
        Kernel localKernel = new Kernel();
        _expectMissingModuleRevert(
            localKernel,
            Module(address(0)),
            new OlympusRoles(localKernel),
            toKeycode("FLOAN")
        );
    }

    // configureDependencies
    // given ROLES is not installed
    //  when Config is activated
    //   then activation reverts for the missing module
    function test_givenRolesMissing_reverts() public {
        Kernel localKernel = new Kernel();
        _expectMissingModuleRevert(
            localKernel,
            new OlympusFixedTermLoan(localKernel),
            Module(address(0)),
            toKeycode("ROLES")
        );
    }

    // configureDependencies
    // given FLOAN has an unsupported major version
    //  when Config is activated
    //   then activation reverts
    function test_givenFloanVersionUnsupported_reverts() public {
        Kernel localKernel = new Kernel();
        _expectInvalidVersionRevert(
            localKernel,
            new MockConfigUnsupportedFloan(localKernel),
            new OlympusRoles(localKernel)
        );
    }

    // configureDependencies
    // given ROLES has an unsupported major version
    //  when Config is activated
    //   then activation reverts
    function test_givenRolesVersionUnsupported_reverts() public {
        Kernel localKernel = new Kernel();
        _expectInvalidVersionRevert(
            localKernel,
            new OlympusFixedTermLoan(localKernel),
            new MockConfigUnsupportedRoles(localKernel)
        );
    }

    function _expectMissingModuleRevert(
        Kernel kernel_,
        Module floan_,
        Module roles_,
        Keycode missing_
    ) internal {
        BurnerLoansConfig localConfig = _deployConfigWithModules(kernel_, floan_, roles_);

        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, missing_)
        );
        kernel_.executeAction(Actions.ActivatePolicy, address(localConfig));
    }

    function _expectInvalidVersionRevert(Kernel kernel_, Module floan_, Module roles_) internal {
        BurnerLoansConfig localConfig = _deployConfigWithModules(kernel_, floan_, roles_);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidModuleVersion.selector);
        kernel_.executeAction(Actions.ActivatePolicy, address(localConfig));
    }

    function _deployConfigWithModules(
        Kernel kernel_,
        Module floan_,
        Module roles_
    ) internal returns (BurnerLoansConfig localConfig) {
        MockBurnerLoansPolicy facility_ = new MockBurnerLoansPolicy(kernel_, address(ohm));
        kernel_.executeAction(Actions.ActivatePolicy, address(facility_));

        if (address(floan_) != address(0)) {
            kernel_.executeAction(Actions.InstallModule, address(floan_));
        }
        if (address(roles_) != address(0)) {
            kernel_.executeAction(Actions.InstallModule, address(roles_));
        }

        localConfig = new BurnerLoansConfig(kernel_, IERC20(address(ohm)));
    }
}
