// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansInventory} from "src/policies/BurnerLoansInventory.sol";

import {BurnerLoansInventoryPrincipal, BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventoryConstructorTest is BurnerLoansInventoryTest {
    // constructor
    // [X] given valid parameters, it stores immutable dependencies and starts with zero accounting
    function test_givenValidParameters_setsZeroState() public view {
        assertEq(inventory.ohm(), address(ohm), "OHM");
        assertEq(inventory.configurator(), address(0), "configurator");
        assertEq(inventory.facility(), address(facility), "immutable facility");
        assertFalse(inventory.isEnabled(), "enabled");
        assertEq(inventory.globalDebtCapOhm(), 0, "global cap");
        assertEq(inventory.activePrincipalOhm(), 0, "active principal");
        assertEq(inventory.suppliedIdleOhm(), 0, "supplied idle");
        assertEq(inventory.suppliedOhm(), 0, "supplied claim");
        (uint8 major, uint8 minor) = inventory.VERSION();
        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
    }

    // constructor
    // [X] given zero OHM, it reverts
    function test_givenZeroOhm_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAddress.selector);
        new BurnerLoansInventory(kernel, IERC20(address(0)), address(facility));
    }

    // constructor
    // [X] given zero facility, it reverts
    function test_givenZeroFacility_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAddress.selector);
        new BurnerLoansInventory(kernel, IERC20(address(ohm)), address(0));
    }

    // constructor
    // [X] given the facility belongs to another Kernel, it reverts
    function test_givenDifferentKernelFacility_reverts() public {
        BurnerLoansInventoryPrincipal foreignFacility = new BurnerLoansInventoryPrincipal(
            new Kernel(),
            address(0)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidPolicy.selector,
                address(foreignFacility)
            )
        );
        new BurnerLoansInventory(kernel, IERC20(address(ohm)), address(foreignFacility));
    }

    // constructor
    // [X] given a same-Kernel facility is not yet active, deployment still succeeds
    function test_givenInactiveSameKernelFacility_succeeds() public {
        BurnerLoansInventoryPrincipal inactiveFacility = new BurnerLoansInventoryPrincipal(
            kernel,
            address(0)
        );

        BurnerLoansInventory deployed = new BurnerLoansInventory(
            kernel,
            IERC20(address(ohm)),
            address(inactiveFacility)
        );

        assertEq(deployed.facility(), address(inactiveFacility), "immutable facility");
    }
}
