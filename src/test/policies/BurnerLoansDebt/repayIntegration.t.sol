// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {BurnerLoansDebtIntegrationTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtIntegrationTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast, unused-return)

contract BurnerLoansDebtRepayIntegrationTest is BurnerLoansDebtIntegrationTest {
    // Scenarios: BLDEBT-REPAY-P03.
    function test_givenTwoBorrowers_whenOneFullyRepaid() public {
        _openRealDebt(2000e6, 100e9);
        _openRealDebtFor(_asset, _recipient, 2000e6, 100e9);
        bytes32 other = keccak256(abi.encode(_lens.getPosition(address(_asset), _recipient)));
        vm.roll(block.number + 1);
        address payer = makeAddr("thirdPartyPayer");
        _fundRepayer(payer, 100e9);
        vm.prank(payer);
        (uint128 quotedDebt, uint256 quotedHealth) = _debt.previewRepay(
            address(_asset),
            100e9,
            _borrower
        );
        assertEq(quotedDebt, 0, "Quote closes only the target debt");
        assertEq(quotedHealth, type(uint256).max, "Debt-free quote health");
        vm.prank(payer);
        (uint128 debt, uint256 health) = _debt.repay(address(_asset), 100e9, _borrower);
        assertEq(debt, quotedDebt, "Repayment matches quoted debt");
        assertEq(health, quotedHealth, "Repayment matches quoted health");
        assertEq(_ohm.balanceOf(payer), 0, "Exact third-party OHM debit");
        assertEq(_position().principalDue, 0, "Target debt cleared");
        assertEq(_position().maturity, 0, "Target episode cleared");
        assertEq(_position().collateral, 2000e6, "Target collateral retained");
        assertEq(
            keccak256(abi.encode(_lens.getPosition(address(_asset), _recipient))),
            other,
            "Other borrower completely unchanged"
        );
        _assertMarketTotals(address(_asset), 100e9, 4000e6, 1);
        assertEq(
            _lens.getActiveBorrowers(address(_asset))[0],
            _recipient,
            "Only the other debt borrower remains"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            100e9,
            "Inventory retains other borrower principal"
        );
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            4000e6,
            "Both collateral claims remain backed"
        );
    }

    // Scenarios: BLDEBT-REPAY-P04.
    function test_givenTwoMarkets_whenOnePartiallyRepaid() public {
        _openRealDebt(2000e6, 100e9);
        MockERC20 other = _admitSecondAsset();
        _openRealDebtFor(other, _borrower, 2000e6, 100e9);
        bytes32 otherPosition = keccak256(abi.encode(_lens.getPosition(address(other), _borrower)));
        bytes32 otherCustody = _custodyDigest(address(other));
        vm.roll(block.number + 1);
        _fundRepayer(_recipient, 50e9);
        vm.prank(_recipient);
        (uint128 quotedDebt, uint256 quotedHealth) = _debt.previewRepay(
            address(_asset),
            50e9,
            _borrower
        );
        // Remaining backing=50 OHM * USD 1 * 1.25 = USD 62.5.
        // Collateral USD 2000 / USD 62.5 = 32 WAD health.
        assertEq(quotedDebt, 50e9, "Independent remaining target debt");
        assertEq(quotedHealth, 32e18, "Independent remaining target health");
        vm.prank(_recipient);
        (uint128 debt, uint256 health) = _debt.repay(address(_asset), 50e9, _borrower);
        assertEq(debt, quotedDebt, "Execution matches quoted debt");
        assertEq(health, quotedHealth, "Execution matches quoted health");
        assertEq(_ohm.balanceOf(_recipient), 0, "Exact payer debit");
        assertEq(
            keccak256(abi.encode(_lens.getPosition(address(other), _borrower))),
            otherPosition,
            "Other market position unchanged"
        );
        assertEq(_custodyDigest(address(other)), otherCustody, "Other market custody unchanged");
        _assertMarketTotals(address(_asset), 50e9, 2000e6, 1);
        _assertMarketTotals(address(other), 100e9, 2000e6, 1);
        assertEq(
            _inventory.activePrincipalOhm(),
            150e9,
            "Global principal reconciles both markets"
        );
        assertEq(_asset.balanceOf(address(_depositManager)), 2000e6, "Target collateral retained");
        assertEq(other.balanceOf(address(_depositManager)), 2000e6, "Other collateral retained");
    }

    // Scenarios: BLDEBT-REPAY-P01.
    function test_givenRealRisk_whenUnrelatedPayerPartiallyRepays_thenIndependentHealth(
        uint8 priceDecimals_
    ) public {
        priceDecimals_ = uint8(bound(priceDecimals_, 6, 18));
        _price.setPriceDecimals(priceDecimals_);
        _price.setPrice(address(_asset), 10 ** priceDecimals_);
        _price.setPrice(address(_ohm), 10 ** priceDecimals_);
        _openRealDebt(2000e6, 100e9);
        vm.roll(block.number + 1);
        _fundRepayer(_recipient, 50e9);
        bytes32 beforeQuote = _stateDigest(_recipient);
        vm.prank(_recipient);
        (uint128 q, uint256 qh) = _debt.previewRepay(address(_asset), 50e9, _borrower);
        assertEq(_stateDigest(_recipient), beforeQuote, "Real repayment quote is read only");
        // Remaining backing=50*1.25=62.5 USD; health=2000/62.5=32 WAD.
        assertEq(q, 50e9, "Independent remaining debt quote");
        assertEq(qh, 32e18, "Independent health quote");
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Repaid(_recipient, address(_asset), _borrower, 50e9, 50e9);
        vm.prank(_recipient);
        (uint128 remaining, uint256 health) = _debt.repay(address(_asset), 50e9, _borrower);
        assertEq(remaining, 50e9, "Independent remaining debt");
        assertEq(health, 32e18, "Independent health");
        assertEq(_ohm.balanceOf(_recipient), 0, "Unrelated payer funds repayment");
        assertEq(_ohm.balanceOf(_borrower), 100e9, "Borrower wallet unchanged");
        assertEq(_position().collateral, 2000e6, "Collateral retained");
        assertEq(_inventory.activePrincipalOhm(), 50e9, "Funding ledger reconciled");
    }

    // Scenarios: BLDEBT-REPAY-P02, BLDEBT-REPAY-D04.
    function test_givenRealStalePrice_whenRepayQuotedOrExecuted_reverts() public {
        _openRealDebt(2000e6, 100e9);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 8 hours + 1);
        bytes32 state = _stateDigest(_borrower);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(_borrower);
        _debt.previewRepay(address(_asset), 1, _borrower);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(_borrower);
        _debt.repay(address(_asset), 1, _borrower);
        assertEq(
            _stateDigest(_borrower),
            state,
            "Real pricing failure restores all ledgers, custody and allowances"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unsafe-typecast, unused-return)
