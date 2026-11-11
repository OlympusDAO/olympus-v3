// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast)

// Interfaces

import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts

import {BurnerLoansInventoryModularTest} from "./fixtures/BurnerLoansInventoryModularTest.sol";
import {toKeycode} from "src/Kernel.sol";

contract BurnerLoansInventoryRescueSurplusIntegrationTest is BurnerLoansInventoryModularTest {
    function setUp() public override {
        super.setUp();
        _supplyInventory(_recipient, 50e9);
        _ohm.mint(address(_inventory), 1e9);
    }

    function _rescueAndAssert(address caller_) internal {
        address treasury = address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
        uint256 beforeBalance = _ohm.balanceOf(treasury);
        vm.expectEmit(false, false, false, true, address(_inventory));
        emit IBurnerLoansInventory.SurplusRescued(1e9);
        vm.prank(caller_);
        _inventory.rescueSurplus();
        // 51 OHM held - 50 OHM provider idle = 1 OHM rescued. Claims are not spent.
        assertEq(_ohm.balanceOf(treasury), beforeBalance + 1e9, "Only donated surplus is rescued");
        assertEq(_ohm.balanceOf(address(_inventory)), 50e9, "Provider idle remains backed");
        assertEq(_inventory.suppliedIdleOhm(), 50e9, "Idle accounting unchanged");
        assertEq(_inventory.suppliedOhm(), 50e9, "Provider obligations unchanged");
        assertEq(_inventory.providerClaimOhm(_recipient), 50e9, "Provider claim unchanged");
        assertEq(_inventory.activePrincipalOhm(), 0, "Principal unchanged");
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-L02.
    function test_givenActiveEnabledInventory_whenSurplusRescued_thenIdleRemainsBacked() public {
        _rescueAndAssert(address(this));
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-L01.
    function test_givenActiveDisabledInventory_whenSurplusRescued_thenIdleRemainsBacked() public {
        _disableInventory();
        _rescueAndAssert(address(this));
        assertFalse(_inventory.isEnabled(), "Rescue does not re-enable Inventory");
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-L03.
    function test_givenInactiveDisabledInventory_whenSurplusRescued_reverts() public {
        _disableInventory();
        _setPolicyActive(address(_inventory), false);
        _expectInventoryNotActive();
        _inventory.rescueSurplus();
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-P02.
    function test_givenInactiveEnabledInventory_whenSurplusRescued_reverts() public {
        _setPolicyActive(address(_inventory), false);
        _expectInventoryNotActive();
        _inventory.rescueSurplus();
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-A02.
    function test_givenSelectedConfigWithoutAdmin_whenSurplusRescued_thenIdleRemainsBacked()
        public
    {
        assertFalse(
            _roles.hasRole(_inventoryConfigurator, ADMIN_ROLE),
            "Config has no ADMIN grant"
        );
        _rescueAndAssert(_inventoryConfigurator);
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-A03.
    function test_givenDisabledInventory_whenSelectedConfigRescues_thenIdleRemainsBacked() public {
        _disableInventory();
        _rescueAndAssert(_inventoryConfigurator);
        assertFalse(_inventory.isEnabled(), "Config rescue does not re-enable Inventory");
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-A04.
    function test_givenSelectedConfigWithAdmin_whenSurplusRescued_thenTransferredOnce() public {
        _rolesAdmin.grantRole(ADMIN_ROLE, _inventoryConfigurator);
        _rescueAndAssert(_inventoryConfigurator);
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-A01.
    function test_whenCallerIsNeitherConfigNorAdmin_reverts(address caller_) public {
        vm.assume(caller_ != _inventoryConfigurator);
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _expectNotAuthorised();
        vm.prank(caller_);
        _inventory.rescueSurplus();
        assertEq(_ohm.balanceOf(address(_inventory)), 51e9, "Unauthorized caller cannot rescue");
        assertEq(_inventory.suppliedOhm(), 50e9, "Unauthorized caller cannot change claims");
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-A05.
    function test_givenConfiguratorReplaced_whenPreviousConfigRescues_reverts() public {
        _inventory.setConfigOperator(address(0xC0FFEE));
        _expectNotAuthorised();
        vm.prank(_inventoryConfigurator);
        _inventory.rescueSurplus();
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-A06.
    function test_givenConfiguratorCleared_whenZeroAddressRescues_reverts() public {
        _inventory.setConfigOperator(address(0));
        _expectNotAuthorised();
        vm.prank(address(0));
        _inventory.rescueSurplus();
    }

    error TransferUnavailable();

    function test_givenDonation_rescuesOnlySurplus(uint128 donation_) public {
        donation_ = uint128(bound(donation_, 1, type(uint128).max));
        _ohm.mint(address(_inventory), donation_);
        address treasury = address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
        uint256 beforeBalance = _ohm.balanceOf(treasury);
        // Fixture holds 50e9 provider idle and 1e9 donation; the extra donation adds to surplus.
        uint256 expected = uint256(donation_) + 1e9;
        vm.expectEmit(false, false, false, true, address(_inventory));
        emit IBurnerLoansInventory.SurplusRescued(expected);
        _inventory.rescueSurplus();
        assertEq(_ohm.balanceOf(treasury), beforeBalance + expected, "Entire donation rescued");
        assertEq(_ohm.balanceOf(address(_inventory)), 50e9, "Provider backing preserved");
        assertEq(_inventory.suppliedOhm(), 50e9, "Provider claims preserved");
        assertEq(_inventory.suppliedIdleOhm(), 50e9, "Idle accounting preserved");
    }

    function test_givenNoSurplus_noOp() public {
        _inventory.burnSurplus();
        vm.recordLogs();
        _inventory.rescueSurplus();
        assertEq(vm.getRecordedLogs().length, 0, "No events when surplus is zero");
        assertEq(_ohm.balanceOf(address(_inventory)), 50e9, "Provider backing untouched");
        assertEq(_inventory.suppliedIdleOhm(), 50e9, "Idle accounting untouched");
        assertEq(_inventory.suppliedOhm(), 50e9, "Provider claims untouched");
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-D02.
    function test_givenTransferFailure_revertsWithoutChangingSurplus() public {
        address treasury = address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
        uint256 beforeBalance = _ohm.balanceOf(treasury);
        vm.mockCallRevert(
            address(_ohm),
            abi.encodeCall(_ohm.transfer, (treasury, 1e9)),
            abi.encodeWithSelector(TransferUnavailable.selector)
        );
        vm.expectRevert(TransferUnavailable.selector);
        _inventory.rescueSurplus();
        assertEq(_inventory.surplusOhm(), 1e9, "Failed transfer preserves surplus");
        assertEq(
            _ohm.balanceOf(treasury),
            beforeBalance,
            "Failed transfer leaves Treasury unchanged"
        );
        assertEq(_inventory.suppliedIdleOhm(), 50e9, "Failed transfer preserves idle");
        assertEq(_inventory.suppliedOhm(), 50e9, "Failed transfer preserves claims");
    }

    function test_givenDisabledInventory_whenDonationRescued_thenFundsRecovered(
        uint128 donation_
    ) public {
        donation_ = uint128(bound(donation_, 1, type(uint128).max));
        _ohm.mint(address(_inventory), donation_);
        _disableInventory();
        address treasury = address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
        uint256 beforeBalance = _ohm.balanceOf(treasury);
        _inventory.rescueSurplus();
        assertEq(
            _ohm.balanceOf(treasury),
            beforeBalance + uint256(donation_) + 1e9,
            "Paused rescue recovers donations"
        );
        assertEq(_inventory.suppliedIdleOhm(), 50e9, "Paused rescue protects provider funding");
        assertEq(_inventory.suppliedOhm(), 50e9, "Paused rescue preserves claims");
        assertFalse(_inventory.isEnabled(), "Paused rescue leaves Inventory disabled");
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast)
