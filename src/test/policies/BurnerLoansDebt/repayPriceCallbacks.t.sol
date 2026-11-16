// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {BurnerLoansDebtPriceCallbackTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtPriceCallbackTest.sol";

// Fixed principal and callback amounts exercise the existing adversarial dependency setups.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

contract BurnerLoansDebtRepayPriceCallbacksTest is BurnerLoansDebtPriceCallbackTest {
    // Scenarios: BLDEBT-REPAY-C01.
    function test_givenAuthorizedBorrowCacheCallback_whenPartiallyRepaid() public {
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 0, address(0));
        vm.roll(block.number + 1);
        vm.prank(_borrower);
        _ohm.approve(address(_core), type(uint256).max);
        _cache.arm(
            address(_debt),
            abi.encodeCall(
                _debt.borrow,
                (address(_asset), 1, _borrower, address(_cache), uint256(0), address(0))
            ),
            true
        );
        _assertCacheUnusedRepayment(1);
    }

    // Scenarios: BLDEBT-REPAY-C05.
    function test_givenFullRepaymentCacheCallback_whenPartiallyRepaid() public {
        _prepareDebtAndCacheRepayer();
        _cache.arm(
            address(_debt),
            abi.encodeCall(_debt.repay, (address(_asset), 100e9, _borrower)),
            true
        );
        _assertCacheUnusedRepayment(1);
    }

    // Scenarios: BLDEBT-REPAY-C06.
    function test_givenPartialRepaymentCacheCallback_whenPartiallyRepaid() public {
        _prepareDebtAndCacheRepayer();
        _cache.arm(
            address(_debt),
            abi.encodeCall(_debt.repay, (address(_asset), 75e9, _borrower)),
            true
        );
        _assertCacheUnusedRepayment(50e9);
    }

    // Scenarios: BLDEBT-REPAY-C03.
    function test_givenCatchingUnauthorizedCacheCallback_whenPartiallyRepaid() public {
        _prepareDebtAndCacheRepayer();
        _armUnauthorizedBorrow(false);
        _assertCacheUnusedRepayment(1);
    }

    // Scenarios: BLDEBT-REPAY-C04.
    function test_givenPropagatingUnauthorizedCacheCallback_whenPartiallyRepaid() public {
        _prepareDebtAndCacheRepayer();
        _armUnauthorizedBorrow(true);
        _assertCacheUnusedRepayment(1);
    }

    function _assertCacheUnusedRepayment(uint128 amount_) internal {
        uint256 cacheCalls = _cache.cachePriceIfNecessaryCallCount();
        uint256 priceCalls = _cache.cachePriceCallCount();
        uint256 cacheFunds = _ohm.balanceOf(address(_cache));
        uint256 cacheAllowance = _ohm.allowance(address(_cache), address(_core));
        uint256 payerBalance = _ohm.balanceOf(_borrower);
        uint48 borrowBlock = _position().lastBorrowBlock;
        uint48 maturity = _position().maturity;
        bytes32 cachedPrices = _cachedPricesDigest();
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.refreshSnapshot.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_cache),
            abi.encodeWithSelector(IPriceCache.cachePriceIfNecessary.selector),
            uint64(0)
        );
        bytes32 beforeQuote = _priceStateDigest();
        uint128 quote = _debt.previewRepay(address(_asset), amount_, _borrower);
        assertEq(quote, 100e9 - amount_, "Independent principal quote");
        assertEq(
            _priceStateDigest(),
            beforeQuote,
            "Quote leaves armed callback and accounting unchanged"
        );
        vm.prank(_borrower);
        uint128 remaining = _debt.repay(address(_asset), amount_, _borrower);
        assertEq(remaining, 100e9 - amount_, "Only the outer repayment reduces principal");
        assertEq(_position().principalDue, remaining, "Position agrees with return");
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            remaining,
            "Market principal reconciles"
        );
        assertEq(_inventory.activePrincipalOhm(), remaining, "Inventory principal reconciles");
        assertEq(_position().collateral, 2000e6, "Collateral retained");
        assertEq(_position().maturity, maturity, "Maturity unchanged");
        assertEq(_position().lastBorrowBlock, borrowBlock, "No nested borrow changes latest block");
        assertEq(
            _ohm.balanceOf(_borrower),
            payerBalance - amount_,
            "Only outer payer funds are used"
        );
        assertEq(_ohm.balanceOf(address(_cache)), cacheFunds, "Nested payer funds remain unused");
        assertEq(
            _ohm.allowance(address(_cache), address(_core)),
            cacheAllowance,
            "Nested payer allowance unchanged"
        );
        assertEq(_cache.cachePriceIfNecessaryCallCount(), cacheCalls, "No cache refresh");
        assertEq(_cache.cachePriceCallCount(), priceCalls, "No cache price write");
        assertEq(_cache.rejection(), bytes(""), "No nested failure is attempted or caught");
        assertEq(_cachedPricesDigest(), cachedPrices, "Cache entries unchanged");
    }

    function _cachedPricesDigest() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _cache.getCachedPrice(address(_ohm), address(_asset)),
                    _cache.getCachedPrice(address(_asset), address(_ohm))
                )
            );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
