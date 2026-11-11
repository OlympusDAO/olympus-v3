// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Libraries

// Contracts

import {BurnerLoansLensTest} from "./BurnerLoansLensTest.sol";

// Explicit boundary values and casts model the declared fixture domains.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)

contract BurnerLoansLensGetActiveBorrowersTest is BurnerLoansLensTest {
    // Scenarios: BLLENS-BORROWERS-L01.
    function test_givenActiveEnabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(true, true);
        _assertBorrowers(caller_, new address[](0), 0);
    }

    // Scenarios: BLLENS-BORROWERS-L02.
    function test_givenActiveDisabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(true, false);
        _assertBorrowers(caller_, new address[](0), 0);
    }

    // Scenarios: BLLENS-BORROWERS-L03.
    function test_givenInactiveEnabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(false, true);
        _assertBorrowers(caller_, new address[](0), 0);
    }

    // Scenarios: BLLENS-BORROWERS-L04.
    function test_givenInactiveDisabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(false, false);
        _assertBorrowers(caller_, new address[](0), 0);
    }

    // Scenarios: BLLENS-BORROWERS-I01.
    function test_whenUnknownAsset_reverts(address caller_) public {
        address asset = makeAddr("unknown asset");
        bytes memory failure = abi.encodeWithSelector(
            IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
            asset
        );
        vm.expectRevert(failure);
        vm.prank(caller_);
        _lens.getActiveBorrowers(asset);
        vm.expectRevert(failure);
        vm.prank(caller_);
        _lens.assetActiveDebtOhm(asset);
    }

    // Scenarios: BLLENS-BORROWERS-I02.
    function test_whenZeroAsset_reverts(address caller_) public {
        address asset = address(0);
        bytes memory failure = abi.encodeWithSelector(
            IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
            asset
        );
        vm.expectRevert(failure);
        vm.prank(caller_);
        _lens.getActiveBorrowers(asset);
        vm.expectRevert(failure);
        vm.prank(caller_);
        _lens.assetActiveDebtOhm(asset);
    }

    // Scenarios: BLLENS-BORROWERS-P01.
    function test_givenEmptyMarket_whenQueried(address caller_) public {
        _assertBorrowers(caller_, new address[](0), 0);
    }

    // Scenarios: BLLENS-BORROWERS-P04.
    function test_givenCollateralOnly_whenQueried(address caller_) public {
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1000e6, _borrower);
        _assertBorrowers(caller_, new address[](0), 0);
    }

    // Scenarios: BLLENS-BORROWERS-P05.
    function test_givenSingleDebt_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);
        _assertBorrowers(caller_, _one(_ALICE), 100e9);
    }

    // Scenarios: BLLENS-BORROWERS-P06.
    function test_givenTwoBorrowers_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);
        _seedDebt(_BOB, 1000e6, 200e9);
        _assertBorrowers(caller_, _two(_ALICE, _BOB), 300e9);
    }

    // Scenarios: BLLENS-BORROWERS-P07.
    function test_givenRepeatedBorrow_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);
        vm.prank(_ALICE);
        _debt.borrow(address(_asset), 50e9, _ALICE, _ALICE, type(uint256).max, address(0));
        _assertBorrowers(caller_, _one(_ALICE), 150e9);
    }

    // Scenarios: BLLENS-BORROWERS-P08.
    function test_givenPartialRepayment_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);
        _repay(_ALICE, 40e9);
        _assertBorrowers(caller_, _one(_ALICE), 60e9);
    }

    // Scenarios: BLLENS-BORROWERS-P09.
    function test_givenFullRepayment_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);
        _seedDebt(_BOB, 1000e6, 200e9);
        _seedDebt(_CAROL, 1000e6, 300e9);
        _repay(_ALICE, 100e9);
        _assertBorrowers(caller_, _two(_BOB, _CAROL), 500e9);
    }

    // Scenarios: BLLENS-BORROWERS-P10.
    function test_givenDefault_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);
        _seedDebt(_BOB, 1000e6, 200e9);
        _seedDebt(_CAROL, 1000e6, 300e9);
        _default(_BOB);
        _assertBorrowers(caller_, _two(_ALICE, _CAROL), 400e9);
    }

    // Scenarios: BLLENS-BORROWERS-P11.
    function test_givenReopenedDebt_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);
        _repay(_ALICE, 100e9);
        vm.prank(_ALICE);
        _debt.borrow(address(_asset), 70e9, _ALICE, _ALICE, type(uint256).max, address(0));
        _assertBorrowers(caller_, _one(_ALICE), 70e9);
    }

    // Scenarios: BLLENS-BORROWERS-P03.
    function test_givenDifferentBorrowerInOtherMarket_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);
        _seedOtherMarket(_BOB, 200e9);
        _assertBorrowers(caller_, _one(_ALICE), 100e9);
    }

    // Scenarios: BLLENS-BORROWERS-P12.
    function test_givenSameBorrowerInOtherMarket_whenQueried(address caller_) public {
        _seedDebt(_ALICE, 1000e6, 100e9);
        _seedOtherMarket(_ALICE, 500e9);
        _assertBorrowers(caller_, _one(_ALICE), 100e9);
    }

    // Scenarios: BLLENS-BORROWERS-P13.
    function test_givenTwoPositions_whenQueried(address caller_) public {
        uint32 market = _core.marketId(address(_asset));
        vm.startPrank(address(_core));
        uint64 first = _floan.createPosition(market, _ALICE);
        uint64 second = _floan.createPosition(market, _ALICE);
        _floan.increaseDebt(first, 50e9, 0, uint48(block.timestamp + 30 days));
        _floan.increaseDebt(second, 70e9, 0, uint48(block.timestamp + 30 days));

        vm.stopPrank();
        _assertBorrowers(caller_, _one(_ALICE), 120e9);
    }

    // Scenarios: BLLENS-BORROWERS-P14.
    function test_givenTwoPositionsOneClosed_whenQueried(address caller_) public {
        uint32 market = _core.marketId(address(_asset));
        vm.startPrank(address(_core));
        uint64 first = _floan.createPosition(market, _ALICE);
        uint64 second = _floan.createPosition(market, _ALICE);
        _floan.increaseDebt(first, 50e9, 0, uint48(block.timestamp + 30 days));
        _floan.increaseDebt(second, 70e9, 0, uint48(block.timestamp + 30 days));
        _floan.decreaseDebt(first, 50e9, 0);
        vm.stopPrank();
        _assertBorrowers(caller_, _one(_ALICE), 70e9);
    }

    // Scenarios: BLLENS-BORROWERS-T01.
    function test_givenMalformedBorrowerArray_whenQueried_reverts(address caller_) public {
        vm.mockCall(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.getActiveBorrowers.selector),
            hex"01"
        );
        // Short dynamic-array returndata has no typed ABI decoder error.
        vm.expectRevert(bytes(""));
        vm.prank(caller_);
        _lens.getActiveBorrowers(address(_asset));
    }

    // Scenarios: BLLENS-BORROWERS-T02.
    function test_givenBorrowerReadFailure_whenQueried_reverts(address caller_) public {
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.getActiveBorrowers.selector),
            abi.encodeWithSelector(FloanReadFailed.selector)
        );
        vm.expectRevert(FloanReadFailed.selector);
        vm.prank(caller_);
        _lens.getActiveBorrowers(address(_asset));
    }

    // Scenarios: BLLENS-BORROWERS-T03.
    function test_givenPrincipalReadFailure_whenQueried_reverts(address caller_) public {
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.getMarketPrincipalDue.selector),
            abi.encodeWithSelector(FloanReadFailed.selector)
        );
        vm.expectRevert(FloanReadFailed.selector);
        vm.prank(caller_);
        _lens.assetActiveDebtOhm(address(_asset));
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
