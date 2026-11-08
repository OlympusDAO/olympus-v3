// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)

// Interfaces

import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts

import {BurnerLoansInventoryModularTest} from "./fixtures/BurnerLoansInventoryModularTest.sol";

import {toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";

import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.

contract BurnerLoansInventorySetGlobalDebtCapIntegrationTest is BurnerLoansInventoryModularTest {
    error ApprovalChangeFailed();
    uint128 internal constant _INITIAL_CAP = 100_000e9;
    MINTRv1 internal _mintr;

    function setUp() public override {
        super.setUp();
        _mintr = MINTRv1(address(_kernel.getModuleForKeycode(toKeycode("MINTR"))));
    }

    // Scenarios: BLINV-GLOBAL-CAP-A08, BLINV-GLOBAL-CAP-L06.
    function test_givenAdmin_setsCapAndApproval(uint128 increase_) public {
        increase_ = uint128(bound(increase_, 1, type(uint128).max - _INITIAL_CAP));
        uint128 newCap = _INITIAL_CAP + increase_;
        vm.expectEmit(false, false, false, true, address(_inventory));
        emit IBurnerLoansInventory.GlobalDebtCapSet(newCap);
        _inventory.setGlobalDebtCap(newCap);
        assertEq(_inventory.globalDebtCapOhm(), newCap, "cap");
        assertEq(_mintr.mintApproval(address(_inventory)), newCap, "approval");
        _assertInventoryInvariant();
    }

    function test_givenEqualCap_preservesAccounting() public {
        _inventory.setGlobalDebtCap(_INITIAL_CAP);

        assertEq(_inventory.globalDebtCapOhm(), _INITIAL_CAP, "cap");
        assertEq(_mintr.mintApproval(address(_inventory)), _INITIAL_CAP, "approval");
        _assertInventoryInvariant();
    }

    function test_givenLowerCap_reducesApproval(uint128 decrease_) public {
        decrease_ = uint128(bound(decrease_, 1, _INITIAL_CAP));
        uint128 newCap = _INITIAL_CAP - decrease_;
        _inventory.setGlobalDebtCap(newCap);

        assertEq(_inventory.globalDebtCapOhm(), newCap, "cap");
        assertEq(_mintr.mintApproval(address(_inventory)), newCap, "approval");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-GLOBAL-CAP-N03.
    function test_givenZeroCap_succeeds() public {
        _inventory.setGlobalDebtCap(0);

        assertEq(_inventory.globalDebtCapOhm(), 0, "cap");
        assertEq(_mintr.mintApproval(address(_inventory)), 0, "approval");
        _assertInventoryInvariant();
    }

    function test_givenExactActivePrincipalFloor_succeeds() public {
        vm.prank(address(_core));
        _inventory.draw(_borrower, 100e9);

        _inventory.setGlobalDebtCap(100e9);

        assertEq(_inventory.globalDebtCapOhm(), 100e9, "cap");
        assertEq(_inventory.availableCapacity(), 0, "capacity");
        _assertInventoryInvariant();
    }

    function test_givenOneBelowActivePrincipal_reverts() public {
        vm.prank(address(_core));
        _inventory.draw(_borrower, 100e9);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidCap.selector,
                100e9 - 1,
                100e9
            )
        );
        _inventory.setGlobalDebtCap(100e9 - 1);

        assertEq(_inventory.globalDebtCapOhm(), _INITIAL_CAP, "cap unchanged");
        _assertInventoryInvariant();
    }

    function test_givenSuppliedIdleAboveCap_preservesCustodyAndBoundsCapacity() public {
        _supplyInventory(_recipient, 200e9);

        _inventory.setGlobalDebtCap(100e9);

        assertEq(_inventory.suppliedIdleOhm(), 200e9, "idle custody");
        assertEq(_inventory.availableCapacity(), 100e9, "cap-bounded capacity");
        vm.prank(_recipient);
        _inventory.withdraw(200e9, _borrower);
        assertEq(_ohm.balanceOf(_borrower), 200e9, "withdrawn custody");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-GLOBAL-CAP-D01.
    function test_givenIncreaseFailure_revertsAndRollsBack(uint128 increase) public {
        increase = uint128(bound(increase, 1, type(uint128).max - _INITIAL_CAP));
        bytes memory failure = abi.encodeWithSelector(ApprovalChangeFailed.selector);
        vm.mockCallRevert(
            address(_mintr),
            abi.encodeCall(MINTRv1.increaseMintApproval, (address(_inventory), increase)),
            failure
        );

        vm.expectRevert(failure);
        _inventory.setGlobalDebtCap(_INITIAL_CAP + increase);

        assertEq(_inventory.globalDebtCapOhm(), _INITIAL_CAP, "cap rolled back");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-GLOBAL-CAP-D02.
    function test_givenDecreaseFailure_revertsAndRollsBack(uint128 decrease) public {
        decrease = uint128(bound(decrease, 1, _INITIAL_CAP));
        bytes memory failure = abi.encodeWithSelector(ApprovalChangeFailed.selector);
        vm.mockCallRevert(
            address(_mintr),
            abi.encodeCall(MINTRv1.decreaseMintApproval, (address(_inventory), decrease)),
            failure
        );

        vm.expectRevert(failure);
        _inventory.setGlobalDebtCap(_INITIAL_CAP - decrease);

        assertEq(_inventory.globalDebtCapOhm(), _INITIAL_CAP, "cap rolled back");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-GLOBAL-CAP-A01.
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _expectAdminRole();
        vm.prank(caller_);
        _inventory.setGlobalDebtCap(_INITIAL_CAP);
    }

    // Scenarios: BLINV-GLOBAL-CAP-A05.
    function test_givenGloballyDisabled_whenAdminSetsCap_reverts(uint128 newCap_) public {
        _disableInventory();
        _expectNotEnabled();
        _inventory.setGlobalDebtCap(newCap_);
        assertEq(_inventory.globalDebtCapOhm(), _INITIAL_CAP, "Paused call preserves cap");
        assertEq(
            _mintr.mintApproval(address(_inventory)),
            _INITIAL_CAP,
            "Paused call preserves approval"
        );
    }

    // Scenarios: BLINV-GLOBAL-CAP-L09.
    function test_givenInactiveDisabledInventory_whenAdminSetsCap_reverts() public {
        _disableInventory();
        _setPolicyActive(address(_inventory), false);
        _expectInventoryNotActive();
        _inventory.setGlobalDebtCap(1);
    }

    // Scenarios: BLINV-GLOBAL-CAP-P04.
    function test_givenInactiveEnabledInventory_whenAdminSetsCap_reverts() public {
        _setPolicyActive(address(_inventory), false);
        _expectInventoryNotActive();
        _inventory.setGlobalDebtCap(1);
    }

    function _assertInventoryInvariant() internal view {
        assertLe(
            _inventory.activePrincipalOhm(),
            _inventory.globalDebtCapOhm(),
            "Principal respects cap"
        );
        assertLe(
            _inventory.suppliedIdleOhm(),
            _inventory.suppliedOhm(),
            "Idle does not exceed claims"
        );
        assertLe(
            _inventory.suppliedIdleOhm(),
            _ohm.balanceOf(address(_inventory)),
            "Idle remains backed"
        );
    }

    // Scenarios: BLINV-GLOBAL-CAP-A02.
    function test_givenRecoveryConfigurator_whenGlobalDebtCapSet_reverts() public {
        _expectAdminRole();
        vm.prank(_inventoryConfigurator);
        _inventory.setGlobalDebtCap(1);
    }

    // Scenarios: BLINV-GLOBAL-CAP-D03.
    function test_givenCoreControllerReplaced_whenCapUpdated_thenInventoryAuthorityIndependent()
        public
    {
        _replaceCoreController();
        assertEq(
            _inventory.configOperator(),
            _inventoryConfigurator,
            "Inventory recovery selection unchanged"
        );
        _inventory.setGlobalDebtCap(1);
        assertEq(
            _inventory.globalDebtCapOhm(),
            1,
            "ADMIN cap control independent of Core configuration"
        );
    }

    // Scenarios: BLINV-GLOBAL-CAP-A06.
    function test_givenFeeReceiptCallback_whenCapRejectionCaught_succeeds() public {
        ReentrantFeeToken token = _prepareFeeReceiptCallback();
        token.setCallbackFrom(
            address(_core),
            address(_inventory),
            abi.encodeCall(_inventory.setGlobalDebtCap, (uint128(1)))
        );
        vm.prank(_borrower);
        _debt.borrow(address(token), 100e9, _borrower, _borrower, 7, address(0));
        _assertCoreCallbackCaught(token);
    }

    // Scenarios: BLINV-GLOBAL-CAP-A06.
    function test_givenFeeReceiptCallback_whenCapRejectionPropagates_reverts() public {
        ReentrantFeeToken token = _prepareFeeReceiptCallback();
        token.setCallbackFrom(
            address(_core),
            address(_inventory),
            abi.encodeCall(_inventory.setGlobalDebtCap, (uint128(1)))
        );
        token.setBubbleCallbackFailure(true);
        uint256 payerBalance = token.balanceOf(_borrower);
        vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
        vm.prank(_borrower);
        _debt.borrow(address(token), 100e9, _borrower, _borrower, 7, address(0));
        _assertCoreCallbackRolledBack(token, payerBalance);
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
