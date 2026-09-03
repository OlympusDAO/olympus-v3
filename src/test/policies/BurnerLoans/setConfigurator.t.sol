// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansSetConfiguratorTest is BurnerLoansTest {
    function test_givenZeroAddress_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(0)
            )
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(0));
    }

    function test_givenCompatibleConfigurator_setsConfigurator() public {
        vm.prank(admin);
        burnerLoans.disable("");

        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit IBurnerLoans.ConfiguratorSet(address(burnerLoansConfig));
        vm.prank(admin);
        burnerLoans.setConfigurator(address(burnerLoansConfig));

        assertEq(burnerLoans.configurator(), address(burnerLoansConfig), "configurator");
    }

    function test_givenCompatibleReplacement_setsConfigurator() public {
        BurnerLoansConfig replacement = new BurnerLoansConfig(kernel, IERC20(address(ohm)));
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        replacement.setFacility(address(burnerLoans));
        burnerLoans.disable("");
        burnerLoans.setConfigurator(address(replacement));
        vm.stopPrank();

        assertEq(burnerLoans.configurator(), address(replacement), "replacement configurator");
    }

    function test_givenCompatibleConfiguratorInactive_reverts() public {
        BurnerLoansConfig replacement = new BurnerLoansConfig(kernel, IERC20(address(ohm)));
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        replacement.setFacility(address(burnerLoans));
        kernel.executeAction(Actions.DeactivatePolicy, address(replacement));
        burnerLoans.disable("");
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(replacement)
            )
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(replacement));
    }

    function test_givenActiveConfiguratorReportsDifferentKernel_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");
        vm.mockCall(
            address(burnerLoansConfig),
            abi.encodeWithSignature("kernel()"),
            abi.encode(makeAddr("otherKernel"))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(burnerLoansConfig)
            )
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(burnerLoansConfig));
    }

    function test_givenActiveConfiguratorKernelCallReverts_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");
        vm.mockCallRevert(
            address(burnerLoansConfig),
            abi.encodeWithSignature("kernel()"),
            bytes("failure")
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(burnerLoansConfig)
            )
        );
        vm.prank(admin);
        burnerLoans.setConfigurator(address(burnerLoansConfig));
    }

    function test_givenEnabled_reverts() public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(admin);
        burnerLoans.setConfigurator(address(burnerLoansConfig));
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.prank(admin);
        burnerLoans.disable("");

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        burnerLoans.setConfigurator(address(burnerLoansConfig));
    }

    function test_givenConfiguratorAgreementMismatch_enableReverts() public {
        BurnerLoansConfig replacement = new BurnerLoansConfig(kernel, IERC20(address(ohm)));
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        replacement.setFacility(address(burnerLoans));
        burnerLoans.disable("");
        burnerLoans.setConfigurator(address(replacement));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidInventory.selector,
                address(inventory)
            )
        );
        burnerLoans.enable("");
        vm.stopPrank();
    }
}
