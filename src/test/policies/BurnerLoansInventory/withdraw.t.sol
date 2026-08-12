// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {BURNER_LOANS_INVENTORY_PROVIDER_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

contract BurnerLoansInventoryWithdrawTest is BurnerLoansInventoryTest {
    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DEFAULT_CAP);
    }

    // withdraw
    // [X] given an idle claim, it reduces the claim and transfers exact OHM
    function test_givenIdleClaim_withdrawsExactAmount(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, 100e9));
        _supply(100e9);
        vm.expectEmit(true, false, false, true, address(inventory));
        emit IBurnerLoansInventory.OhmWithdrawn(
            provider,
            amount_,
            100e9 - amount_,
            100e9 - amount_
        );
        vm.prank(provider);
        inventory.withdraw(amount_, recipient);
        assertEq(inventory.suppliedOhm(), 100e9 - amount_, "claim");
        assertEq(inventory.providerClaimOhm(provider), 100e9 - amount_, "provider claim");
        assertEq(inventory.suppliedIdleOhm(), 100e9 - amount_, "idle");
        assertEq(ohm.balanceOf(recipient), amount_, "recipient balance");
        _assertInventoryInvariant();
    }

    // withdraw
    // [X] given the full idle claim, it clears the provider and aggregate claims
    function test_givenFullIdleClaim_withdrawsAll() public {
        _supply(100e9);
        vm.prank(provider);
        inventory.withdraw(100e9, recipient);

        assertEq(inventory.providerClaimOhm(provider), 0, "provider claim");
        assertEq(inventory.suppliedOhm(), 0, "aggregate claim");
        assertEq(inventory.suppliedIdleOhm(), 0, "idle");
        assertEq(ohm.balanceOf(recipient), 100e9, "recipient balance");
        _assertInventoryInvariant();
    }

    // withdraw
    // [X] given the trusted OHM transfer fails, claim, idle, and approval changes roll back
    function test_givenTransferFailure_revertsAndRollsBack(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, 100e9));
        _supply(100e9);
        bytes memory failure = bytes("transfer failed");
        vm.mockCallRevert(
            address(ohm),
            abi.encodeWithSelector(ERC20.transfer.selector, recipient, amount_),
            failure
        );

        vm.expectRevert(bytes("TRANSFER_FAILED"));
        vm.prank(provider);
        inventory.withdraw(amount_, recipient);

        assertEq(inventory.providerClaimOhm(provider), 100e9, "provider claim rolled back");
        assertEq(inventory.suppliedOhm(), 100e9, "aggregate claim rolled back");
        assertEq(inventory.suppliedIdleOhm(), 100e9, "idle rolled back");
        assertEq(ohm.balanceOf(recipient), 0, "recipient unchanged");
        _assertInventoryInvariant();
    }

    // withdraw
    // [X] given a valid idle claim, the provider exit remains available
    function test_givenValidIdleClaim_withdraws(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, 100e9));
        _supply(100e9);
        vm.prank(provider);
        inventory.withdraw(amount_, recipient);

        assertEq(ohm.balanceOf(recipient), amount_, "recipient balance");
        assertEq(
            mintr.mintApproval(address(inventory)),
            inventory.desiredMintApproval(),
            "approval synchronized"
        );
        _assertInventoryInvariant();
    }

    // withdraw
    // [X] given Burner Loans Inventory is globally disabled, the strict pause blocks the provider exit
    function test_givenGloballyDisabled_reverts() public {
        _supply(100e9);
        vm.prank(emergency);
        inventory.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(provider);
        inventory.withdraw(40e9, recipient);
    }

    // withdraw
    // [X] given another provider has a claim, the caller cannot withdraw that claim
    function test_givenAnotherProviderClaim_reverts() public {
        address secondProvider = makeAddr("secondProvider");
        vm.prank(admin);
        rolesAdmin.grantRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, secondProvider);
        _supply(100e9);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientClaim.selector,
                1,
                0
            )
        );
        vm.prank(secondProvider);
        inventory.withdraw(1, recipient);
    }

    // withdraw
    // [X] given the provider claim exceeds aggregate idle, it cannot withdraw unavailable OHM
    function test_givenAmountAboveIdle_reverts(uint128 excess_) public {
        excess_ = uint128(bound(excess_, 1, 60e9));
        uint128 amount = 40e9 + excess_;
        _supply(100e9);
        _draw(60e9);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientIdle.selector,
                amount,
                40e9
            )
        );
        vm.prank(provider);
        inventory.withdraw(amount, recipient);

        _assertInventoryInvariant();
    }

    // withdraw
    // [X] given zero amount, it reverts
    function test_givenZeroAmount_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAmount.selector);
        vm.prank(provider);
        inventory.withdraw(0, recipient);
    }

    // withdraw
    // [X] given a zero recipient, it reverts
    function test_givenZeroRecipient_reverts() public {
        _supply(1);
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAddress.selector);
        vm.prank(provider);
        inventory.withdraw(1, address(0));
    }

    // withdraw
    // [X] given a provider's role is revoked, its claim remains but access is suspended
    function test_givenProviderRoleRevoked_preservesClaimAndReverts() public {
        _supply(100e9);
        vm.prank(admin);
        rolesAdmin.revokeRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, provider);

        vm.expectRevert(
            abi.encodeWithSelector(
                ROLESv1.ROLES_RequireRole.selector,
                BURNER_LOANS_INVENTORY_PROVIDER_ROLE
            )
        );
        vm.prank(provider);
        inventory.withdraw(1, recipient);
        assertEq(inventory.providerClaimOhm(provider), 100e9, "provider claim preserved");
        assertEq(inventory.suppliedOhm(), 100e9, "aggregate claim preserved");
    }

    // withdraw
    // [X] given supplied idle still consumes all cap room, it does not restore approval above desired
    function test_givenIdleStillAtCap_capsApprovalRestoration() public {
        _supply(DEFAULT_CAP + 100e9);
        vm.prank(provider);
        inventory.withdraw(100e9, recipient);
        assertEq(inventory.desiredMintApproval(), 0, "desired approval");
        assertEq(mintr.mintApproval(address(inventory)), 0, "actual approval");
        _assertInventoryInvariant();
    }

    // withdraw
    // [X] given approval drifted above desired, the exit removes the unsafe excess
    function test_givenExternalOverApproval_reducesApprovalToDesired(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, 100e9));
        _supply(100e9);
        vm.prank(address(inventory));
        mintr.increaseMintApproval(address(inventory), type(uint256).max);

        vm.prank(provider);
        inventory.withdraw(amount_, recipient);

        assertEq(
            mintr.mintApproval(address(inventory)),
            inventory.desiredMintApproval(),
            "approval reduced to desired"
        );
        _assertInventoryInvariant();
    }
}
