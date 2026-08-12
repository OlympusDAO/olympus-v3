// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";

// Contracts
import {Actions, Kernel, Policy, toKeycode} from "src/Kernel.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {BurnerLoansConfigTimelock} from "src/policies/BurnerLoansConfigTimelock.sol";
import {MockConfigUnsupportedRoles} from "src/test/policies/BurnerLoansConfig/fixtures/MockConfigModules.sol";
import {MockBurnerLoansPolicy} from "src/test/policies/BurnerLoansConfig/fixtures/MockBurnerLoansPolicy.sol";

import {BurnerLoansConfigTimelockTest} from "src/test/policies/BurnerLoansConfigTimelock/BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockConfigureDependenciesTest is BurnerLoansConfigTimelockTest {
    // configureDependencies
    // given policy activated
    //  when configureDependencies is called
    //   then it sets roles module
    function test_givenPolicyActivated_configureDependencies_setsRolesModule() public view {
        assertEq(address(configTimelock.ROLES()), address(roles), "ROLES");
    }

    // configureDependencies
    // given ROLES is not installed
    //  when the timelock is activated
    //   then activation reverts for the missing module
    function test_givenRolesModuleMissing_reverts() public {
        Kernel localKernel = new Kernel();
        BurnerLoansConfigTimelock localTimelock = _deployTimelock(localKernel);

        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        localKernel.executeAction(Actions.ActivatePolicy, address(localTimelock));
    }

    // configureDependencies
    // given ROLES has an unsupported major version
    //  when the timelock is activated
    //   then activation reverts with the timelock's version error
    function test_givenRolesModuleVersionUnsupported_reverts() public {
        Kernel localKernel = new Kernel();
        BurnerLoansConfigTimelock localTimelock = _deployTimelock(localKernel);
        localKernel.executeAction(
            Actions.InstallModule,
            address(new MockConfigUnsupportedRoles(localKernel))
        );

        vm.expectRevert(
            IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_InvalidModuleVersion.selector
        );
        localKernel.executeAction(Actions.ActivatePolicy, address(localTimelock));
    }

    function _deployTimelock(
        Kernel kernel_
    ) internal returns (BurnerLoansConfigTimelock localTimelock) {
        MockBurnerLoansPolicy facility = new MockBurnerLoansPolicy(kernel_, address(ohm));
        kernel_.executeAction(Actions.ActivatePolicy, address(facility));
        BurnerLoansConfig localConfig = new BurnerLoansConfig(kernel_, IERC20(address(ohm)));
        localTimelock = new BurnerLoansConfigTimelock(kernel_, localConfig);
    }
}
