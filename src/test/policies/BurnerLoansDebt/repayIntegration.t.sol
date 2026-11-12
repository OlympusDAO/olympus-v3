// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {MockBackingOracle} from "src/test/mocks/MockBackingOracle.sol";
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
        uint128 quotedDebt = _debt.previewRepay(address(_asset), 100e9, _borrower);
        assertEq(quotedDebt, 0, "Quote closes only the target debt");
        vm.prank(payer);
        uint128 debt = _debt.repay(address(_asset), 100e9, _borrower);
        assertEq(debt, quotedDebt, "Repayment matches quoted debt");
        assertEq(
            _lens.positionHealthFactor(address(_asset), 2000e6, debt),
            type(uint256).max,
            "Separate debt-free health read"
        );
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
        uint128 quotedDebt = _debt.previewRepay(address(_asset), 50e9, _borrower);
        // Remaining backing=50 OHM * USD 1 * 1.25 = USD 62.5.
        // Collateral USD 2000 / USD 62.5 = 32 WAD health.
        assertEq(quotedDebt, 50e9, "Independent remaining target debt");
        vm.prank(_recipient);
        uint128 debt = _debt.repay(address(_asset), 50e9, _borrower);
        assertEq(debt, quotedDebt, "Execution matches quoted debt");
        assertEq(
            _lens.positionHealthFactor(address(_asset), 2000e6, debt),
            32e18,
            "Separate independent remaining health"
        );
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
        uint128 q = _debt.previewRepay(address(_asset), 50e9, _borrower);
        assertEq(_stateDigest(_recipient), beforeQuote, "Real repayment quote is read only");
        // Remaining backing=50*1.25=62.5 USD; health=2000/62.5=32 WAD.
        assertEq(q, 50e9, "Independent remaining debt quote");
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Repaid(_recipient, address(_asset), _borrower, 50e9, 50e9);
        vm.prank(_recipient);
        uint128 remaining = _debt.repay(address(_asset), 50e9, _borrower);
        assertEq(remaining, 50e9, "Independent remaining debt");
        assertEq(
            _lens.positionHealthFactor(address(_asset), 2000e6, remaining),
            32e18,
            "Separate independent health read"
        );
        assertEq(_ohm.balanceOf(_recipient), 0, "Unrelated payer funds repayment");
        assertEq(_ohm.balanceOf(_borrower), 100e9, "Borrower wallet unchanged");
        assertEq(_position().collateral, 2000e6, "Collateral retained");
        assertEq(_inventory.activePrincipalOhm(), 50e9, "Funding ledger reconciled");
    }

    // Scenarios: BLDEBT-REPAY-D11.
    function test_givenBackingPaused_whenFullyRepaid_thenDebtCloses() public {
        _openRealDebt(2000e6, 100e9);
        vm.roll(block.number + 1);
        _fundRepayer(_borrower, 100e9);
        MockBackingOracle(_risk.backingOracle()).setEnabled(false);
        uint128 quotedDebt = _debt.previewRepay(address(_asset), 100e9, _borrower);
        assertEq(quotedDebt, 0, "full repayment preview clears debt during backing outage");
        vm.prank(_borrower);
        uint128 remaining = _debt.repay(address(_asset), 100e9, _borrower);
        assertEq(remaining, 0, "full repayment clears debt during backing outage");
        _assertMarketTotals(address(_asset), 0, 2000e6, 0);
    }

    // Scenarios: BLDEBT-REPAY-P02, BLDEBT-REPAY-D04.
    function test_givenStalePrices_whenPartialRepaymentExecuted() public {
        _openRealDebt(2000e6, 100e9);
        vm.roll(block.number + 1);
        _fundRepayer(_recipient, 50e9);
        vm.warp(vm.getBlockTimestamp() + 8 hours + 1);
        uint48 maturity = _position().maturity;
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Repaid(_recipient, address(_asset), _borrower, 50e9, 50e9);
        vm.prank(_recipient);
        uint128 remaining = _debt.repay(address(_asset), 50e9, _borrower);
        assertEq(remaining, 50e9, "Independent remaining principal despite oracle outage");
        assertEq(_ohm.balanceOf(_recipient), 0, "Unrelated payer supplies exact repayment");
        assertEq(
            _ohm.allowance(_recipient, address(_core)),
            0,
            "Repayment consumes exact allowance"
        );
        assertEq(_ohm.balanceOf(_borrower), 100e9, "Borrower wallet is unchanged");
        assertEq(_position().principalDue, 50e9, "Stale prices do not block debt reduction");
        assertEq(_position().maturity, maturity, "Repayment does not extend maturity");
        assertEq(_inventory.activePrincipalOhm(), 50e9, "Inventory principal reconciles");
        _assertMarketTotals(address(_asset), 50e9, 2000e6, 1);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        _lens.positionHealthFactor(address(_asset), 2000e6, 50e9);
        assertEq(_position().principalDue, 50e9, "Separate failed health read preserves repayment");
    }

    // Scenarios: BLDEBT-REPAY-P02, BLDEBT-REPAY-D04.
    function test_givenStalePrices_whenPartialRepaymentQuoted() public {
        _openRealDebt(2000e6, 100e9);
        vm.roll(block.number + 1);
        vm.warp(vm.getBlockTimestamp() + 8 hours + 1);
        bytes32 beforeQuote = _stateDigest(_recipient);
        vm.prank(_recipient);
        uint128 remaining = _debt.previewRepay(address(_asset), 50e9, _borrower);
        assertEq(remaining, 50e9, "Independent principal quote despite oracle outage");
        assertEq(
            _stateDigest(_recipient),
            beforeQuote,
            "Stale-price preview is read only and unfunded"
        );
    }

    // Scenarios: BLDEBT-REPAY-D10.
    function test_givenPausedBacking_whenPartialRepaymentExecuted() public {
        _openRealDebt(2000e6, 100e9);
        vm.roll(block.number + 1);
        _fundRepayer(_recipient, 50e9);
        MockBackingOracle(_risk.backingOracle()).setEnabled(false);
        vm.prank(_recipient);
        uint128 remaining = _debt.repay(address(_asset), 50e9, _borrower);
        assertEq(remaining, 50e9, "Independent remaining principal despite oracle outage");
        assertEq(_ohm.balanceOf(_recipient), 0, "Backing outage permits exact OHM collection");
        assertEq(_inventory.activePrincipalOhm(), 50e9, "Inventory principal reduced once");
        _assertMarketTotals(address(_asset), 50e9, 2000e6, 1);
    }

    // Scenarios: BLDEBT-REPAY-D10.
    function test_givenPausedBacking_whenPartialRepaymentQuoted() public {
        _openRealDebt(2000e6, 100e9);
        vm.roll(block.number + 1);
        MockBackingOracle(_risk.backingOracle()).setEnabled(false);
        bytes32 beforeQuote = _stateDigest(_recipient);
        vm.prank(_recipient);
        uint128 remaining = _debt.previewRepay(address(_asset), 50e9, _borrower);
        assertEq(remaining, 50e9, "Independent principal quote despite oracle outage");
        assertEq(
            _stateDigest(_recipient),
            beforeQuote,
            "Backing outage quote is read only and unfunded"
        );
    }

    // Scenarios: BLDEBT-REPAY-P05.
    function test_givenPartialRepayment_whenReturnDataInspected() public {
        _openRealDebt(2000e6, 100e9);
        vm.roll(block.number + 1);
        _fundRepayer(_recipient, 50e9);
        vm.prank(_recipient);
        (bool quoted, bytes memory quote) = address(_debt).staticcall(
            abi.encodeCall(_debt.previewRepay, (address(_asset), uint128(50e9), _borrower))
        );
        assertTrue(quoted, "Partial repayment quote succeeds");
        assertEq(quote.length, 32, "Preview returns one principal word without health");
        assertEq(abi.decode(quote, (uint128)), 50e9, "Independent partial principal quote");
        vm.prank(_recipient);
        (bool repaid, bytes memory result) = address(_debt).call(
            abi.encodeCall(_debt.repay, (address(_asset), uint128(50e9), _borrower))
        );
        assertTrue(repaid, "Partial repayment succeeds");
        assertEq(result.length, 32, "Repayment returns one principal word without health");
        assertEq(abi.decode(result, (uint128)), 50e9, "Canonical remaining principal returned");
        assertEq(_ohm.balanceOf(_recipient), 0, "Scalar return accompanies exact payer debit");
        _assertMarketTotals(address(_asset), 50e9, 2000e6, 1);
    }

    // Scenarios: BLDEBT-REPAY-P06.
    function test_givenFullRepayment_whenReturnDataInspected() public {
        _openRealDebt(2000e6, 100e9);
        vm.roll(block.number + 1);
        _fundRepayer(_recipient, 100e9);
        MockBackingOracle(_risk.backingOracle()).setEnabled(false);
        vm.prank(_recipient);
        (bool quoted, bytes memory quote) = address(_debt).staticcall(
            abi.encodeCall(_debt.previewRepay, (address(_asset), uint128(100e9), _borrower))
        );
        assertTrue(quoted, "Full repayment quote succeeds during outage");
        assertEq(quote.length, 32, "Full preview returns principal without health sentinel");
        assertEq(abi.decode(quote, (uint128)), 0, "Full repayment quote clears principal");
        vm.prank(_recipient);
        (bool repaid, bytes memory result) = address(_debt).call(
            abi.encodeCall(_debt.repay, (address(_asset), uint128(100e9), _borrower))
        );
        assertTrue(repaid, "Full repayment succeeds during outage");
        assertEq(result.length, 32, "Full repayment returns principal without health sentinel");
        assertEq(abi.decode(result, (uint128)), 0, "Canonical zero principal returned");
        assertEq(_ohm.balanceOf(_recipient), 0, "Full repayment consumes exact payer funds");
        _assertMarketTotals(address(_asset), 0, 2000e6, 0);
    }

    // Scenarios: BLDEBT-REPAY-N04.
    function test_givenRealUnhealthyPosition_whenPartiallyRepaid() public {
        _openRealDebt(2000e6, 100e9);
        vm.roll(block.number + 1);
        _fundRepayer(_recipient, 50e9);
        _price.setPrice(address(_asset), 0.01e18);
        // Collateral: 2000 * USD 0.01 = USD 20 (18 decimals).
        // Required backing before: 100 OHM * USD 1 * 1.25 = USD 125.
        // Health before: floor(20e18 * 1e18 / 125e18) = 0.16e18.
        assertEq(
            _lens.positionHealthFactor(address(_asset), 2000e6, 100e9),
            0.16e18,
            "Independent initial unhealthy position"
        );
        uint128 quoted = _debt.previewRepay(address(_asset), 50e9, _borrower);
        vm.prank(_recipient);
        uint128 remaining = _debt.repay(address(_asset), 50e9, _borrower);
        assertEq(quoted, 50e9, "Unhealthy principal quote is independent of health");
        assertEq(remaining, 50e9, "Helpful repayment need not cure the position");
        // Required backing after: 50 OHM * USD 1 * 1.25 = USD 62.5.
        // Health after: floor(20e18 * 1e18 / 62.5e18) = 0.32e18, still below 1e18.
        assertEq(
            _lens.positionHealthFactor(address(_asset), 2000e6, remaining),
            0.32e18,
            "Separate health improves but remains unhealthy"
        );
        assertEq(_ohm.balanceOf(_recipient), 0, "Unrelated payer supplies exactly 50 OHM");
        _assertMarketTotals(address(_asset), 50e9, 2000e6, 1);
    }

    // Scenarios: BLDEBT-REPAY-D16.
    function test_givenOperationalCacheFailure_whenPartiallyRepaid() public {
        _openRealDebt(2000e6, 100e9);
        address cache = address(_installPriceCache());
        vm.roll(block.number + 1);
        _fundRepayer(_recipient, 50e9);
        vm.mockCallRevert(
            cache,
            bytes(""),
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector)
        );
        vm.expectCall(
            cache,
            abi.encodeWithSelector(IPriceCache.cachePriceIfNecessary.selector),
            uint64(0)
        );
        vm.expectCall(
            cache,
            abi.encodeWithSelector(IPriceCache.getCachedPrice.selector),
            uint64(0)
        );
        bytes32 beforeQuote = _stateDigest(_recipient);
        uint128 quoted = _debt.previewRepay(address(_asset), 50e9, _borrower);
        assertEq(quoted, 50e9, "Cache failure does not block principal quote");
        assertEq(_stateDigest(_recipient), beforeQuote, "Cache-independent quote is read only");
        vm.prank(_recipient);
        uint128 remaining = _debt.repay(address(_asset), 50e9, _borrower);
        assertEq(remaining, 50e9, "Cache failure does not block repayment");
        assertEq(_inventory.activePrincipalOhm(), 50e9, "Inventory principal reduced once");
        assertEq(_ohm.balanceOf(_recipient), 0, "Cache outage permits exact OHM collection");
        _assertMarketTotals(address(_asset), 50e9, 2000e6, 1);
    }

    // Scenarios: BLDEBT-REPAY-D17.
    function test_givenBackingReadFailure_whenPartiallyRepaid() public {
        _openRealDebt(2000e6, 100e9);
        vm.roll(block.number + 1);
        _fundRepayer(_recipient, 50e9);
        address oracle = _risk.backingOracle();
        vm.mockCallRevert(
            oracle,
            abi.encodeWithSelector(IBackingOracle.backing.selector),
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector)
        );
        vm.expectCall(oracle, abi.encodeWithSelector(IBackingOracle.backing.selector), uint64(0));
        bytes32 beforeQuote = _stateDigest(_recipient);
        uint128 quoted = _debt.previewRepay(address(_asset), 50e9, _borrower);
        assertEq(quoted, 50e9, "Backing read failure does not block principal quote");
        assertEq(_stateDigest(_recipient), beforeQuote, "Backing-independent quote is read only");
        vm.prank(_recipient);
        uint128 remaining = _debt.repay(address(_asset), 50e9, _borrower);
        assertEq(remaining, 50e9, "Backing read failure does not block repayment");
        assertEq(_inventory.activePrincipalOhm(), 50e9, "Inventory principal reduced once");
        assertEq(_ohm.balanceOf(_recipient), 0, "Backing failure permits exact OHM collection");
        _assertMarketTotals(address(_asset), 50e9, 2000e6, 1);
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unsafe-typecast, unused-return)
