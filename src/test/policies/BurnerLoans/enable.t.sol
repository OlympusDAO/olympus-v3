// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {BurnerLoansInventory} from "src/policies/BurnerLoansInventory.sol";
import {Actions} from "src/Kernel.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansEnableTest is BurnerLoansTest {
    event Enabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at);

    // enable
    // given caller has the admin role
    //  when enable is called while disabled
    //   then the policy is enabled and transition time is recorded
    function test_enable_givenAdminCaller_enablesPolicyAndRecordsTransition() public {
        vm.warp(1234);
        vm.prank(admin);
        burnerLoans.disable("");

        vm.prank(admin);
        vm.expectEmit(address(burnerLoans));
        emit Enabled();
        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit Transition(admin, true, "", 1234);
        burnerLoans.enable("");

        assertTrue(burnerLoans.isEnabled(), "enabled");
        assertEq(burnerLoans.lastTransitionAt(), 1234, "last transition");
    }

    // enable
    // given caller does not have the admin role
    //  when enable is called
    //   then it reverts
    function test_enable_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.prank(admin);
        burnerLoans.disable("");

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        burnerLoans.enable("");
    }

    // enable
    // given the policy is already enabled
    //  when enable is called by admin
    //   then it reverts
    function test_enable_givenAlreadyEnabled_reverts() public {
        vm.prank(admin);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        burnerLoans.enable("");
    }

    // enable
    // given the configured Burner Loans Inventory is globally disabled
    //  when admin enables Burner Loans
    //   then it reverts
    function test_givenInventoryDisabled_reverts() public {
        vm.startPrank(admin);
        burnerLoans.disable("");
        inventory.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InventoryNotEnabled.selector,
                address(inventory)
            )
        );
        burnerLoans.enable("");
        vm.stopPrank();
    }

    // enable
    // given a compatible but inactive Burner Loans Inventory was staged while disabled
    //  when admin enables Burner Loans
    //   then it reverts
    function test_givenInventoryInactive_reverts() public {
        vm.startPrank(admin);
        burnerLoans.disable("");
        BurnerLoansInventory replacement = new BurnerLoansInventory(
            kernel,
            IERC20(address(ohm)),
            address(burnerLoans)
        );
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        replacement.setConfigurator(address(burnerLoansConfig));
        replacement.enable("");
        burnerLoans.setInventory(address(replacement));
        kernel.executeAction(Actions.DeactivatePolicy, address(replacement));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InventoryNotActive.selector,
                address(replacement)
            )
        );
        burnerLoans.enable("");
        vm.stopPrank();
    }

    function test_givenInventoryReportsDifferentKernel_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");
        vm.mockCall(
            address(inventory),
            abi.encodeWithSignature("kernel()"),
            abi.encode(makeAddr("otherKernel"))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidInventory.selector,
                address(inventory)
            )
        );
        vm.prank(admin);
        burnerLoans.enable("");
    }

    // enable
    // given Burner Loans Config is globally disabled
    //  when admin enables Burner Loans
    //   then existing-loan servicing remains available
    function test_givenConfiguratorDisabled_enables() public {
        vm.startPrank(admin);
        burnerLoans.disable("");
        burnerLoansConfig.disable("");
        burnerLoans.enable("");
        vm.stopPrank();

        assertTrue(burnerLoans.isEnabled(), "Burner Loans enabled");
        assertFalse(burnerLoansConfig.isEnabled(), "Config remains disabled");
    }

    // enable
    // given Burner Loans Config is inactive in the Kernel
    //  when admin enables Burner Loans
    //   then it reverts because linked policies are revalidated before enablement
    function test_givenConfiguratorInactive_reverts() public {
        vm.startPrank(admin);
        burnerLoans.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoansConfig));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(burnerLoansConfig)
            )
        );
        burnerLoans.enable("");
        vm.stopPrank();
    }

    function test_givenConfiguratorReportsDifferentKernel_reverts() public {
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
        burnerLoans.enable("");
    }

    // enable
    // given the constructor-bound Deposit Manager is inactive in the Kernel
    //  when admin enables Burner Loans
    //   then it reverts
    function test_givenDepositManagerInactive_reverts() public {
        vm.startPrank(admin);
        burnerLoans.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoans.enable("");
        vm.stopPrank();
    }
}
