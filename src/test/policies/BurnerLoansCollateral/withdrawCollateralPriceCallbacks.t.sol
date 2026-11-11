// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansCollateralPriceCallbackTest} from "./fixtures/BurnerLoansCollateralPriceCallbackTest.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralWithdrawCollateralPriceCallbacksTest is
    BurnerLoansCollateralPriceCallbackTest
{
    // Scenarios: BLCOL-WITHDRAW-C01.
    function test_givenCacheWithdraws_whenOuterNowExceedsCollateral_thenRollback() public {
        _openDebt();
        _cache.arm(
            address(_collateral),
            abi.encodeCall(
                _collateral.withdrawCollateral,
                (address(_asset), 1500e6, _borrower, address(_cache))
            ),
            true
        );
        bytes32 beforeState = _accountingDigest(address(_asset));
        bytes32 beforeCache = keccak256(
            abi.encode(_cache.getCachedPrice(address(_ohm), address(_asset)))
        );
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_asset), 1000e6, _borrower, _recipient);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            2000e6,
            "Nested and outer debits restored"
        );
        assertEq(_asset.balanceOf(_recipient), 0, "No outer payout");
        assertEq(_asset.balanceOf(address(_cache)), 100e6, "No nested withdrawal escapes");
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

    // Scenarios: BLCOL-WITHDRAW-C03.
    function test_givenCaughtUnauthorizedCacheAction_whenWithdrawing_thenOneDebit() public {
        _openDebt();
        _armUnauthorized(false);
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_asset), 1, _borrower, _recipient);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            2000e6 - 1,
            "Only outer debit"
        );
        assertEq(_asset.balanceOf(_recipient), 1, "One output");
        assertEq(
            _cache.rejection(),
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidContext.selector),
            "Cache caught the specified authorization error"
        );
        _assertDirectCollateral(2000e6 - 1);
    }

    // Scenarios: BLCOL-WITHDRAW-C04.
    function test_givenPropagatedUnauthorizedCacheAction_whenWithdrawing_thenRollback() public {
        _openDebt();
        _armUnauthorized(true);
        bytes32 beforeState = _accountingDigest(address(_asset));
        bytes32 beforeCache = keccak256(
            abi.encode(_cache.getCachedPrice(address(_ohm), address(_asset)))
        );
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_asset), 1, _borrower, _recipient);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            2000e6,
            "Failed refresh leaves collateral intact"
        );
        assertEq(_asset.balanceOf(_recipient), 0, "No delivery");
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
