// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {BurnerLoansDebtTest} from "src/test/policies/BurnerLoansDebt/BurnerLoansDebtTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

contract BurnerLoansDebtBorrowCallbacksTest is BurnerLoansDebtTest {
    // Scenarios: BLDEBT-BORROW-C11.
    function test_givenOhmDeliveryCallback_whenBorrowed_thenFeeAndFundingRollBack() public {
        ReentrantFeeToken token = _prepareOhmDeliveryCallback();

        token.setBubbleCallbackFailure(true);
        uint256 payerBalance = _asset.balanceOf(_borrower);
        bytes32 rollbackBefore = _stateDigest(_borrower);
        vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 7, address(0));
        assertEq(_asset.balanceOf(_borrower), payerBalance, "Earlier fee collection restored");
        assertEq(_asset.balanceOf(address(_payout)), 0, "No new custody receipt");
        assertEq(token.balanceOf(_borrower), 0, "Failed principal delivery restored");
        assertEq(_inventory.activePrincipalOhm(), 0, "Funding ledger restored");
        assertEq(_lens.getPosition(address(_asset), _borrower).debtOhm, 0, "FLOAN debt restored");
        assertEq(
            _stateDigest(_borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    function test_givenCaughtOhmDeliveryCallback_whenBorrowed_thenOnlyOuterOperationSucceeds()
        public
    {
        ReentrantFeeToken token = _prepareOhmDeliveryCallback();

        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 7, address(0));
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized nested borrow reaches Core guard"
        );
    }

    function _prepareOhmDeliveryCallback() internal returns (ReentrantFeeToken token) {
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 2000e6, _borrower);
        ReentrantFeeToken template = new ReentrantFeeToken();
        // Both mocks have the same inherited OZ ERC20 storage layout. Preserve the existing
        // OHM identity and its 9-decimal Core scale while adding transfer callback behavior.
        vm.etch(address(_ohm), address(template).code);
        token = ReentrantFeeToken(address(_ohm));
        _asset.mint(address(token), 7);
        vm.prank(address(token));
        _asset.approve(address(_core), 7);
        _authorizeOperator(address(token), type(uint48).max);
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(uint256(7), uint256(0))
        );
        token.setCallbackFrom(
            address(_inventory),
            address(_debt),
            abi.encodeCall(
                _debt.borrow,
                (address(_asset), 1, _borrower, _borrower, uint256(7), address(0))
            )
        );
        token.setCallbackPhases(true, false);
    }

    // Scenarios: BLDEBT-BORROW-C09.
    function test_givenFeeTokenCallback_whenBorrowed_thenMandatoryReceiptFailureRollsBack() public {
        ReentrantFeeToken token = _prepareFeeTokenCallback();

        token.setBubbleCallbackFailure(true);
        uint256 beforeBalance = token.balanceOf(_borrower);
        bytes32 rollbackBefore = _stateDigestFor(address(token), _borrower);
        vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
        vm.prank(_borrower);
        _debt.borrow(address(token), 100e9, _borrower, _borrower, 7, address(0));
        assertEq(token.balanceOf(_borrower), beforeBalance, "Fee payer funds restored");
        assertEq(token.balanceOf(address(_payout)), 0, "No fee receipt");
        assertEq(_inventory.activePrincipalOhm(), 0, "No funding exposure");
        assertEq(_lens.getPosition(address(token), _borrower).debtOhm, 0, "No new debt");
        assertEq(
            _stateDigestFor(address(token), _borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    function test_givenCaughtFeeTokenCallback_whenBorrowed_thenOnlyOuterOperationSucceeds() public {
        ReentrantFeeToken token = _prepareFeeTokenCallback();

        vm.prank(_borrower);
        _debt.borrow(address(token), 100e9, _borrower, _borrower, 7, address(0));
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized funded nested borrow reaches Core guard"
        );
    }

    function _prepareFeeTokenCallback() internal returns (ReentrantFeeToken token) {
        token = new ReentrantFeeToken();
        _price.setPrice(address(token), 1e18);
        _admit(address(token));
        token.mint(_borrower, 3000e18);
        token.mint(address(token), 7);
        vm.startPrank(_borrower);
        token.approve(address(_core), type(uint256).max);
        _core.setAuthorization(address(token), type(uint48).max);
        _collateral.depositCollateral(address(token), 2000e18, _borrower);
        vm.stopPrank();
        vm.prank(address(token));
        token.approve(address(_core), 7);
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(uint256(7), uint256(0))
        );
        token.setCallbackFrom(
            address(_core),
            address(_debt),
            abi.encodeCall(
                _debt.borrow,
                (address(token), 1, _borrower, _borrower, uint256(7), address(0))
            )
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
