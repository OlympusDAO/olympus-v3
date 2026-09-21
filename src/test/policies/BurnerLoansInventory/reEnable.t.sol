// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventoryReEnableTest is BurnerLoansInventoryTest {
    uint48 internal constant _DISABLED_AT = 1_000;

    function test_givenNeverEnabled_reverts() public {
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(admin);
        inventory.reEnable();
    }

    function test_givenAlreadyEnabled_reverts() public {
        _initializeAndEnable();

        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(burnerLoansAdmin);
        inventory.reEnable();
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        _initializeAndEnable();
        vm.prank(emergency);
        inventory.disable("");

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        inventory.reEnable();
    }

    function test_givenGracePeriodElapsed_reverts(uint48 elapsedAfterDeadline_) public {
        uint256 elapsedAfterDeadline = bound(elapsedAfterDeadline_, 1, 365 days);
        vm.warp(_DISABLED_AT);
        _initializeAndEnable();
        vm.prank(emergency);
        inventory.disable("");

        // deadline = disabled timestamp + the 7-day default grace period.
        uint48 deadline = _DISABLED_AT + BurnerLoansConstants.REENABLE_GRACE_PERIOD;
        vm.warp(uint256(deadline) + elapsedAfterDeadline);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(burnerLoansAdmin);
        inventory.reEnable();
    }

    function test_givenFacilityInactive_reverts() public {
        _initializeAndEnable();
        vm.prank(emergency);
        inventory.disable("");
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(facility));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidPolicy.selector,
                address(facility)
            )
        );
        vm.prank(admin);
        inventory.reEnable();
    }

    function test_givenConfiguratorInactive_reverts() public {
        _initializeAndEnable();
        vm.prank(emergency);
        inventory.disable("");
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(config));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidPolicy.selector,
                address(config)
            )
        );
        vm.prank(admin);
        inventory.reEnable();
    }

    function test_givenBurnerLoansAdminWithinGracePeriod_reEnables(uint32 elapsed_) public {
        uint256 elapsed = bound(elapsed_, 0, BurnerLoansConstants.REENABLE_GRACE_PERIOD);
        vm.warp(_DISABLED_AT);
        _initializeAndEnable();
        vm.prank(address(config));
        inventory.setGlobalDebtCap(DEFAULT_CAP);
        vm.prank(emergency);
        inventory.disable("");
        vm.warp(uint256(_DISABLED_AT) + elapsed);

        vm.prank(burnerLoansAdmin);
        inventory.reEnable();

        assertTrue(inventory.isEnabled(), "Inventory should be enabled");
        assertEq(uint256(inventory.lastTransitionAt()), block.timestamp, "last transition");
        assertEq(inventory.configurator(), address(config), "configurator should be preserved");
        assertEq(inventory.globalDebtCapOhm(), DEFAULT_CAP, "debt cap should be preserved");
    }

    function test_givenAdminAtGracePeriodDeadline_reEnables() public {
        vm.warp(_DISABLED_AT);
        _initializeAndEnable();
        vm.prank(emergency);
        inventory.disable("");
        vm.warp(uint256(_DISABLED_AT) + BurnerLoansConstants.REENABLE_GRACE_PERIOD);

        vm.prank(admin);
        inventory.reEnable();

        assertTrue(inventory.isEnabled(), "Inventory should be enabled at the deadline");
    }
}
