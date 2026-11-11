// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BL_DEBT_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansDebtTest} from "src/test/policies/BurnerLoansDebt/BurnerLoansDebtTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, unused-return)

abstract contract BurnerLoansDebtLifecycleTest is BurnerLoansDebtTest {
    bytes32 internal _initialAccounting;
    bytes32 internal constant _SETTLEMENT_ROLE = BL_DEBT_POLICY_ROLE;
    bytes4 internal constant _INTERFACE_ID = type(IBurnerLoansDebt).interfaceId;

    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(_borrower);
        _collateral.depositCollateral(address(_asset), 2000e6, _borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 100e6, address(0));
        vm.stopPrank();
        _initialAccounting = _stateDigest(_borrower);
    }

    function _assertLoansPreserved() internal view {
        assertEq(
            _stateDigest(_borrower),
            _initialAccounting,
            "Lifecycle preserves every accounting, custody, allowance and index component"
        );
        IBurnerLoansCore.Position memory position = _lens.getPosition(address(_asset), _borrower);
        assertEq(position.depositedCollateral, 2000e6, "Lifecycle preserves live collateral");
        assertEq(position.debtOhm, 100e9, "Lifecycle preserves live debt");
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Lifecycle preserves funding ledger");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            2000e6,
            "Lifecycle preserves DM operator liabilities"
        );
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            2000e6,
            "Lifecycle preserves actual custody"
        );
    }

    function _assertActivationRejected(uint48 last_) internal view {
        assertFalse(_debt.isEnabled(), "Failed activation leaves action disabled");
        assertEq(_debt.lastTransitionAt(), last_, "Failed activation preserves history");
        _assertLoansPreserved();
    }

    function _expectDependencyNotActive(address dependency_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                dependency_
            )
        );
    }

    function _assertActivationSucceeded() internal view {
        assertTrue(_debt.isEnabled(), "Restored dependency permits activation");
        assertEq(
            _debt.lastTransitionAt(),
            vm.getBlockTimestamp(),
            "Retry records exact current time"
        );
        _assertLoansPreserved();
    }

    function _grantReEnableCaller(address caller_, bool blAdmin_, bool overlap_) internal {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(blAdmin_ ? BURNER_LOANS_ADMIN_ROLE : ADMIN_ROLE, caller_);
        if (overlap_)
            _rolesAdmin.grantRole(blAdmin_ ? ADMIN_ROLE : BURNER_LOANS_ADMIN_ROLE, caller_);
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unused-return)
