// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BURNER_LOANS_INVENTORY_PROVIDER_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventorySupplyTest is BurnerLoansInventoryTest {
    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DEFAULT_CAP);
    }

    // supply
    // [X] given an authorized provider, it raises its claim and aggregate idle and reduces approval
    function test_givenProvider_updatesAccountingAndEmits(uint128 amount) public {
        amount = uint128(bound(amount, 1, type(uint128).max));
        ohm.mint(provider, amount);
        vm.startPrank(provider);
        ohm.approve(address(inventory), amount);
        vm.expectEmit(true, false, false, true, address(inventory));
        emit IBurnerLoansInventory.OhmSupplied(provider, amount, amount, amount);
        inventory.supply(amount);
        vm.stopPrank();
        assertEq(inventory.suppliedOhm(), amount, "claim");
        assertEq(inventory.providerClaimOhm(provider), amount, "provider claim");
        assertEq(inventory.suppliedIdleOhm(), amount, "idle");
        _assertInventoryInvariant();
    }

    // supply
    // [X] given zero amount, it reverts without changing accounting
    function test_givenZeroAmount_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAmount.selector);
        vm.prank(provider);
        inventory.supply(0);

        _assertInventoryInvariant();
    }

    // supply
    // [X] given Burner Loans Inventory is globally disabled, supply is blocked
    function test_givenGloballyDisabled_reverts() public {
        vm.prank(emergency);
        inventory.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(provider);
        inventory.supply(1);
    }

    // supply
    // [X] given a caller without the provider role, it reverts
    function test_givenCallerWithoutProviderRole_reverts(address caller_) public {
        vm.assume(caller_ != provider);
        vm.expectRevert(
            abi.encodeWithSelector(
                ROLESv1.ROLES_RequireRole.selector,
                BURNER_LOANS_INVENTORY_PROVIDER_ROLE
            )
        );
        vm.prank(caller_);
        inventory.supply(1);
    }

    // supply
    // [X] given the provider has not approved Burner Loans Inventory, SafeTransferLib reverts
    function test_givenMissingAllowance_reverts(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        ohm.mint(provider, amount_);
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        vm.prank(provider);
        inventory.supply(amount_);
    }

    // supply
    // [X] given the provider has insufficient OHM, SafeTransferLib reverts
    function test_givenMissingBalance_reverts(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        vm.prank(provider);
        ohm.approve(address(inventory), amount_);
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        vm.prank(provider);
        inventory.supply(amount_);
    }

    // supply
    // [X] given multiple providers, it records isolated claims and aggregate accounting
    function test_givenMultipleProviders_recordsSeparateClaims() public {
        address secondProvider = makeAddr("secondProvider");
        vm.prank(admin);
        rolesAdmin.grantRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, secondProvider);

        _supply(100e9);
        ohm.mint(secondProvider, 40e9);
        vm.startPrank(secondProvider);
        ohm.approve(address(inventory), 40e9);
        inventory.supply(40e9);
        vm.stopPrank();

        assertEq(inventory.providerClaimOhm(provider), 100e9, "first provider claim");
        assertEq(inventory.providerClaimOhm(secondProvider), 40e9, "second provider claim");
        assertEq(inventory.suppliedOhm(), 140e9, "aggregate claim");
        assertEq(inventory.suppliedIdleOhm(), 140e9, "aggregate idle");
        _assertInventoryInvariant();
    }
}
