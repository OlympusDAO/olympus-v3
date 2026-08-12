// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {BurnerLoansInventoryPrincipal, BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventorySetConfiguratorTest is BurnerLoansInventoryTest {
    function test_givenValidConfigurator_setsAddress() public {
        vm.expectEmit(true, false, false, true, address(inventory));
        emit IBurnerLoansInventory.ConfiguratorSet(address(config));

        vm.prank(admin);
        inventory.setConfigurator(address(config));

        assertEq(inventory.configurator(), address(config), "configurator");
    }

    function test_givenReplacementConfigurator_replacesAddress() public {
        BurnerLoansInventoryPrincipal replacement = new BurnerLoansInventoryPrincipal(
            kernel,
            address(facility)
        );

        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        inventory.setConfigurator(address(config));
        inventory.setConfigurator(address(replacement));
        vm.stopPrank();

        assertEq(inventory.configurator(), address(replacement), "replacement configurator");
    }

    function test_givenCompatibleConfiguratorInactive_reverts() public {
        BurnerLoansInventoryPrincipal inactiveConfigurator = new BurnerLoansInventoryPrincipal(
            kernel,
            address(facility)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidPolicy.selector,
                address(inactiveConfigurator)
            )
        );
        vm.prank(admin);
        inventory.setConfigurator(address(inactiveConfigurator));
    }

    function test_givenZeroAddress_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAddress.selector);
        vm.prank(admin);
        inventory.setConfigurator(address(0));
    }

    function test_givenEOA_reverts(address configurator_) public {
        vm.assume(configurator_.code.length == 0);
        vm.assume(configurator_ != address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidPolicy.selector,
                configurator_
            )
        );
        vm.prank(admin);
        inventory.setConfigurator(configurator_);
    }

    function test_givenActiveConfiguratorReportsForeignKernel_reverts() public {
        Kernel otherKernel = new Kernel();
        BurnerLoansInventoryPrincipal otherConfig = new BurnerLoansInventoryPrincipal(
            otherKernel,
            address(facility)
        );

        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(otherConfig));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidPolicy.selector,
                address(otherConfig)
            )
        );
        inventory.setConfigurator(address(otherConfig));
        vm.stopPrank();
    }

    function test_givenDifferentFacility_reverts() public {
        BurnerLoansInventoryPrincipal otherConfig = new BurnerLoansInventoryPrincipal(
            kernel,
            makeAddr("differentFacility")
        );

        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(otherConfig));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidPolicy.selector,
                address(otherConfig)
            )
        );
        vm.prank(admin);
        inventory.setConfigurator(address(otherConfig));
    }

    function test_givenActiveConfiguratorKernelCallReverts_reverts() public {
        vm.mockCallRevert(address(config), abi.encodeWithSignature("kernel()"), bytes("failure"));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidPolicy.selector,
                address(config)
            )
        );
        vm.prank(admin);
        inventory.setConfigurator(address(config));
    }

    function test_givenFacilityCallReverts_mapsToInvalidPolicy() public {
        vm.mockCallRevert(
            address(config),
            abi.encodeCall(BurnerLoansInventoryPrincipal.facility, ()),
            bytes("failure")
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidPolicy.selector,
                address(config)
            )
        );
        vm.prank(admin);
        inventory.setConfigurator(address(config));
    }

    function test_givenEnabled_reverts() public {
        vm.prank(admin);
        inventory.enable("");

        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(admin);
        inventory.setConfigurator(address(config));
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        inventory.setConfigurator(address(config));
    }
}
