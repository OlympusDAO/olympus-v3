// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansAuth} from "src/policies/burnerloans/BurnerLoansAuth.sol";
import {BurnerLoansCollateralPriceCallbackTest} from "src/test/policies/BurnerLoansCollateral/fixtures/BurnerLoansCollateralPriceCallbackTest.sol";
import {CollateralPreparationAuthRotation} from "src/test/policies/BurnerLoansCollateral/fixtures/CollateralPreparationAuthRotation.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralDepositCollateralPriceCallbacksTest is
    BurnerLoansCollateralPriceCallbackTest
{
    // Scenarios: BLCOL-DEPOSIT-AUTH-C05.
    function test_givenPreparationAuthRotation_whenDeposited(bool delegated_) public {
        _openDebt();
        address operator = delegated_ ? _recipient : _borrower;
        if (delegated_) _approveOperator(_borrower, operator, type(uint48).max);
        _asset.mint(operator, 1);
        vm.prank(operator);
        _asset.approve(address(_core), type(uint256).max);
        CollateralPreparationAuthRotation callback = new CollateralPreparationAuthRotation();
        _rolesAdmin.grantRole(ADMIN_ROLE, address(callback));
        BurnerLoansAuth next = new BurnerLoansAuth(address(_kernel), address(_core));
        _cache.arm(
            address(callback),
            abi.encodeCall(callback.rotate, (IBurnerLoansCore(address(_core)), address(next))),
            true
        );
        uint256 epoch = _currentAuthEpoch();
        uint256 accountEpoch = _auth.accountEpochs(_borrower);
        uint256 pairEpoch = _auth.pairEpochs(_borrower, operator);
        (address originalAuth, ) = _core.authConfig();
        vm.expectCall(
            address(_cache),
            abi.encodeWithSelector(_cache.cachePriceIfNecessary.selector),
            uint64(0)
        );
        vm.prank(operator);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        _assertDirectCollateral(2000e6 + 1);
        assertEq(_currentAuthEpoch(), epoch, "No price callback rotates Auth");
        assertEq(_auth.accountEpochs(_borrower), accountEpoch, "Account epoch remains unchanged");
        assertEq(_auth.pairEpochs(_borrower, operator), pairEpoch, "Pair epoch remains unchanged");
        (address selected, ) = _core.authConfig();
        assertEq(selected, originalAuth, "Selected verifier remains unchanged");
        assertEq(
            _lens.getPosition(address(_asset), _borrower).debtOhm,
            100e9,
            "No price callback mutates principal"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-C01.
    function test_givenCacheRepaymentArmed_whenDeposited() public {
        _openDebt();
        _ohm.mint(address(_cache), 100e9);
        vm.prank(address(_cache));
        _ohm.approve(address(_core), 100e9);
        _cache.arm(
            address(_debt),
            abi.encodeCall(_debt.repay, (address(_asset), 100e9, _borrower)),
            true
        );
        vm.expectCall(
            address(_cache),
            abi.encodeWithSelector(_cache.cachePriceIfNecessary.selector),
            uint64(0)
        );
        vm.prank(_borrower);
        (uint128 credit, uint128 collateral) = _collateral.depositCollateral(
            address(_asset),
            1,
            _borrower
        );
        assertEq(credit, 1, "Only outer credit");
        assertEq(collateral, 2000e6 + 1, "Actual final collateral");
        _assertDirectCollateral(collateral);
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Armed cache cannot repay principal");
        assertEq(
            _lens.getPosition(address(_asset), _borrower).debtOhm,
            100e9,
            "Borrower principal remains unchanged"
        );
        assertEq(_ohm.balanceOf(address(_cache)), 100e9, "Armed callback funds are untouched");
    }

    // Scenarios: BLCOL-DEPOSIT-C03.
    function test_givenCaughtUnauthorizedCacheAction_whenDeposited() public {
        _openDebt();
        _armUnauthorized(false);
        vm.expectCall(
            address(_cache),
            abi.encodeWithSelector(_cache.cachePriceIfNecessary.selector),
            uint64(0)
        );
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        _assertDirectCollateral(2000e6 + 1);
        assertEq(_cache.rejection().length, 0, "Unexecuted cache callback catches no error");
        assertEq(
            _lens.getPosition(address(_asset), _borrower).debtOhm,
            100e9,
            "No nested mutation"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-C04.
    function test_givenPropagatedUnauthorizedCacheAction_whenDeposited() public {
        _openDebt();
        _armUnauthorized(true);
        bytes32 beforeCache = keccak256(
            abi.encode(_cache.getCachedPrice(address(_ohm), address(_asset)))
        );
        vm.expectCall(
            address(_cache),
            abi.encodeWithSelector(_cache.cachePriceIfNecessary.selector),
            uint64(0)
        );
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        _assertDirectCollateral(2000e6 + 1);
        assertEq(
            keccak256(abi.encode(_cache.getCachedPrice(address(_ohm), address(_asset)))),
            beforeCache,
            "Deposit preserves cache observation"
        );
        assertEq(_cache.rejection().length, 0, "Unexecuted callback cannot propagate an error");
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
