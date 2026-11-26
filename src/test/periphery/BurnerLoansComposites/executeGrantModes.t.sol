// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansCompositesGrantModesTest} from "./fixtures/BurnerLoansCompositesGrantModesTest.sol";

/// @dev Shared operation cases fuzz direct/inline acceptance and temporary/reusable lifetime.
contract BurnerLoansCompositesExecuteGrantModesTest is BurnerLoansCompositesGrantModesTest {
    function _expectNoWalletFunding() private {
        vm.expectCall(
            address(_asset),
            abi.encodeWithSelector(IERC20.transferFrom.selector),
            uint64(0)
        );
    }

    // Scenarios: BLREX-P12, BLREX-A05.
    function test_whenDepositAlone(bool inlineGrant_, bool multiple_) public {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 15e6),
            _single(_deposit(10e6)),
            new IExecutor.Output[](0)
        );
        assertEq(
            results[0],
            abi.encode(uint128(10e6), uint128(10e6)),
            "Deposit returns credit and total collateral"
        );
        assertEq(_asset.balanceOf(_borrower), beforeWallet - 10e6, "Unused input refunded");
        _assertSettled(10e6, 0);
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-P13, BLREX-N08.
    function test_givenCollateralPosition_whenBorrowAlone(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            _single(_borrow(100e9, 1e6, _borrower)),
            new IExecutor.Output[](0)
        );
        IBurnerLoansDebt.BorrowPreview memory result = abi.decode(
            results[0],
            (IBurnerLoansDebt.BorrowPreview)
        );
        // 100 OHM requires max(100 / 0.85, 100 * 1.25) = 125 collateral;
        // fee = 125e6 (6 decimals) * 25 / 10000 = 312500 raw collateral units.
        assertEq(result.fee, 312500, "Independent origination fee basis");
        assertEq(_asset.balanceOf(_borrower), beforeWallet - 312500, "Only actual fee spent");
        assertEq(_ohm.balanceOf(_borrower), 100e9, "Borrow recipient receives 9-decimal principal");
        _assertSettled(2000e6, 100e9);
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-P14, BLREX-N09.
    function test_givenOlderDebt_whenRepayAlone(
        bool inlineGrant_,
        bool multiple_
    ) public givenOlderDebt {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 supplyBefore = _ohm.totalSupply();
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_ohm), 100e9),
            _single(_repay(100e9)),
            new IExecutor.Output[](0)
        );
        assertEq(
            abi.decode(results[0], (uint128)),
            0,
            "Repayment reports zero remaining principal"
        );
        assertEq(_ohm.balanceOf(_borrower), 0, "Exact principal supplied by caller");
        assertEq(
            _ohm.totalSupply(),
            supplyBefore - 100e9,
            "Inventory burns repaid minted principal"
        );
        _assertSettled(2000e6, 0);
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-P15, BLREX-N10.
    function test_givenCollateralPosition_whenWithdrawAlone(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            new IExecutor.Funding[](0),
            _single(_withdraw(2000e6)),
            new IExecutor.Output[](0)
        );
        IBurnerLoansCollateral.WithdrawPreview memory result = abi.decode(
            results[0],
            (IBurnerLoansCollateral.WithdrawPreview)
        );
        assertEq(result.returnToken, address(_asset), "Expected underlying output returned");
        assertEq(result.returnAmount, 2000e6, "Exact raw underlying output returned");
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet + 2000e6,
            "Withdrawal proceeds refunded to account"
        );
        _assertSettled(0, 0);
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-P16, BLREX-N11.
    function test_givenOlderDebt_whenExtendAlone(
        bool inlineGrant_,
        bool multiple_
    ) public givenOlderDebt {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint48 maturityBefore = _position().maturity;
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(uint256(7), uint256(0))
        );
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 10),
            _single(_extend(1)),
            new IExecutor.Output[](0)
        );
        IBurnerLoansDebt.ExtendPreview memory result = abi.decode(
            results[0],
            (IBurnerLoansDebt.ExtendPreview)
        );
        assertEq(result.fee, 7, "Exact fee-calculator result settled");
        assertEq(
            _position().maturity,
            maturityBefore + 30 days,
            "Maturity increases by one configured term"
        );
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet - 7,
            "Unused extension funding refunded"
        );
        _assertSettled(2000e6, 100e9);
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-P01.
    function test_whenDepositThenBorrow(bool inlineGrant_, bool multiple_) public {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _deposit(2000e6);
        operations[1] = _borrow(100e9, 1e6, _borrower);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 2100e6),
            operations,
            new IExecutor.Output[](0)
        );
        assertEq(results.length, 2, "Both ordered operations return results");
        // Credit 2000e6 plus fee 125e6 * 25 / 10000 = 312500 raw collateral.
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet - 2000e6 - 312500,
            "Only deposit and independently derived fee spent"
        );
        assertEq(_ohm.balanceOf(_borrower), 100e9, "Borrow executes after collateral is credited");
        _assertSettled(2000e6, 100e9);
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-A32.
    function test_whenLaterBorrowActionIsNotGranted_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        grant.actions = 1;
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _deposit(2000e6);
        operations[1] = _borrow(100e9, 1e6, _borrower);

        _expectNoWalletFunding();
        vm.expectCall(
            address(_collateral),
            abi.encodeWithSelector(IBurnerLoansCollateral.depositCollateral.selector),
            uint64(0)
        );
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 2100e6),
            operations,
            new IExecutor.Output[](0)
        );
        _assertSettled(0, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-P02.
    function test_givenOlderDebt_whenRepayThenWithdraw(
        bool inlineGrant_,
        bool multiple_
    ) public givenOlderDebt {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _repay(100e9);
        operations[1] = _withdraw(2000e6);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_ohm), 100e9),
            operations,
            new IExecutor.Output[](0)
        );
        assertEq(results.length, 2, "Repayment and withdrawal both execute");
        assertEq(_ohm.balanceOf(_borrower), 0, "Earlier principal is repaid");
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet + 2000e6,
            "Repaid position releases all collateral"
        );
        _assertSettled(0, 0);
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-P17.
    function test_whenDepositThenWithdraw(bool inlineGrant_, bool multiple_) public {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _deposit(10e6);
        operations[1] = _withdraw(10e6);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 10e6),
            operations,
            new IExecutor.Output[](0)
        );
        assertEq(results.length, 2, "Both operations execute within one accepted grant");
        assertEq(_asset.balanceOf(_borrower), beforeWallet, "Round trip returns exact input");
        _assertSettled(0, 0);
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-P18.
    function test_whenRepeatedDeposits(bool inlineGrant_, bool multiple_) public {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](3);
        operations[0] = _deposit(1);
        operations[1] = _deposit(1);
        operations[2] = _deposit(1);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 3),
            operations,
            new IExecutor.Output[](0)
        );
        assertEq(results.length, 3, "Repeated actions are not single-operation limited");
        _assertSettled(3, 0);
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-I07, BLREX-N04.
    function test_whenDepositAmountIsZero_reverts(bool inlineGrant_, bool multiple_) public {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            new IExecutor.Funding[](0),
            _single(_deposit(0)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Rejected operation preserves caller collateral"
        );
        _assertSettled(0, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-I08, BLREX-N08.
    function test_whenBorrowAmountIsZero_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            new IExecutor.Funding[](0),
            _single(_borrow(0, 1e6, _borrower)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Rejected operation preserves caller collateral"
        );
        _assertSettled(2000000000, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-I09, BLREX-N09.
    function test_whenRepayAmountIsZero_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public givenOlderDebt {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            new IExecutor.Funding[](0),
            _single(_repay(0)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Rejected operation preserves caller collateral"
        );
        _assertSettled(2000000000, 100000000000);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-I10, BLREX-N10.
    function test_whenWithdrawAmountIsZero_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            new IExecutor.Funding[](0),
            _single(_withdraw(0)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Rejected operation preserves caller collateral"
        );
        _assertSettled(2000000000, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-I11, BLREX-N11.
    function test_whenExtendTermsIsZero_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public givenOlderDebt {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            new IExecutor.Funding[](0),
            _single(_extend(0)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Rejected operation preserves caller collateral"
        );
        _assertSettled(2000000000, 100000000000);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-A09.
    function test_whenDepositActionIsNotGranted_reverts(bool inlineGrant_, bool multiple_) public {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        grant.actions = 2;
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        _expectNoWalletFunding();
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            _single(_deposit(1)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Missing action permission collects no wallet inputs"
        );
        _assertSettled(0, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-A20.
    function test_whenBorrowActionIsNotGranted_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        grant.actions = 1;
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        _expectNoWalletFunding();
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            _single(_borrow(1, 1e6, _borrower)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Missing action permission collects no wallet inputs"
        );
        _assertSettled(2000000000, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-A21.
    function test_whenWithdrawActionIsNotGranted_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        grant.actions = 1;
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        _expectNoWalletFunding();
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            _single(_withdraw(1)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Missing action permission collects no wallet inputs"
        );
        _assertSettled(2000000000, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-A22.
    function test_whenExtendActionIsNotGranted_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public givenOlderDebt {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        grant.actions = 1;
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        _expectNoWalletFunding();
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            _single(_extend(1)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Missing action permission collects no wallet inputs"
        );
        _assertSettled(2000000000, 100000000000);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-A26.
    function test_givenTemporaryGrant_whenNextTransactionUsesIt_reverts(bool inlineGrant_) public {
        IOperatorAuth.Grant memory grant = _grant(false);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 blockBefore = block.number;
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0)
        );
        assertEq(results.length, 1, "Temporary grant works in accepting transaction");
        _assertAcceptedGrant(false);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(_accountOwner);
        _account.runWithExistingGrant(
            _executor,
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0)
        );
        assertEq(block.number, blockBefore, "Transaction lifetime differs even in the same block");
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Expired authority collects no later input"
        );
        _assertSettled(1, 0);
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            1,
            "Consumed acceptance epoch remains consumed"
        );
    }

    // Scenarios: BLREX-A27.
    function test_givenReusableGrant_whenNextTransactionUsesIt(bool inlineGrant_) public {
        IOperatorAuth.Grant memory grant = _grant(true);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 blockBefore = block.number;
        bytes[] memory first = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0)
        );
        vm.prank(_accountOwner);
        bytes[] memory second = _account.runWithExistingGrant(
            _executor,
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0)
        );
        assertEq(first.length, 1, "First execution succeeds");
        assertEq(second.length, 1, "Later transaction reuses authority without another acceptance");
        assertEq(block.number, blockBefore, "Reusable lifetime does not require a block change");
        _assertSettled(2, 0);
        _assertAcceptedGrant(true);
    }

    // Scenarios: BLREX-T03.
    function test_whenLaterDepositExceedsFunds_reverts(bool inlineGrant_, bool multiple_) public {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _deposit(10e6);
        operations[1] = _deposit(1);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientFunds.selector,
                address(_asset),
                1,
                0
            )
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 10e6),
            operations,
            new IExecutor.Output[](0)
        );
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Later failure restores all wallet funding"
        );
        _assertSettled(0, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }
}
