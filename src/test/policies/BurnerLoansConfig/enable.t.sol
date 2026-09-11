// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigEnableTest is BurnerLoansTest {
    function test_givenNoFacility_reverts() public {
        BurnerLoansConfig unlinkedConfig = new BurnerLoansConfig(kernel, IERC20(address(ohm)));
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(unlinkedConfig));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(0)
            )
        );
        unlinkedConfig.enable("");
        vm.stopPrank();
    }

    function test_givenFacilityDisabled_enables() public {
        vm.startPrank(admin);
        burnerLoansConfig.disable("");
        burnerLoans.disable("");
        burnerLoansConfig.enable("");
        vm.stopPrank();

        assertTrue(burnerLoansConfig.isEnabled(), "Config enabled");
        assertFalse(burnerLoans.isEnabled(), "Burner Loans remains disabled");
    }

    function test_givenInventoryDisabledButActive_enables() public {
        vm.startPrank(admin);
        burnerLoansConfig.disable("");
        inventory.disable("");
        burnerLoansConfig.enable("");
        vm.stopPrank();

        assertTrue(burnerLoansConfig.isEnabled(), "Config enabled");
    }

    function test_givenInventoryInactive_reverts() public {
        vm.startPrank(admin);
        burnerLoansConfig.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(inventory));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidInventory.selector,
                address(inventory)
            )
        );
        burnerLoansConfig.enable("");
        vm.stopPrank();
    }

    function test_givenFacilityInactive_reverts() public {
        vm.startPrank(admin);
        burnerLoansConfig.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(burnerLoans)
            )
        );
        burnerLoansConfig.enable("");
        vm.stopPrank();
    }

    function test_givenFacilityReportsDifferentKernel_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.disable("");
        vm.mockCall(
            address(burnerLoans),
            abi.encodeWithSignature("kernel()"),
            abi.encode(makeAddr("otherKernel"))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(burnerLoans)
            )
        );
        vm.prank(admin);
        burnerLoansConfig.enable("");
    }

    function test_givenInventoryReportsDifferentKernel_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.disable("");
        vm.mockCall(
            address(inventory),
            abi.encodeWithSignature("kernel()"),
            abi.encode(makeAddr("otherKernel"))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidInventory.selector,
                address(inventory)
            )
        );
        vm.prank(admin);
        burnerLoansConfig.enable("");
    }

    function test_givenFacilityConfiguratorMismatch_reverts() public {
        BurnerLoansConfig replacement = _deployReplacementConfig();
        vm.startPrank(admin);
        burnerLoansConfig.disable("");
        burnerLoans.disable("");
        burnerLoans.setConfigurator(address(replacement));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(burnerLoans)
            )
        );
        burnerLoansConfig.enable("");
        vm.stopPrank();
    }

    function test_givenInventoryConfiguratorMismatch_reverts() public {
        BurnerLoansConfig replacement = _deployReplacementConfig();
        vm.startPrank(admin);
        burnerLoansConfig.disable("");
        inventory.disable("");
        inventory.setConfigurator(address(replacement));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidInventory.selector,
                address(inventory)
            )
        );
        burnerLoansConfig.enable("");
        vm.stopPrank();
    }

    function test_givenNoInventory_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.disable("");
        vm.mockCall(
            address(burnerLoans),
            abi.encodeCall(IBurnerLoansView.inventory, ()),
            abi.encode(address(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidInventory.selector,
                address(0)
            )
        );
        vm.prank(admin);
        burnerLoansConfig.enable("");
    }

    function test_givenInventoryFacilityMismatch_reverts(address reportedFacility_) public {
        vm.assume(reportedFacility_ != address(burnerLoans));
        vm.mockCall(
            address(inventory),
            abi.encodeCall(IBurnerLoansInventory.facility, ()),
            abi.encode(reportedFacility_)
        );
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidInventory.selector,
                address(inventory)
            )
        );
        vm.prank(admin);
        burnerLoansConfig.enable("");
    }

    function _deployReplacementConfig() internal returns (BurnerLoansConfig replacement_) {
        replacement_ = new BurnerLoansConfig(kernel, IERC20(address(ohm)));
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(replacement_));
        vm.prank(admin);
        replacement_.setFacility(address(burnerLoans));
    }
}
