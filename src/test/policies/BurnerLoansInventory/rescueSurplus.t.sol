// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventoryRescueSurplusTest is BurnerLoansInventoryTest {
    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DEFAULT_CAP);
    }

    // rescueSurplus
    // [X] given a direct donation, it transfers only surplus and preserves supplied accounting
    function test_givenDonation_rescuesOnlySurplus(uint128 donation_) public {
        donation_ = uint128(bound(donation_, 1, type(uint128).max - 100e9));
        _supply(100e9);
        ohm.mint(address(inventory), donation_);
        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.SurplusRescued(donation_);
        vm.prank(admin);
        inventory.rescueSurplus();
        assertEq(ohm.balanceOf(address(trsry)), donation_, "treasury balance");
        assertEq(inventory.suppliedIdleOhm(), 100e9, "idle unchanged");
        assertEq(inventory.suppliedOhm(), 100e9, "claim unchanged");
        _assertInventoryInvariant();
    }

    // rescueSurplus
    // [X] given no surplus, it is a no-op
    function test_givenNoSurplus_noOp() public {
        _supply(100e9);
        vm.prank(admin);
        inventory.rescueSurplus();
        assertEq(ohm.balanceOf(address(trsry)), 0, "treasury unchanged");
        assertEq(inventory.suppliedIdleOhm(), 100e9, "idle unchanged");
        assertEq(inventory.suppliedOhm(), 100e9, "claim unchanged");
        _assertInventoryInvariant();
    }

    // rescueSurplus
    // [X] given the trusted OHM transfer fails, the surplus remains in Burner Loans Inventory
    function test_givenTransferFailure_revertsWithoutChangingSurplus() public {
        ohm.mint(address(inventory), 25e9);
        bytes memory failure = bytes("transfer failed");
        vm.mockCallRevert(
            address(ohm),
            abi.encodeWithSelector(ERC20.transfer.selector, address(trsry), 25e9),
            failure
        );

        vm.expectRevert(bytes("TRANSFER_FAILED"));
        vm.prank(admin);
        inventory.rescueSurplus();

        assertEq(inventory.surplusOhm(), 25e9, "surplus preserved");
        assertEq(ohm.balanceOf(address(trsry)), 0, "treasury unchanged");
        _assertInventoryInvariant();
    }

    // rescueSurplus
    // rescueSurplus
    // [X] given a caller without OCG admin authority, it reverts
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        inventory.rescueSurplus();
    }

    // rescueSurplus
    // [X] given Burner Loans Inventory is globally disabled, surplus rescue is blocked
    function test_givenGloballyDisabled_reverts(uint128 donation_) public {
        donation_ = uint128(bound(donation_, 1, type(uint128).max));
        ohm.mint(address(inventory), donation_);
        vm.prank(emergency);
        inventory.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(admin);
        inventory.rescueSurplus();

        assertEq(inventory.surplusOhm(), donation_, "surplus unchanged");
        assertEq(ohm.balanceOf(address(trsry)), 0, "treasury unchanged");
    }
}
