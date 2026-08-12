// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {BurnerLoansInventory} from "src/policies/BurnerLoansInventory.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {BurnerLoansHarness} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarness.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansSetInventoryTest is BurnerLoansTest {
    // setInventory
    // given Burner Loans is disabled and replacement Burner Loans Inventory is compatible
    //  when admin sets it
    //   then Burner Loans and Config resolve the replacement
    function test_givenDisabledAndCompatibleInventory_setsReplacement() public {
        vm.prank(admin);
        burnerLoans.disable("");
        BurnerLoansInventory replacement = _deployEnabledInventory(address(burnerLoans));

        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit IBurnerLoans.InventorySet(address(replacement));
        vm.prank(admin);
        burnerLoans.setInventory(address(replacement));

        assertEq(burnerLoans.inventory(), address(replacement), "Burner Loans inventory");
        assertEq(burnerLoansConfig.inventory(), address(replacement), "Config inventory");

        vm.startPrank(admin);
        burnerLoansConfig.setGlobalDebtCap(1_000_000e9);
        vm.stopPrank();
        assertEq(
            replacement.globalDebtCapOhm(),
            1_000_000e9,
            "Config writes replacement Burner Loans Inventory"
        );
    }

    // setInventory
    // given the replacement was initialized with another Config policy
    //  when Config tries to administer it after Burner Loans accepts the pointer
    //   then Config rejects the incompatible link
    function test_givenReplacementUsesDifferentConfig_configWriteReverts() public {
        vm.prank(admin);
        burnerLoans.disable("");
        BurnerLoansConfig otherConfig = new BurnerLoansConfig(kernel, IERC20(address(ohm)));
        BurnerLoansInventory replacement = new BurnerLoansInventory(
            kernel,
            IERC20(address(ohm)),
            address(burnerLoans)
        );
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(otherConfig));
        otherConfig.setFacility(address(burnerLoans));
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        replacement.setConfigurator(address(otherConfig));
        replacement.enable("");
        burnerLoans.setInventory(address(replacement));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_Unauthorized.selector,
                address(burnerLoansConfig)
            )
        );
        burnerLoansConfig.setGlobalDebtCap(1_000_000e9);
        vm.stopPrank();
    }

    // setInventory
    // given Burner Loans is enabled
    //  when admin tries to replace Burner Loans Inventory
    //   then it reverts before changing the pointer
    function test_givenEnabled_reverts() public {
        vm.prank(admin);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        burnerLoans.setInventory(address(inventory));

        assertEq(burnerLoans.inventory(), address(inventory), "inventory unchanged");
    }

    // setInventory
    // given the current Burner Loans Inventory still has active principal
    //  when admin tries to replace it while Burner Loans is disabled
    //   then Burner Loans accepts the replacement without requiring the old contract to drain
    function test_givenCurrentInventoryHasActivePrincipal_setsReplacement() public {
        vm.prank(admin);
        burnerLoansConfig.setGlobalDebtCap(1e9);
        vm.prank(address(burnerLoans));
        inventory.draw(address(this), 1e9);
        vm.prank(admin);
        burnerLoans.disable("");
        BurnerLoansInventory replacement = _deployEnabledInventory(address(burnerLoans));

        vm.prank(admin);
        burnerLoans.setInventory(address(replacement));

        assertEq(burnerLoans.inventory(), address(replacement), "replacement inventory");
        assertEq(inventory.activePrincipalOhm(), 1e9, "old active principal unchanged");
    }

    // setInventory
    // given the current Burner Loans Inventory still owes a provider claim
    //  when admin tries to replace it while Burner Loans is disabled
    //   then Burner Loans accepts the replacement without requiring the old contract to drain
    function test_givenCurrentInventoryHasProviderClaim_setsReplacement() public {
        ohm.mint(protocolProvider, 1e9);
        vm.startPrank(protocolProvider);
        ohm.approve(address(inventory), 1e9);
        inventory.supply(1e9);
        vm.stopPrank();
        vm.prank(admin);
        burnerLoans.disable("");
        BurnerLoansInventory replacement = _deployEnabledInventory(address(burnerLoans));

        vm.prank(admin);
        burnerLoans.setInventory(address(replacement));

        assertEq(burnerLoans.inventory(), address(replacement), "replacement inventory");
        assertEq(inventory.suppliedOhm(), 1e9, "old supplied OHM unchanged");
    }

    // setInventory
    // given Burner Loans is disabled and caller is not OCG admin
    //  when caller tries to replace Burner Loans Inventory
    //   then it reverts
    function test_givenCallerIsNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.prank(admin);
        burnerLoans.disable("");

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        burnerLoans.setInventory(address(inventory));
    }

    // setInventory
    // given the replacement address is zero
    //  when admin sets it while disabled
    //   then it reverts as an invalid Burner Loans Inventory
    function test_givenZeroInventory_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidInventory.selector, address(0))
        );
        burnerLoans.setInventory(address(0));
    }

    // setInventory
    // given the replacement Burner Loans Inventory is not active in the Kernel
    //  when admin sets it while Burner Loans is disabled
    //   then it reverts because Kernel activation is the authoritative trust boundary
    function test_givenInventoryIsInactive_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");
        BurnerLoansInventory replacement = new BurnerLoansInventory(
            kernel,
            IERC20(address(ohm)),
            address(burnerLoans)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InventoryNotActive.selector,
                address(replacement)
            )
        );
        vm.prank(admin);
        burnerLoans.setInventory(address(replacement));
    }

    // setInventory
    // given the replacement Burner Loans Inventory is active but globally disabled
    //  when admin sets it while Burner Loans is disabled
    //   then staged wiring succeeds
    function test_givenInventoryIsDisabled_setsInventory() public {
        vm.prank(admin);
        burnerLoans.disable("");
        BurnerLoansInventory replacement = new BurnerLoansInventory(
            kernel,
            IERC20(address(ohm)),
            address(burnerLoans)
        );
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        replacement.setConfigurator(address(burnerLoansConfig));

        burnerLoans.setInventory(address(replacement));
        assertEq(burnerLoans.inventory(), address(replacement), "staged disabled inventory");
        vm.stopPrank();
    }

    // setInventory
    // given the replacement Burner Loans Inventory is permanently bound to another facility
    //  when admin sets it
    //   then it reverts
    function test_givenInventoryFacilityMismatch_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");
        BurnerLoansInventory replacement = new BurnerLoansInventory(
            kernel,
            IERC20(address(ohm)),
            address(burnerLoansConfig)
        );
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        replacement.enable("");
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InventoryFacilityMismatch.selector,
                address(burnerLoans),
                address(burnerLoansConfig)
            )
        );
        burnerLoans.setInventory(address(replacement));
    }

    // setInventory
    // given an active replacement Burner Loans Inventory reports another Kernel
    //  when admin sets it
    //   then it reverts
    function test_givenActiveInventoryReportsDifferentKernel_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");
        Kernel otherKernel = new Kernel();
        vm.mockCall(
            address(inventory),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(otherKernel))
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidInventory.selector,
                address(inventory)
            )
        );
        burnerLoans.setInventory(address(inventory));
    }

    // setInventory
    // given an active replacement Burner Loans Inventory reverts when reporting its Kernel
    //  when admin sets it
    //   then it reverts
    function test_givenActiveInventoryKernelCallReverts_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");
        vm.mockCallRevert(
            address(inventory),
            abi.encodeWithSignature("kernel()"),
            bytes("failure")
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidInventory.selector,
                address(inventory)
            )
        );
        burnerLoans.setInventory(address(inventory));
    }

    // setInventory
    // given the replacement Burner Loans Inventory reports another OHM token
    //  when admin sets it
    //   then it reverts
    function test_givenInventoryOhmMismatch_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");
        MockOhm otherOhm = new MockOhm("Other OHM", "OHM2", OHM_DECIMALS);
        vm.mockCall(
            address(inventory),
            abi.encodeCall(IBurnerLoansInventory.ohm, ()),
            abi.encode(address(otherOhm))
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InventoryOhmMismatch.selector,
                address(ohm),
                address(otherOhm)
            )
        );
        burnerLoans.setInventory(address(inventory));
    }

    // enable
    // given no Burner Loans Inventory has been bound
    //  when admin enables Burner Loans
    //   then it reverts
    function test_givenNoInventory_enableReverts() public {
        BurnerLoansHarness unbound = new BurnerLoansHarness(
            kernel,
            IERC20(address(ohm)),
            depositManager,
            backingOracle
        );
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(unbound));

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidInventory.selector, address(0))
        );
        unbound.enable("");
    }

    function _deployEnabledInventory(
        address facility_
    ) internal returns (BurnerLoansInventory replacement_) {
        replacement_ = new BurnerLoansInventory(kernel, IERC20(address(ohm)), facility_);
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement_));
        replacement_.setConfigurator(address(burnerLoansConfig));
        replacement_.enable("");
        vm.stopPrank();
    }
}
