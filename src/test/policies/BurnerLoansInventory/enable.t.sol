// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventoryEnableTest is BurnerLoansInventoryTest {
    // enable
    // [X] given no configurator, it can still be enabled for independent wiring
    function test_givenNoConfigurator_succeeds() public {
        vm.prank(admin);
        inventory.enable("");
        assertTrue(inventory.isEnabled(), "Burner Loans Inventory enabled");
    }

    // enable
    // [X] given the immutable Burner Loans facility is inactive, enablement revalidates the link
    function test_givenFacilityInactive_reverts() public {
        vm.startPrank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(facility));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidPolicy.selector,
                address(facility)
            )
        );
        inventory.enable("");
        vm.stopPrank();
    }

    // enable
    // [X] given the immutable Burner Loans facility reports another Kernel, enablement reverts
    function test_givenFacilityReportsDifferentKernel_reverts() public {
        vm.mockCall(
            address(facility),
            abi.encodeWithSignature("kernel()"),
            abi.encode(makeAddr("otherKernel"))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidPolicy.selector,
                address(facility)
            )
        );
        vm.prank(admin);
        inventory.enable("");
    }

    // enable
    // [X] given a configured Burner Loans Config policy becomes inactive, enablement revalidates it
    function test_givenConfiguratorInactive_reverts() public {
        vm.startPrank(admin);
        inventory.setConfigurator(address(config));
        kernel.executeAction(Actions.DeactivatePolicy, address(config));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidPolicy.selector,
                address(config)
            )
        );
        inventory.enable("");
        vm.stopPrank();
    }

    // enable
    // [X] given Burner Loans Config reports another Kernel, enablement revalidates it
    function test_givenConfiguratorReportsDifferentKernel_reverts() public {
        vm.prank(admin);
        inventory.setConfigurator(address(config));
        vm.mockCall(
            address(config),
            abi.encodeWithSignature("kernel()"),
            abi.encode(makeAddr("otherKernel"))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidPolicy.selector,
                address(config)
            )
        );
        vm.prank(admin);
        inventory.enable("");
    }
}
