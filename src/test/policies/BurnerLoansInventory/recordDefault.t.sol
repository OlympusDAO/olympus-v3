// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventoryRecordDefaultTest is BurnerLoansInventoryTest {
    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DEFAULT_CAP);
        _supply(100e9);
        _draw(100e9);
    }

    // recordDefault
    // [X] given a partial default, it reduces active principal without impairing the provider claim
    function test_givenPartialDefault_preservesClaim(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, 100e9 - 1));
        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.PrincipalDefaulted(amount_);
        vm.prank(address(facility));
        inventory.recordDefault(amount_);
        assertEq(inventory.activePrincipalOhm(), 100e9 - amount_, "active principal");
        assertEq(inventory.suppliedOhm(), 100e9, "claim");
        _assertInventoryInvariant();
    }

    // recordDefault
    // [X] given the full principal defaults, it clears active principal and preserves the claim
    function test_givenFullDefault_clearsPrincipalAndPreservesClaim() public {
        vm.prank(address(facility));
        inventory.recordDefault(100e9);

        assertEq(inventory.activePrincipalOhm(), 0, "active principal");
        assertEq(inventory.suppliedOhm(), 100e9, "claim");
        assertEq(inventory.suppliedIdleOhm(), 0, "idle");
        _assertInventoryInvariant();
    }

    // recordDefault
    // [X] given a provider claim survives one default, repayment from remaining principal later
    //     replenishes that unchanged claim before any OHM is burned
    function test_givenDefaultThenLaterRepayment_replenishesSurvivingClaim(
        uint128 defaultAmount_
    ) public {
        defaultAmount_ = uint128(bound(defaultAmount_, 1, 100e9 - 1));
        uint128 repaymentAmount = 100e9 - defaultAmount_;
        vm.prank(address(facility));
        inventory.recordDefault(defaultAmount_);
        _transferRepayment(repaymentAmount);

        vm.prank(address(facility));
        inventory.settleRepayment(repaymentAmount);

        assertEq(inventory.activePrincipalOhm(), 0, "remaining principal repaid");
        assertEq(inventory.suppliedOhm(), 100e9, "claim survives default");
        assertEq(inventory.suppliedIdleOhm(), repaymentAmount, "later repayment replenishes claim");
        assertEq(ohm.balanceOf(address(inventory)), repaymentAmount, "replenished OHM retained");
        _assertInventoryInvariant();
    }

    // recordDefault
    // [X] given principal has already fully defaulted, a repeated default reverts specifically
    function test_givenRepeatedDefault_reverts() public {
        vm.prank(address(facility));
        inventory.recordDefault(100e9);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_ExcessivePrincipal.selector,
                1,
                0
            )
        );
        vm.prank(address(facility));
        inventory.recordDefault(1);

        _assertInventoryInvariant();
    }

    // recordDefault
    // [X] given zero amount, it reverts without changing accounting
    function test_givenZeroAmount_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAmount.selector);
        vm.prank(address(facility));
        inventory.recordDefault(0);

        assertEq(inventory.activePrincipalOhm(), 100e9, "active principal unchanged");
        _assertInventoryInvariant();
    }

    // recordDefault
    // [X] given amount exceeds active principal, it reverts without changing accounting
    function test_givenAmountAbovePrincipal_reverts(uint128 excess_) public {
        excess_ = uint128(bound(excess_, 1, type(uint128).max - 100e9));
        uint128 amount = 100e9 + excess_;
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_ExcessivePrincipal.selector,
                amount,
                100e9
            )
        );
        vm.prank(address(facility));
        inventory.recordDefault(amount);

        assertEq(inventory.activePrincipalOhm(), 100e9, "active principal unchanged");
        _assertInventoryInvariant();
    }

    // recordDefault
    // [X] given an unrelated caller, it rejects default accounting
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != address(facility));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_Unauthorized.selector,
                caller_
            )
        );
        vm.prank(caller_);
        inventory.recordDefault(1e9);
    }

    // recordDefault
    // [X] given approval restoration fails, default completes and emits diagnostic failure data
    function test_givenApprovalRestorationFailure_defersToAdminWithoutReverting(
        uint128 amount_
    ) public {
        amount_ = uint128(bound(amount_, 1, 100e9));
        bytes memory failure = abi.encodeWithSelector(MINTRv1.MINTR_NotApproved.selector);
        vm.mockCallRevert(
            address(mintr),
            abi.encodeCall(MINTRv1.increaseMintApproval, (address(inventory), amount_)),
            failure
        );

        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.ApprovalRestorationFailed(amount_, failure);
        vm.prank(address(facility));
        inventory.recordDefault(amount_);

        assertEq(inventory.activePrincipalOhm(), 100e9 - amount_, "default recorded");
        assertEq(
            inventory.desiredMintApproval() - mintr.mintApproval(address(inventory)),
            amount_,
            "approval deficit"
        );
        _assertInventoryInvariant();
    }

    // recordDefault
    // [X] given Burner Loans Inventory is globally disabled, the strict pause blocks default accounting
    function test_givenGloballyDisabled_reverts() public {
        vm.prank(emergency);
        inventory.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(facility));
        inventory.recordDefault(40e9);
    }

    // recordDefault
    // [X] given another active policy in the same Kernel, exact facility authentication rejects it
    function test_givenActiveSameKernelNonFacility_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_Unauthorized.selector,
                address(config)
            )
        );
        vm.prank(address(config));
        inventory.recordDefault(1e9);
    }
}
