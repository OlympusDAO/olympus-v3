// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventorySyncMintApprovalTest is BurnerLoansInventoryTest {
    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DEFAULT_CAP);
    }

    // syncMintApproval
    // [X] given a conservative deficit, the Burner Loans admin restores exact desired approval
    function test_givenConservativeDeficit_restoresDesiredApproval(uint128 deficit_) public {
        deficit_ = uint128(bound(deficit_, 1, DEFAULT_CAP));
        vm.prank(address(inventory));
        mintr.decreaseMintApproval(address(inventory), deficit_);
        vm.prank(burnerLoansAdmin);
        uint256 approval = inventory.syncMintApproval();
        assertEq(approval, DEFAULT_CAP, "returned approval");
        _assertInventoryInvariant();
    }

    // syncMintApproval
    // [X] given approval already equals desired, it emits and preserves the exact value
    function test_givenApprovalEqualToDesired_isIdempotent() public {
        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.MintApprovalSynchronized(DEFAULT_CAP);
        vm.prank(burnerLoansAdmin);
        uint256 approval = inventory.syncMintApproval();

        assertEq(approval, DEFAULT_CAP, "returned approval");
        _assertInventoryInvariant();
    }

    // syncMintApproval
    // [X] given unsafe external over-approval, it reduces approval to desired
    function test_givenExternalOverApproval_reducesToDesired(uint128 excess_) public {
        excess_ = uint128(bound(excess_, 1, type(uint128).max - DEFAULT_CAP));
        vm.prank(address(inventory));
        mintr.increaseMintApproval(address(inventory), excess_);

        vm.prank(burnerLoansAdmin);
        uint256 approval = inventory.syncMintApproval();

        assertEq(approval, DEFAULT_CAP, "returned approval");
        _assertInventoryInvariant();
    }

    // syncMintApproval
    // [X] given a conservative deficit, admin reconciliation restores the deficit
    function test_givenApprovalDeficit_restoresDeficit() public {
        _draw(100e9);
        vm.prank(address(inventory));
        mintr.decreaseMintApproval(address(inventory), 40e9);
        vm.prank(address(facility));
        inventory.recordDefault(40e9);
        vm.prank(burnerLoansAdmin);
        uint256 approval = inventory.syncMintApproval();

        assertEq(approval, inventory.desiredMintApproval(), "approval synchronized");
        _assertInventoryInvariant();
    }

    // syncMintApproval
    // [X] given a restoration was deferred, the Burner Loans admin restores capacity
    function test_givenDeferredDefaultRestoration_restoresDesiredApproval() public {
        _draw(100e9);
        vm.prank(address(inventory));
        mintr.decreaseMintApproval(address(inventory), 40e9);

        assertEq(
            inventory.desiredMintApproval() - mintr.mintApproval(address(inventory)),
            40e9,
            "pre-sync deficit"
        );
        vm.prank(burnerLoansAdmin);
        uint256 approval = inventory.syncMintApproval();

        assertEq(approval, inventory.desiredMintApproval(), "approval synchronized");
        _assertInventoryInvariant();
    }

    // syncMintApproval
    // [X] given Burner Loans Inventory is globally disabled, admin reconciliation is blocked
    function test_givenGloballyDisabled_reverts(uint128 deficit_) public {
        deficit_ = uint128(bound(deficit_, 1, DEFAULT_CAP));
        vm.prank(address(inventory));
        mintr.decreaseMintApproval(address(inventory), deficit_);
        vm.prank(emergency);
        inventory.disable("");

        uint256 approvalBefore = mintr.mintApproval(address(inventory));

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(burnerLoansAdmin);
        inventory.syncMintApproval();

        assertEq(mintr.mintApproval(address(inventory)), approvalBefore, "approval unchanged");
    }

    // syncMintApproval
    // [X] given an unrelated caller, it reverts with the Burner Loans admin role
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BURNER_LOANS_ADMIN_ROLE)
        );
        vm.prank(caller_);
        inventory.syncMintApproval();
    }

    // syncMintApproval
    // [X] given supplied OHM reduces desired approval, synchronization uses the reduced target
    function test_givenSuppliedOhm_synchronizesToReducedDesiredApproval(uint128 supplied_) public {
        supplied_ = uint128(bound(supplied_, 1, DEFAULT_CAP));
        _supply(supplied_);
        vm.prank(address(inventory));
        mintr.increaseMintApproval(address(inventory), supplied_);

        vm.prank(burnerLoansAdmin);
        uint256 approval = inventory.syncMintApproval();

        assertEq(approval, DEFAULT_CAP - supplied_, "supplied-adjusted approval");
        _assertInventoryInvariant();
    }
}
