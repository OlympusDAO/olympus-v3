// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansCollateralPriceCallbackTest} from "./fixtures/BurnerLoansCollateralPriceCallbackTest.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralDepositCollateralPriceCallbacksTest is
    BurnerLoansCollateralPriceCallbackTest
{
    // Scenarios: BLCOL-DEPOSIT-C01.
    function test_givenCacheFullyRepays_whenTopUpSettles_thenActualDebtFreeHealthReturned() public {
        _openDebt();
        _ohm.mint(address(_cache), 100e9);
        vm.prank(address(_cache));
        _ohm.approve(address(_core), 100e9);
        bytes32 beforeQuote = _accountingDigest(address(_asset));
        vm.prank(_borrower);
        (, , uint256 quotedHealth) = _collateral.previewDepositCollateral(
            address(_asset),
            1,
            _borrower
        );
        // 2000.000001 assets / 125 required assets = 16.000000008 WAD.
        assertEq(
            quotedHealth,
            16_000_000_008_000_000_000,
            "Read-only quote retains pre-callback principal"
        );
        assertEq(
            _accountingDigest(address(_asset)),
            beforeQuote,
            "Quote cannot run the mutating cache callback"
        );
        _cache.arm(
            address(_debt),
            abi.encodeCall(_debt.repay, (address(_asset), 100e9, _borrower)),
            true
        );
        vm.prank(_borrower);
        (uint128 credit, uint128 collateral, uint256 health) = _collateral.depositCollateral(
            address(_asset),
            1,
            _borrower
        );
        assertEq(credit, 1, "Only outer credit");
        assertEq(collateral, 2000e6 + 1, "Actual final collateral");
        assertEq(health, type(uint256).max, "Health reflects debt repaid by refresh callback");
        assertEq(_inventory.activePrincipalOhm(), 0, "Nested repayment reconciled");
        _assertDirectCollateral(2000e6 + 1);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).debtOhm,
            0,
            "Canonical principal reflects nested repayment"
        );
        assertEq(
            _ohm.balanceOf(address(_cache)),
            0,
            "Authorized callback funds the entire repayment"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-C03.
    function test_givenCaughtUnauthorizedCacheAction_whenDepositing_thenOneCredit() public {
        _openDebt();
        _armUnauthorized(false);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            2000e6 + 1,
            "Only outer top-up"
        );
        assertEq(
            _cache.rejection(),
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            "Exact caught auth failure"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-C04.
    function test_givenPropagatedUnauthorizedCacheAction_whenDepositing_thenRollback() public {
        _openDebt();
        _armUnauthorized(true);
        bytes32 beforeState = _accountingDigest(address(_asset));
        bytes32 beforeCache = keccak256(
            abi.encode(_cache.getCachedPrice(address(_ohm), address(_asset)))
        );
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            2000e6,
            "Failed refresh adds no collateral"
        );
        assertEq(
            _accountingDigest(address(_asset)),
            beforeState,
            "Nested and outer accounting fully restored"
        );
        assertEq(
            keccak256(abi.encode(_cache.getCachedPrice(address(_ohm), address(_asset)))),
            beforeCache,
            "Failed refresh restores cache observation"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
