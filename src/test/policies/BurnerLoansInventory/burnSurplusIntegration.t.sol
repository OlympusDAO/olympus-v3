// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant)

// Interfaces

import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts

import {BurnerLoansInventoryModularTest} from "./fixtures/BurnerLoansInventoryModularTest.sol";
import {toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";

contract BurnerLoansInventoryBurnSurplusIntegrationTest is BurnerLoansInventoryModularTest {
    error BurnUnavailable();

    function setUp() public override {
        super.setUp();
        _supplyInventory(_recipient, 50e9);
    }

    // Scenarios: BLINV-BURN-SURPLUS-P02.
    function test_givenRepaymentBurnFailed_whenSurplusBurned_thenProviderIdleRemainsBacked()
        public
        givenDebtBearingPosition
    {
        vm.mockCallRevert(
            address(_kernel.getModuleForKeycode(toKeycode("MINTR"))),
            abi.encodeWithSelector(MINTRv1.burnOhm.selector),
            abi.encodeWithSelector(BurnUnavailable.selector)
        );
        vm.roll(block.number + 1);
        vm.startPrank(_borrower);
        assertTrue(_ohm.approve(address(_core), 100e9), "Borrower approves full repayment");
        (uint128 principal, uint256 health) = _debt.repay(address(_asset), 100e9, _borrower);
        vm.stopPrank();
        assertEq(principal, 0, "Full repayment clears borrower principal despite burn failure");
        assertEq(health, type(uint256).max, "Debt-free position reports maximum health");
        // Supply 50, draw 100: 50 supplied + 50 minted. Repay 100: retain 50, burn the other 50.
        assertEq(_inventory.suppliedIdleOhm(), 50e9, "Repayment restores provider funding");
        assertEq(_inventory.surplusOhm(), 50e9, "Failed burn is recoverable surplus");
        vm.clearMockedCalls();
        uint256 supplyBefore = _ohm.totalSupply();
        vm.expectEmit(false, false, false, true, address(_inventory));
        emit IBurnerLoansInventory.SurplusBurned(50e9);
        _inventory.burnSurplus();
        assertEq(_ohm.totalSupply(), supplyBefore - 50e9, "Only failed minted principal is burned");
        assertEq(_ohm.balanceOf(address(_inventory)), 50e9, "Provider idle stays backed");
        assertEq(_inventory.providerClaimOhm(_recipient), 50e9, "Provider claim is not burned");
        assertEq(_inventory.surplusOhm(), 0, "No surplus remains");
        assertEq(_inventory.activePrincipalOhm(), 0, "Inventory principal remains zero");
    }

    function _burnAndAssert(address caller_) internal {
        _ohm.mint(address(_inventory), 1e9);
        uint256 beforeSupply = _ohm.totalSupply();
        vm.expectEmit(false, false, false, true, address(_inventory));
        emit IBurnerLoansInventory.SurplusBurned(1e9);
        vm.prank(caller_);
        _inventory.burnSurplus();
        // 51 OHM held - 50 OHM provider idle = 1 OHM burned.
        assertEq(_ohm.totalSupply(), beforeSupply - 1e9, "Surplus burned exactly once");
        assertEq(_ohm.balanceOf(address(_inventory)), 50e9, "Provider idle remains backed");
        assertEq(_inventory.suppliedIdleOhm(), 50e9, "Idle accounting unchanged");
        assertEq(_inventory.suppliedOhm(), 50e9, "Provider obligations unchanged");
        assertEq(_inventory.providerClaimOhm(_recipient), 50e9, "Provider claim unchanged");
        assertEq(_inventory.activePrincipalOhm(), 0, "Principal unchanged");
    }

    // Scenarios: BLINV-BURN-SURPLUS-A02.
    function test_givenSelectedConfigWithoutAdmin_whenSurplusBurned_thenIdleRemainsBacked() public {
        assertFalse(
            _roles.hasRole(_inventoryConfigurator, ADMIN_ROLE),
            "Config has no ADMIN grant"
        );
        _burnAndAssert(_inventoryConfigurator);
    }

    // Scenarios: BLINV-BURN-SURPLUS-A04.
    function test_givenSelectedConfigWithAdmin_whenSurplusBurned_thenBurnedOnce() public {
        _rolesAdmin.grantRole(ADMIN_ROLE, _inventoryConfigurator);
        _burnAndAssert(_inventoryConfigurator);
    }

    function test_whenCallerIsNeitherConfigNorAdmin_reverts(address caller_) public {
        _ohm.mint(address(_inventory), 1e9);
        vm.assume(caller_ != _inventoryConfigurator);
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _expectNotAuthorised();
        vm.prank(caller_);
        _inventory.burnSurplus();
        assertEq(_ohm.balanceOf(address(_inventory)), 51e9, "Unauthorized caller cannot burn");
        assertEq(_inventory.suppliedOhm(), 50e9, "Unauthorized caller cannot change claims");
    }

    function test_givenConfiguratorReplaced_whenPreviousConfigBurns_reverts() public {
        _inventory.setConfigOperator(address(0xC0FFEE));
        _expectNotAuthorised();
        vm.prank(_inventoryConfigurator);
        _inventory.burnSurplus();
    }

    function test_givenDisabledInventory_whenAdminBurnsSurplus_reverts() public {
        _ohm.mint(address(_inventory), 1e9);
        _disableInventory();
        _expectNotEnabled();
        _inventory.burnSurplus();
        assertEq(_ohm.balanceOf(address(_inventory)), 51e9, "Disabled burn preserves surplus");
        assertEq(_inventory.suppliedIdleOhm(), 50e9, "Disabled burn preserves idle funding");
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant)
