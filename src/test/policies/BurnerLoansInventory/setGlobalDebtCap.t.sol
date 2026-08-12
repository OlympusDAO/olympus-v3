// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventorySetGlobalDebtCapTest is BurnerLoansInventoryTest {
    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DEFAULT_CAP);
    }

    // setGlobalDebtCap
    // [X] given an authorized Config and higher cap, it updates cap and approval exactly
    function test_givenConfig_setsCapAndApproval(uint128 increase_) public {
        increase_ = uint128(bound(increase_, 1, type(uint128).max - DEFAULT_CAP));
        uint128 newCap = DEFAULT_CAP + increase_;
        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.GlobalDebtCapSet(newCap);
        vm.prank(address(config));
        inventory.setGlobalDebtCap(newCap);
        assertEq(inventory.globalDebtCapOhm(), newCap, "cap");
        assertEq(mintr.mintApproval(address(inventory)), newCap, "approval");
        _assertInventoryInvariant();
    }

    // setGlobalDebtCap
    // [X] given the same cap, it preserves synchronized accounting
    function test_givenEqualCap_preservesAccounting() public {
        vm.prank(address(config));
        inventory.setGlobalDebtCap(DEFAULT_CAP);

        assertEq(inventory.globalDebtCapOhm(), DEFAULT_CAP, "cap");
        assertEq(mintr.mintApproval(address(inventory)), DEFAULT_CAP, "approval");
        _assertInventoryInvariant();
    }

    // setGlobalDebtCap
    // [X] given a lower cap above active principal, it reduces approval to the new desired amount
    function test_givenLowerCap_reducesApproval(uint128 decrease_) public {
        decrease_ = uint128(bound(decrease_, 1, DEFAULT_CAP));
        uint128 newCap = DEFAULT_CAP - decrease_;
        vm.prank(address(config));
        inventory.setGlobalDebtCap(newCap);

        assertEq(inventory.globalDebtCapOhm(), newCap, "cap");
        assertEq(mintr.mintApproval(address(inventory)), newCap, "approval");
        _assertInventoryInvariant();
    }

    // setGlobalDebtCap
    // [X] given no active principal, a zero cap succeeds
    function test_givenZeroCap_succeeds() public {
        vm.prank(address(config));
        inventory.setGlobalDebtCap(0);

        assertEq(inventory.globalDebtCapOhm(), 0, "cap");
        assertEq(mintr.mintApproval(address(inventory)), 0, "approval");
        _assertInventoryInvariant();
    }

    // setGlobalDebtCap
    // [X] given active principal, the exact active-principal floor succeeds
    function test_givenExactActivePrincipalFloor_succeeds() public {
        _draw(100e9);

        vm.prank(address(config));
        inventory.setGlobalDebtCap(100e9);

        assertEq(inventory.globalDebtCapOhm(), 100e9, "cap");
        assertEq(inventory.availableCapacity(), 0, "capacity");
        _assertInventoryInvariant();
    }

    // setGlobalDebtCap
    // [X] given active principal, one unit below it reverts without changing accounting
    function test_givenOneBelowActivePrincipal_reverts() public {
        _draw(100e9);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidCap.selector,
                100e9 - 1,
                100e9
            )
        );
        vm.prank(address(config));
        inventory.setGlobalDebtCap(100e9 - 1);

        assertEq(inventory.globalDebtCapOhm(), DEFAULT_CAP, "cap unchanged");
        _assertInventoryInvariant();
    }

    // setGlobalDebtCap
    // [X] given supplied idle exceeds the reduced cap, custody remains withdrawable but capacity is bounded
    function test_givenSuppliedIdleAboveCap_preservesCustodyAndBoundsCapacity() public {
        _supply(200e9);

        vm.prank(address(config));
        inventory.setGlobalDebtCap(100e9);

        assertEq(inventory.suppliedIdleOhm(), 200e9, "idle custody");
        assertEq(inventory.availableCapacity(), 100e9, "cap-bounded capacity");
        vm.prank(provider);
        inventory.withdraw(200e9, recipient);
        assertEq(ohm.balanceOf(recipient), 200e9, "withdrawn custody");
        _assertInventoryInvariant();
    }

    // setGlobalDebtCap
    // [X] given a capacity-restoring increase fails, the cap persists for later admin sync
    function test_givenIncreaseFailure_revertsAndRollsBack(uint128 increase) public {
        increase = uint128(bound(increase, 1, type(uint128).max - DEFAULT_CAP));
        bytes memory failure = abi.encodeWithSelector(MINTRv1.MINTR_NotApproved.selector);
        vm.mockCallRevert(
            address(mintr),
            abi.encodeCall(MINTRv1.increaseMintApproval, (address(inventory), increase)),
            failure
        );

        vm.expectRevert(failure);
        vm.prank(address(config));
        inventory.setGlobalDebtCap(DEFAULT_CAP + increase);

        assertEq(inventory.globalDebtCapOhm(), DEFAULT_CAP, "cap rolled back");
        _assertInventoryInvariant();
    }

    // setGlobalDebtCap
    // [X] given a required approval decrease fails, the cap change rolls back
    function test_givenDecreaseFailure_revertsAndRollsBack(uint128 decrease) public {
        decrease = uint128(bound(decrease, 1, DEFAULT_CAP));
        bytes memory failure = abi.encodeWithSelector(MINTRv1.MINTR_NotApproved.selector);
        vm.mockCallRevert(
            address(mintr),
            abi.encodeCall(MINTRv1.decreaseMintApproval, (address(inventory), decrease)),
            failure
        );

        vm.expectRevert(failure);
        vm.prank(address(config));
        inventory.setGlobalDebtCap(DEFAULT_CAP - decrease);

        assertEq(inventory.globalDebtCapOhm(), DEFAULT_CAP, "cap rolled back");
        _assertInventoryInvariant();
    }

    // setGlobalDebtCap
    // [X] given an unrelated caller, it reverts with the exact caller
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != address(config));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_Unauthorized.selector,
                caller_
            )
        );
        vm.prank(caller_);
        inventory.setGlobalDebtCap(DEFAULT_CAP);
    }

    // setGlobalDebtCap
    // [X] given Burner Loans Inventory is globally disabled, Config can still reconcile the cap
    function test_givenGloballyDisabled_setsCap(uint128 newCap_) public {
        vm.prank(emergency);
        inventory.disable("");

        vm.prank(address(config));
        inventory.setGlobalDebtCap(newCap_);

        assertEq(inventory.globalDebtCapOhm(), newCap_, "cap");
        assertEq(mintr.mintApproval(address(inventory)), newCap_, "approval");
    }
}
