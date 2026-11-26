// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";

// Contracts
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC20FeeOnTransfer} from "src/test/mocks/MockERC20FeeOnTransfer.sol";
import {BurnerLoansCompositesGrantModesTest} from "./fixtures/BurnerLoansCompositesGrantModesTest.sol";

contract BurnerLoansCompositesExecuteSettlementTest is BurnerLoansCompositesGrantModesTest {
    error TransferFailed();

    // Scenarios: BLREX-T07, BLREX-T11.
    function test_givenOlderDebt_whenWithdrawalCannotSettle_reverts(
        bool inlineGrant_,
        bool multiple_,
        bool wrongToken_
    ) public givenOlderDebt {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        address token = wrongToken_ ? address(_ohm) : address(_asset);
        uint256 minimum = wrongToken_ ? 2000e6 : 2000e6 + 1;
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _repay(100e9);
        operations[1] = IExecutor.Operation(
            IExecutor.OperationKind.Withdraw,
            abi.encode(
                IExecutor.Withdraw(address(_asset), 2000e6, address(_executor), token, minimum)
            )
        );
        uint256 supply = _ohm.totalSupply();
        bytes memory reason = wrongToken_
            ? abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_UnexpectedOutput.selector,
                token,
                address(_asset)
            )
            : abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientOutput.selector,
                minimum,
                2000e6
            );
        vm.expectRevert(reason);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_ohm), 100e9),
            operations,
            new IExecutor.Output[](0)
        );
        _assertSettled(2000e6, 100e9);
        assertEq(_ohm.balanceOf(_borrower), 100e9, "Repayment funding restored");
        assertEq(_ohm.totalSupply(), supply, "Earlier OHM burn rolled back");
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-D04.
    function test_whenBorrowThenRepaySameBlock_reverts(bool inlineGrant_, bool multiple_) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](3);
        operations[0] = _deposit(2000e6);
        operations[1] = _borrow(100e9, 1e6, address(_executor));
        operations[2] = _repay(100e9);
        uint256 supply = _ohm.totalSupply();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_SameBlockRepay.selector,
                uint48(vm.getBlockNumber())
            )
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 2001e6),
            operations,
            new IExecutor.Output[](0)
        );
        _assertSettled(0, 0);
        assertEq(_ohm.totalSupply(), supply, "Earlier OHM mint rolled back");
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Wallet funding restored");
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-P05.
    function test_givenOlderDebt_whenExtensionFeeHasReferral(
        bool inlineGrant_,
        bool multiple_
    ) public givenOlderDebt {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        address treasury = _payout.treasury();
        uint256 treasuryBefore = _asset.balanceOf(treasury);
        uint256 walletBefore = _asset.balanceOf(_borrower);
        uint48 maturityBefore = _position().maturity;
        _quoteFee(7, 3);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 15),
            _single(_extension(1, 10, _recipient)),
            new IExecutor.Output[](0)
        );
        IBurnerLoansDebt.ExtendPreview memory result = abi.decode(
            results[0],
            (IBurnerLoansDebt.ExtendPreview)
        );
        // Protocol and referral components are raw collateral units. Total fee = 7 + 3.
        assertEq(result.fee, 10, "Result reports both paid fee components");
        assertEq(_asset.balanceOf(treasury), treasuryBefore + 7, "Treasury receives protocol fee");
        assertEq(_asset.balanceOf(_recipient), 3, "Referrer receives referral fee");
        assertEq(_asset.balanceOf(_borrower), walletBefore - 10, "Unused fee funding refunded");
        assertEq(
            _position().maturity,
            maturityBefore + 30 days,
            "Stored maturity advances by one term"
        );
        _assertSettled(2000e6, 100e9);
    }

    // Scenarios: BLREX-P06.
    function test_givenOlderDebt_whenBorrowAndExtensionAreFree(
        bool inlineGrant_,
        bool multiple_
    ) public givenOlderDebt {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        uint256 walletBefore = _asset.balanceOf(_borrower);
        uint48 maturityBefore = _position().maturity;
        _quoteFee(0, 0);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _borrow(100e9, 0, _borrower);
        operations[1] = _extension(1, 0, address(0));
        vm.expectCall(address(_asset), abi.encodeWithSelector(IERC20.transferFrom.selector), 0);
        _executeGrantMode(
            inlineGrant_,
            signed,
            new IExecutor.Funding[](0),
            operations,
            new IExecutor.Output[](0)
        );
        _assertSettled(2000e6, 200e9);
        assertEq(_ohm.balanceOf(_borrower), 200e9, "Free top-up pays the caller");
        assertEq(
            _position().maturity,
            maturityBefore + 30 days,
            "Free extension advances maturity"
        );
        assertEq(_asset.balanceOf(_borrower), walletBefore, "Free operations spend no collateral");
    }

    // Scenarios: BLREX-T06, BLREX-N05.
    function test_givenOlderDebt_whenFeeExceedsOneCeiling_reverts(
        bool inlineGrant_,
        bool multiple_,
        bool extend_,
        bool callerCeiling_
    ) public givenOlderDebt {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        uint256 walletBefore = _asset.balanceOf(_borrower);
        uint48 maturityBefore = _position().maturity;
        _quoteFee(7, 0);
        uint256 cap = callerCeiling_ ? 6 : type(uint256).max;
        IExecutor.Operation memory operation = extend_
            ? _extension(1, cap, address(0))
            : _borrow(100e9, cap, _borrower);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansDebt.BurnerLoans_FeeExceedsMax.selector, 7, 6)
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), callerCeiling_ ? 7 : 6),
            _single(operation),
            new IExecutor.Output[](0)
        );
        _assertSettled(2000e6, 100e9);
        assertEq(_position().maturity, maturityBefore, "Rejected fee leaves maturity unchanged");
        assertEq(_asset.balanceOf(_borrower), walletBefore, "Rejected fee restores wallet funding");
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-T01, BLREX-T02.
    function test_whenExecutorHoldsProtectedCollateral(
        bool inlineGrant_,
        bool multiple_,
        bool short_
    ) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _asset.mint(address(_executor), 50e6);
        if (short_)
            vm.expectRevert(
                abi.encodeWithSelector(
                    IExecutor.BurnerLoansComposites_InsufficientFunds.selector,
                    address(_asset),
                    10e6,
                    10e6 - 1
                )
            );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), short_ ? 10e6 - 1 : 15e6),
            _single(_deposit(10e6)),
            new IExecutor.Output[](0)
        );
        uint128 deposited = short_ ? 0 : 10e6;
        assertEq(_position().depositedCollateral, deposited, "Only covered deposit is credited");
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            deposited,
            "Actual custody matches credit"
        );
        assertEq(_asset.balanceOf(_borrower), 10_000e6 - deposited, "Wallet spends only deposit");
        assertEq(_asset.balanceOf(address(_executor)), 50e6, "Protected funds remain intact");
        assertEq(_asset.allowance(address(_executor), address(_core)), 0, "Core allowance cleared");
    }

    // Scenarios: BLREX-T04, BLREX-T08.
    function test_whenTokenTransferFails_reverts(
        bool inlineGrant_,
        bool multiple_,
        bool refund_
    ) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        bytes memory transfer = refund_
            ? abi.encodeCall(IERC20.transfer, (_borrower, 1))
            : abi.encodeCall(IERC20.transferFrom, (_borrower, address(_executor), 11));
        vm.mockCallRevert(
            address(_asset),
            transfer,
            abi.encodeWithSelector(TransferFailed.selector)
        );
        vm.expectRevert(TransferFailed.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 11),
            _single(_deposit(10)),
            new IExecutor.Output[](0)
        );
        _assertSettled(0, 0);
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Transfer failure restores wallet");
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-T05.
    function test_whenFundingCreditIsInexact_reverts(bool inlineGrant_, bool multiple_) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        MockERC20FeeOnTransfer token = new MockERC20FeeOnTransfer("Tax", "TAX", _recipient);
        token.mint(_borrower, 100);
        IExecutor.Funding[] memory funding = new IExecutor.Funding[](2);
        funding[0] = IExecutor.Funding(address(_asset), 1);
        funding[1] = IExecutor.Funding(address(token), 100);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(token),
                address(_executor),
                100,
                90
            )
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            funding,
            _single(_deposit(1)),
            new IExecutor.Output[](0)
        );
        assertEq(token.balanceOf(_borrower), 100, "Wallet retains all input");
        assertEq(token.balanceOf(_recipient), 0, "Transfer tax rolled back");
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Earlier funding transfer rolled back");
        _assertSettled(0, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-N03, BLREX-N07.
    function test_whenUnusedFundsAccompanyRepeatedOperations(
        bool inlineGrant_,
        bool multiple_,
        uint256 amount_,
        uint8 count_
    ) public {
        _assertRepeatedOperations(inlineGrant_, multiple_, amount_, bound(count_, 1, 128));
    }

    // Scenarios: BLREX-N03, BLREX-N07.
    function test_whenUnusedFundingIsZeroWithOneOperation() public {
        _assertRepeatedOperations(false, false, 0, 1);
    }

    // Scenarios: BLREX-N03, BLREX-N07.
    function test_whenUnusedFundingIsOneWithLongBatch() public {
        _assertRepeatedOperations(true, false, 1, 128);
    }

    // Scenarios: BLREX-N03, BLREX-N07.
    function test_whenUnusedFundingIsMaximumWithLongBatch() public {
        _assertRepeatedOperations(true, true, type(uint256).max, 128);
    }

    function _assertRepeatedOperations(
        bool inlineGrant_,
        bool multiple_,
        uint256 amount_,
        uint256 count_
    ) private {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        MockERC20 token = new MockERC20("Unused", "UNUSED", 18);
        token.mint(_borrower, amount_);
        IExecutor.Funding[] memory funding = new IExecutor.Funding[](2);
        funding[0] = IExecutor.Funding(address(_asset), count_ + 1);
        funding[1] = IExecutor.Funding(address(token), amount_);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](count_);
        for (uint256 i; i < count_; ++i) operations[i] = _deposit(1);
        vm.expectCall(address(_asset), abi.encodeCall(IERC20.transfer, (_borrower, 1)), 1);
        if (amount_ != 0)
            vm.expectCall(address(token), abi.encodeCall(IERC20.transfer, (_borrower, amount_)), 1);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            funding,
            operations,
            new IExecutor.Output[](0)
        );
        assertEq(results.length, count_, "Every ordered operation returns a result");
        assertEq(token.balanceOf(_borrower), amount_, "All unused input refunded");
        assertEq(token.balanceOf(address(_executor)), 0, "Executor retains no unused token");
        assertEq(
            token.allowance(address(_executor), address(_core)),
            0,
            "Unused token was never approved to Core"
        );
        assertEq(
            _asset.balanceOf(_borrower),
            10_000e6 - count_,
            "Caller pays exact total deposited"
        );
        _assertSettled(uint128(count_), 0);
    }

    function _quoteFee(uint256 protocol_, uint256 referral_) private {
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(protocol_, referral_)
        );
    }

    function _extension(
        uint16 terms_,
        uint256 cap_,
        address referrer_
    ) private view returns (IExecutor.Operation memory) {
        return
            IExecutor.Operation(
                IExecutor.OperationKind.Extend,
                abi.encode(IExecutor.Extend(address(_asset), terms_, cap_, referrer_))
            );
    }
}
