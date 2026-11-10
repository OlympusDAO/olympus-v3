// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {BL_DEBT_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansAuthorizationIntegrationTest} from "src/test/policies/BurnerLoansCore/authorizationLifecycleTest.sol";

contract BurnerLoansCoreBorrowAuthorizationTest is BurnerLoansAuthorizationIntegrationTest {
    // Scenarios: BLCORE-SETTLE-BORROW-N90.
    function test_givenExistingPrincipal_whenCanonicalDebtExceedsBound_reverts() public {
        _deposit(2000e6);
        _borrow(100e9);
        // 100e9 existing + 50e9 requested = 150e9 raw 9-decimal OHM.
        // The resulting principal exceeds this cap by exactly one raw OHM unit (1e-9 OHM).
        _acceptBounded(_boundedGrant(2, 0, 150e9 - 1, 0, 0));
        IBurnerLoansCore.AuthorizationContext memory original = _delegatedContext(2);
        IBurnerLoansCore.BorrowRequest memory request = IBurnerLoansCore.BorrowRequest(
            address(_asset),
            _borrower,
            _recipient,
            _recipient,
            50e9,
            _rawPosition().maturity,
            0,
            address(0),
            0
        );
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ResultOutsideGrant.selector);
        vm.prank(address(_debt));
        _core.settleBorrow(request, _recipient, original);
        assertEq(_ledger(), before, "Principal, Inventory and recipient delivery all roll back");
    }

    // Scenarios: BLCORE-SETTLE-BORROW-P90.
    function test_givenExistingPrincipal_whenCanonicalDebtEqualsBound() public {
        _deposit(2000e6);
        _borrow(100e9);
        _acceptBounded(_boundedGrant(2, 0, 150e9, 0, 0));
        IBurnerLoansCore.AuthorizationContext memory original = _delegatedContext(2);
        IBurnerLoansCore.BorrowRequest memory request = IBurnerLoansCore.BorrowRequest(
            address(_asset),
            _borrower,
            _recipient,
            _recipient,
            50e9,
            _rawPosition().maturity,
            0,
            address(0),
            0
        );
        uint256 recipientBefore = _ohm.balanceOf(_recipient);
        vm.prank(address(_debt));
        (uint128 debt, ) = _core.settleBorrow(request, _recipient, original);
        // 100e9 existing + 50e9 new = 150e9 raw 9-decimal OHM principal.
        assertEq(
            debt,
            150e9,
            "Borrow limit applies to resulting principal, not this call's amount"
        );
        assertEq(
            _ohm.balanceOf(_recipient) - recipientBefore,
            50e9,
            "Authorized recipient receives principal"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-P91.
    function test_givenUsedReusableGrant_whenBorrowedAgainAtCap() public {
        IBurnerLoansCore.AuthorizationContext memory original = _prepareUsedReusableGrant();
        bytes memory grant = abi.encode(_auth.getGrant(_borrower, _recipient));
        uint256 recipientBefore = _ohm.balanceOf(_recipient);
        uint128 debt = _borrowWithGrant(25e9, original);
        // 100e9 initial + 25e9 first use + 25e9 second use = the inclusive 150e9 cap.
        assertEq(debt, 150e9, "Repeated use reaches the resulting-principal cap exactly");
        assertEq(
            _ohm.balanceOf(_recipient) - recipientBefore,
            25e9,
            "Second use pays principal once"
        );
        assertEq(
            abi.encode(_auth.getGrant(_borrower, _recipient)),
            grant,
            "Successful reuse leaves the grant unchanged"
        );
        assertEq(
            _auth.captureAuthorization(_borrower, _recipient, 2),
            original.grantContext,
            "Original stamp remains valid after both uses"
        );
        assertEq(
            _auth.pairEpochs(_borrower, _recipient),
            1,
            "Using a grant consumes no acceptance epochs"
        );
        assertEq(_auth.accountEpochs(_borrower), 0, "Using a grant changes no account epoch");
    }

    // Scenarios: BLCORE-SETTLE-BORROW-N91.
    function test_givenReusableGrantAtCap_whenBorrowedAgain_reverts() public {
        IBurnerLoansCore.AuthorizationContext memory original = _prepareUsedReusableGrant();
        _borrowWithGrant(25e9, original);
        bytes32 before = _ledger();
        bytes memory grant = abi.encode(_auth.getGrant(_borrower, _recipient));
        IBurnerLoansCore.BorrowRequest memory request = _reusableBorrowRequest(1);
        // 150e9 current principal + 1 raw OHM unit exceeds the same 150e9 cap.
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ResultOutsideGrant.selector);
        vm.prank(address(_debt));
        _core.settleBorrow(request, _recipient, original);
        assertEq(
            _ledger(),
            before,
            "Over-cap reuse rolls back funding, delivery and canonical principal"
        );
        assertEq(
            abi.encode(_auth.getGrant(_borrower, _recipient)),
            grant,
            "Rejected reuse preserves the whole grant"
        );
        assertEq(
            _auth.captureAuthorization(_borrower, _recipient, 2),
            original.grantContext,
            "Rejected reuse preserves original authority"
        );
        assertEq(
            _auth.pairEpochs(_borrower, _recipient),
            1,
            "Rejected reuse consumes no pair epoch"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-A91.
    function test_givenUsedReusableGrant_whenUnrelatedPublicCallerBorrows_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != address(0) && caller_ != _borrower && caller_ != _recipient);
        IBurnerLoansCore.AuthorizationContext memory original = _prepareUsedReusableGrant();
        bytes32 before = _ledger();
        bytes memory grant = abi.encode(_auth.getGrant(_borrower, _recipient));
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(caller_);
        _debt.borrow(address(_asset), 1, _borrower, _recipient, type(uint256).max, address(0));
        assertEq(_ledger(), before, "Unrelated caller moves no principal or custody");
        assertEq(
            abi.encode(_auth.getGrant(_borrower, _recipient)),
            grant,
            "Unrelated caller cannot alter the operator's grant"
        );
        assertEq(
            _auth.captureAuthorization(_borrower, _recipient, 2),
            original.grantContext,
            "Genuine authority remains unchanged"
        );
        assertEq(
            _auth.pairEpochs(_borrower, caller_),
            0,
            "Third party acquires no delegated authority"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-A92.
    function test_givenUsedReusableGrant_whenZeroPublicCallerBorrows_reverts() public {
        IBurnerLoansCore.AuthorizationContext memory original = _prepareUsedReusableGrant();
        bytes32 before = _ledger();
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidIdentity.selector);
        vm.prank(address(0));
        _debt.borrow(address(_asset), 1, _borrower, _recipient, type(uint256).max, address(0));
        assertEq(_ledger(), before, "Zero caller moves no principal or custody");
        assertEq(
            _auth.captureAuthorization(_borrower, _recipient, 2),
            original.grantContext,
            "Zero caller cannot invalidate genuine authority"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-A93.
    function test_givenUsedReusableGrant_whenUnadmittedCallerCopiesStamp_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != _borrower && caller_ != _recipient);
        vm.assume(!_roles.hasRole(caller_, BL_DEBT_POLICY_ROLE));
        IBurnerLoansCore.AuthorizationContext memory original = _prepareUsedReusableGrant();
        IBurnerLoansCore.BorrowRequest memory request = _reusableBorrowRequest(1);
        bytes32 before = _ledger();
        // The original snapshot is public, but its possession cannot replace the settlement role.
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE)
        );
        vm.prank(caller_);
        _core.settleBorrow(request, _recipient, original);
        assertEq(
            _ledger(),
            before,
            "Copied public authority moves no funds for an unadmitted caller"
        );
        assertEq(
            _auth.captureAuthorization(_borrower, _recipient, 2),
            original.grantContext,
            "Copied snapshot leaves the real grant live"
        );
        assertEq(
            _auth.pairEpochs(_borrower, _recipient),
            1,
            "Unadmitted settlement consumes no epoch"
        );
    }

    function _prepareUsedReusableGrant()
        private
        returns (IBurnerLoansCore.AuthorizationContext memory original)
    {
        _deposit(2000e6);
        _borrow(100e9);
        _acceptBounded(_boundedGrant(2, 0, 150e9, 0, 0));
        assertTrue(
            _auth.getGrant(_borrower, _recipient).multiple,
            "Fixture uses reusable authority"
        );
        original = _delegatedContext(2);
        uint256 recipientBefore = _ohm.balanceOf(_recipient);
        uint128 debt = _borrowWithGrant(25e9, original);
        // 100e9 existing + 25e9 first delegated use = 125e9 raw 9-decimal OHM principal.
        assertEq(debt, 125e9, "Initial legitimate use completes before the scenario");
        assertEq(
            _ohm.balanceOf(_recipient) - recipientBefore,
            25e9,
            "Initial use pays principal once"
        );
    }

    function _reusableBorrowRequest(
        uint128 amount_
    ) private view returns (IBurnerLoansCore.BorrowRequest memory) {
        return
            IBurnerLoansCore.BorrowRequest(
                address(_asset),
                _borrower,
                _recipient,
                _recipient,
                amount_,
                _rawPosition().maturity,
                0,
                address(0),
                0
            );
    }

    function _borrowWithGrant(
        uint128 amount_,
        IBurnerLoansCore.AuthorizationContext memory original_
    ) private returns (uint128) {
        IBurnerLoansCore.BorrowRequest memory request = _reusableBorrowRequest(amount_);
        vm.prank(address(_debt));
        (uint128 debt, ) = _core.settleBorrow(request, _recipient, original_);
        return debt;
    }
}
// forge-lint: disable-end(unused-return)
