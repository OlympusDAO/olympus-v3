// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {IERC3156FlashLender} from "src/interfaces/maker-dao/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "src/interfaces/maker-dao/IERC3156FlashBorrower.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansSwapAdapter} from "src/periphery/interfaces/IBurnerLoansSwapAdapter.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {BurnerLoansCompositesTest} from "./fixtures/BurnerLoansCompositesTest.sol";
import {MockCompositesFlashLender} from "./fixtures/MockCompositesFlashLender.sol";
import {MockCompositesMigrator} from "./fixtures/MockCompositesMigrator.sol";
import {MockCompositesSwapAdapter} from "./fixtures/MockCompositesSwapAdapter.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {CoreCallbackToken} from "src/test/policies/BurnerLoansCore/fixtures/CoreCallbackToken.sol";

contract BurnerLoansCompositesExecuteFlashTest is BurnerLoansCompositesTest {
    CoreCallbackToken internal _dai;
    MockERC20 internal _usds;
    MockCompositesFlashLender internal _lender;
    MockCompositesSwapAdapter internal _adapter;

    function _integrations() internal override returns (IExecutor.Integrations memory) {
        _dai = new CoreCallbackToken();
        _usds = new MockERC20("USDS", "USDS", 18);
        _lender = new MockCompositesFlashLender(_dai);
        _adapter = new MockCompositesSwapAdapter();
        return
            IExecutor.Integrations(
                address(new MockCompositesMigrator(_dai, _usds)),
                address(_adapter),
                address(_lender)
            );
    }

    function setUp() public override {
        super.setUp();
        _dai.mint(address(_lender), 100e18);
        _dai.mint(address(_executor), 7e18);
        _fundDAI(_borrower, 15e18);
    }

    modifier givenOlderDebt() {
        vm.startPrank(_borrower);
        _collateral.depositCollateral(address(_asset), 2000e6, _borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 1e6, address(0));
        vm.stopPrank();
        vm.roll(vm.getBlockNumber() + 1);
        _;
    }

    // Scenarios: BLRFL-P06.
    function test_givenOlderDebt_whenFlashProceedsFundRepayment() public givenOlderDebt {
        _adapter.setOutput(address(_ohm), 200e9);
        _adapter.setOutput(address(_dai), 100e18);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](3);
        operations[0] = _swapExactInput(address(_dai), address(_ohm), 100e18, 200e9);
        operations[1] = _repay(100e9);
        operations[2] = _swapExactInput(address(_ohm), address(_dai), 100e9, 100e18);

        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            new IExecutor.Funding[](0),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(100e18, 0),
            type(uint48).max
        );

        assertEq(abi.decode(results[1], (uint128)), 0, "Repayment result reports zero principal");
        assertEq(_position().debtOhm, 0, "Older Burner Loans debt repaid inside the flash loan");
        assertEq(_position().depositedCollateral, 2000e6, "Collateral remains in the position");
        assertEq(_ohm.balanceOf(_borrower), 100e9, "No wallet OHM pulled");
        assertEq(_dai.balanceOf(_borrower), 15e18, "No wallet DAI pulled");
        assertEq(_dai.balanceOf(address(_lender)), 100e18, "Lender recovers full principal");
        assertEq(_dai.balanceOf(address(_executor)), 7e18, "Executor DAI baseline preserved");
        assertEq(
            _dai.allowance(address(_executor), address(_lender)),
            0,
            "Lender allowance cleared"
        );
    }

    // Scenarios: BLRFL-P01, BLRFL-N01, BLRFL-N02.
    function test_whenWholeBatchUsesTheFlashBalance() public {
        _lender.configure(2e18, MockCompositesFlashLender.Behavior.Normal);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        // In raw 18-decimal units, 23e18 DAI exceeds 15e18 funding plus 7e18 protected DAI.
        // The reverse conversion restores 10e18 DAI, leaving 115e18 - 23e18 + 10e18 = 102e18.
        operations[0] = _convertDaiUsds(23e18);
        operations[1] = _convertUsdsToDai(10e18);
        IExecutor.Output[] memory outputs = new IExecutor.Output[](1);
        outputs[0] = IExecutor.Output(address(_usds), 13e18);
        vm.expectEmit(address(_executor));
        emit IExecutor.OperationExecuted(
            _borrower,
            0,
            IExecutor.OperationKind.ConvertDaiUsds,
            abi.encode(23e18)
        );
        vm.expectEmit(address(_executor));
        emit IExecutor.OperationExecuted(
            _borrower,
            1,
            IExecutor.OperationKind.ConvertDaiUsds,
            abi.encode(10e18)
        );
        vm.expectEmit(address(_executor));
        emit IExecutor.FlashLoanSettled(_borrower, 100e18, 2e18);
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            _funding(address(_dai), 15e18),
            operations,
            outputs,
            IExecutor.FlashLoan(100e18, 2e18),
            type(uint48).max
        );
        assertEq(results.length, 2, "Each operation has one result");
        assertEq(abi.decode(results[0], (uint256)), 23e18, "First operation result");
        assertEq(abi.decode(results[1], (uint256)), 10e18, "Second operation result");
        assertEq(_usds.balanceOf(_borrower), 13e18, "Only outer caller receives output");
        assertEq(_dai.balanceOf(_borrower), 0, "Funding exactly covers conversions and fee");
        assertEq(_dai.balanceOf(address(_lender)), 102e18, "Principal and fee repaid");
        assertEq(_dai.balanceOf(address(_executor)), 7e18, "Protected DAI preserved");
        assertEq(
            _dai.allowance(address(_executor), address(_lender)),
            0,
            "Lender approval cleared"
        );
    }

    // Scenarios: BLRFL-P03, BLRFL-N02.
    function test_whenTemporarySignedGrantAuthorizesFlashBatch() public {
        _borrower = vm.addr(_SIGNER_KEY);
        _adapter.setOutput(address(_asset), 2001e6);
        _adapter.setOutput(address(_dai), 101e18);
        IExecutor.SignedGrant memory signed = _signedTemporaryGrant();
        IExecutor.Operation[] memory operations = _creditOperations(101e18);
        IExecutor.Output[] memory outputs = new IExecutor.Output[](1);
        outputs[0] = IExecutor.Output(address(_dai), 1e18);
        vm.prank(_borrower);
        bytes[] memory results = _executor.executeWithGrant(
            new IExecutor.Funding[](0),
            operations,
            outputs,
            IExecutor.FlashLoan(100e18, 0),
            type(uint48).max,
            signed
        );
        assertEq(results.length, operations.length, "One result per operation");
        assertEq(abi.decode(results[0], (uint256)), 2001e6, "Initial swap result");
        assertEq(
            results[1],
            abi.encode(uint128(2000e6), uint128(2000e6)),
            "Complete deposit result"
        );
        IBurnerLoansDebt.BorrowPreview memory borrowResult = abi.decode(
            results[2],
            (IBurnerLoansDebt.BorrowPreview)
        );
        assertEq(borrowResult.resultingDebtOhm, 100e9, "Borrow result reports exact OHM debt");
        assertEq(borrowResult.maturity, _position().maturity, "Borrow result reports maturity");
        assertEq(abi.decode(results[3], (uint256)), 101e18, "Repayment swap result");
        assertEq(
            _position().depositedCollateral,
            2000e6,
            "Deposit belongs to signed submitting EOA"
        );
        assertEq(_position().debtOhm, 100e9, "Borrow belongs to signed submitting EOA");
        assertEq(_dai.balanceOf(_borrower), 1e18, "Only surplus after repayment is returned");
        assertEq(_dai.balanceOf(address(_lender)), 100e18, "Lender repaid");
        assertEq(
            _auth.getGrant(_borrower, address(_executor)).actions,
            0,
            "Temporary authority expired"
        );
    }

    // Scenarios: BLREX-T10.
    function test_whenSignedCreditRoundTripCannotRepay_reverts() public {
        _borrower = vm.addr(_SIGNER_KEY);
        _adapter.setOutput(address(_asset), 2001e6);
        _adapter.setOutput(address(_dai), 99e18);
        IExecutor.SignedGrant memory signed = _signedTemporaryGrant();
        IExecutor.Operation[] memory operations = _creditOperations(99e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientFunds.selector,
                address(_dai),
                100e18,
                99e18
            )
        );
        vm.prank(_borrower);
        _executor.executeWithGrant(
            new IExecutor.Funding[](0),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(100e18, 0),
            type(uint48).max,
            signed
        );
        _assertSignedCreditRestored();
    }

    // Scenarios: BLRFL-T06.
    function test_whenLenderRejectsCollectedRepayment_reverts() public {
        _borrower = vm.addr(_SIGNER_KEY);
        _adapter.setOutput(address(_asset), 2001e6);
        _adapter.setOutput(address(_dai), 101e18);
        _lender.configure(1e18, MockCompositesFlashLender.Behavior.RequireHigherRepayment);
        IExecutor.SignedGrant memory signed = _signedTemporaryGrant();
        IExecutor.Operation[] memory operations = _creditOperations(101e18);

        // Composites approves 100 DAI principal plus the quoted 1 DAI fee (18 decimals).
        // The lender collects all 101 DAI, then rejects its own higher balance requirement.
        vm.expectRevert(
            abi.encodeWithSelector(
                MockCompositesFlashLender.RepaymentShortfall.selector,
                101e18 + 1,
                101e18
            )
        );
        vm.prank(_borrower);
        _executor.executeWithGrant(
            new IExecutor.Funding[](0),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(100e18, 1e18),
            type(uint48).max,
            signed
        );
        _assertSignedCreditRestored();
    }

    function _assertSignedCreditRestored() private view {
        assertEq(_auth.pairEpochs(_borrower, address(_executor)), 0, "Signed acceptance restored");
        assertEq(_position().depositedCollateral, 0, "Earlier collateral credited then restored");
        assertEq(_position().debtOhm, 0, "Earlier borrowed principal restored");
        assertEq(_inventory.activePrincipalOhm(), 0, "Inventory principal restored");
        assertEq(_asset.balanceOf(address(_depositManager)), 0, "Custody restored");
        assertEq(_dai.balanceOf(address(_lender)), 100e18, "Lender balance restored");
        assertEq(_dai.balanceOf(address(_executor)), 7e18, "Executor protected balance restored");
        assertEq(
            _dai.allowance(address(_executor), address(_lender)),
            0,
            "Repayment allowance restored"
        );
    }

    function _creditOperations(
        uint256 repaymentOutput_
    ) private view returns (IExecutor.Operation[] memory operations) {
        operations = new IExecutor.Operation[](4);
        operations[0] = _swapExactInput(address(_dai), address(_asset), 100e18, 2001e6);
        operations[1] = _deposit(2000e6);
        operations[2] = _borrow(100e9, 1e6, address(_executor));
        operations[3] = _swapExactInput(address(_ohm), address(_dai), 100e9, repaymentOutput_);
    }

    // Scenarios: BLRFL-I02.
    function test_whenNoFlashRequestRejectsCallback_reverts(address caller_) public {
        _expectIdleRejection(caller_);
    }

    // Scenarios: BLRFL-I02.
    function test_whenNoFlashRequestRejectsConfiguredLender_reverts() public {
        _expectIdleRejection(address(_lender));
    }

    // Scenarios: BLRFL-A02, BLRFL-I01, BLRFL-I04, BLRFL-C02.
    function test_whenLenderCallbackDoesNotMatchRequest_reverts() public {
        _assertRejectedCallback(MockCompositesFlashLender.Behavior.ReplayCallback);
        _assertRejectedCallback(MockCompositesFlashLender.Behavior.WrongInitiator);
        _assertRejectedCallback(MockCompositesFlashLender.Behavior.WrongToken);
        _assertRejectedCallback(MockCompositesFlashLender.Behavior.WrongAmount);
        _assertRejectedCallback(MockCompositesFlashLender.Behavior.ChangedData);
    }

    // Scenarios: BLRFL-A01.
    function test_whenCallbackCallerIsNotLender_reverts() public {
        _assertRejectedCallback(MockCompositesFlashLender.Behavior.WrongCaller);
    }

    function _assertRejectedCallback(MockCompositesFlashLender.Behavior behavior_) private {
        _lender.configure(0, behavior_);
        vm.expectRevert(IExecutor.BurnerLoansComposites_InvalidFlashCallback.selector);
        _executeLoan(_borrower, 100e18, 0);
        _assertNoFlashEffects();
    }

    // Scenarios: BLRFL-I04.
    function test_whenLenderRepeatsCallbackDuringContinuation_reverts() public {
        _lender.configure(0, MockCompositesFlashLender.Behavior.ReplayDuringContinuation);
        _adapter.setExpectedRejection(
            address(_lender),
            abi.encodeCall(_lender.repeatActiveCallback, ())
        );
        vm.expectRevert(IExecutor.BurnerLoansComposites_InvalidFlashCallback.selector);
        _executeLoanWithSwap();
        _assertNoFlashEffects();
    }

    // Scenarios: BLRFL-C01.
    function test_whenFlashOperationAttemptsNestedExecution_reverts() public givenReusableGrant {
        _adapter.setExpectedRejection(address(this), abi.encodeCall(this.executeNestedDeposit, ()));
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        _executeLoanWithSwap();
        _assertNoFlashEffects();
        assertEq(_position().depositedCollateral, 0, "Nested lending does not commit");
    }

    // Scenarios: BLRFL-C01.
    function test_whenRepaymentTransferCatchesNestedExecution() public givenReusableGrant {
        _armRepaymentCallback(false);
        _executeLoan(_borrower, 100e18, 0);
        assertEq(
            _dai.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "Repayment-time callback reaches the executor guard"
        );
        _assertNoFlashEffects();
        assertEq(_position().depositedCollateral, 0, "Nested lending does not commit");
    }

    // Scenarios: BLRFL-C01.
    function test_whenRepaymentTransferPropagatesNestedExecution_reverts()
        public
        givenReusableGrant
    {
        _armRepaymentCallback(true);
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        _executeLoan(_borrower, 100e18, 0);
        _assertNoFlashEffects();
        assertEq(_position().depositedCollateral, 0, "Nested lending does not commit");
    }

    function _armRepaymentCallback(bool bubble_) private {
        _dai.setCallbackFrom(
            address(_lender),
            address(this),
            abi.encodeCall(this.executeNestedDeposit, ())
        );
        _dai.setCallbackPhases(false, true);
        _dai.setCallbackTransferRecipient(address(_lender));
        _dai.setBubbleCallbackFailure(bubble_);
    }

    // Scenarios: BLRFL-T01.
    function test_whenPrincipalReceiptIsExcess_reverts() public {
        _lender.configure(0, MockCompositesFlashLender.Behavior.ExcessReceipt);
        vm.expectRevert(IExecutor.BurnerLoansComposites_InexactFlashReceipt.selector);
        _executeLoan(_borrower, 99e18, 0);
        _assertNoFlashEffects();
    }

    // Scenarios: BLRFL-N01, BLRFL-N02.
    function test_whenPrincipalAndFeeFitLimits(uint256 principal_, uint256 fee_) public {
        _assertPermittedLoan(bound(principal_, 1, 100e18), bound(fee_, 0, 2e18));
    }

    // Scenarios: BLRFL-N01, BLRFL-N02.
    function test_whenPrincipalAndFeeFitBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        _assertPermittedLoan(1, 1);
        assertTrue(vm.revertToState(snapshot), "Restore one-unit fixture");
        _assertPermittedLoan(100e18 - 1, 2e18 - 1);
    }

    function _assertPermittedLoan(uint256 principal_, uint256 fee_) private {
        _lender.configure(fee_, MockCompositesFlashLender.Behavior.Normal);
        _executeLoan(_borrower, principal_, 2e18);
        assertEq(_dai.balanceOf(_borrower), 15e18 - fee_, "Caller pays the actual fee");
        assertEq(
            _dai.balanceOf(address(_lender)),
            100e18 + fee_,
            "Lender collects principal and actual fee"
        );
        assertEq(_dai.balanceOf(address(_executor)), 7e18, "Protected balance retained");
        assertEq(
            _dai.allowance(address(_executor), address(_lender)),
            0,
            "Lender allowance cleared"
        );
    }

    function executeNestedDeposit() external {
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
    }

    function _executeLoanWithSwap() private {
        IExecutor.Operation[] memory operations = _single(
            _swapExactInput(address(_dai), address(_usds), 1e18, 1e18)
        );
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_dai), 15e18),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(100e18, 0),
            type(uint48).max
        );
    }

    // Scenarios: BLRFL-T02.
    function test_whenRepaymentWouldUseProtectedBalance_reverts() public {
        IExecutor.Operation[] memory operations = _single(_convertDaiUsds(16e18));
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientFunds.selector,
                address(_dai),
                100e18,
                99e18
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_dai), 15e18),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(100e18, 0),
            type(uint48).max
        );
        _assertNoFlashEffects();
        assertEq(_usds.balanceOf(_borrower), 0, "Operation effects restored");
    }

    // Scenarios: BLRFL-T04.
    function test_whenOutputMinimumWouldCountLenderPrincipal_reverts() public {
        IExecutor.Output[] memory outputs = new IExecutor.Output[](1);
        outputs[0] = IExecutor.Output(address(_dai), 15e18 + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientReturn.selector,
                address(_dai),
                15e18 + 1,
                15e18
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_dai), 15e18),
            _roundTrip(),
            outputs,
            IExecutor.FlashLoan(100e18, 0),
            type(uint48).max
        );
        _assertNoFlashEffects();
    }

    // Scenarios: BLRFL-T03.
    function test_whenLenderDoesNotCompleteCallback_reverts(bool skip_) public {
        _lender.configure(
            0,
            skip_
                ? MockCompositesFlashLender.Behavior.SkipCallback
                : MockCompositesFlashLender.Behavior.ReturnFalse
        );
        vm.expectRevert(IExecutor.BurnerLoansComposites_IncompleteFlashLoan.selector);
        _executeLoan(_borrower, 100e18, 0);
        _assertNoFlashEffects();
    }

    // Scenarios: BLRFL-T03.
    function test_whenLenderSkipsRepaymentCollection_reverts() public {
        _lender.configure(0, MockCompositesFlashLender.Behavior.SkipCollection);
        vm.expectRevert(IExecutor.BurnerLoansComposites_InexactFlashRepayment.selector);
        _executeLoan(_borrower, 100e18, 0);
        _assertNoFlashEffects();
    }

    // Scenarios: BLRFL-T01.
    function test_whenPrincipalReceiptIsShort_reverts() public {
        _lender.configure(0, MockCompositesFlashLender.Behavior.ShortReceipt);
        vm.expectRevert(IExecutor.BurnerLoansComposites_InexactFlashReceipt.selector);
        _executeLoan(_borrower, 100e18, 0);
        _assertNoFlashEffects();
    }

    // Scenarios: BLRFL-N02.
    function test_whenFeeExceedsCap_reverts(uint256 cap_) public {
        cap_ = bound(cap_, 0, 15e18);
        _lender.configure(cap_ + 1, MockCompositesFlashLender.Behavior.Normal);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_FlashFeeTooHigh.selector,
                cap_,
                cap_ + 1
            )
        );
        _executeLoan(_borrower, 100e18, cap_);
        _assertNoFlashEffects();
    }

    // Scenarios: BLREX-T10, BLRFL-N02.
    function test_whenSignedBatchExceedsFlashFeeCap_reverts() public {
        _borrower = vm.addr(_SIGNER_KEY);
        _fundDAI(_borrower, 15e18);
        _asset.mint(_borrower, 10);
        vm.prank(_borrower);
        _asset.approve(address(_executor), 10);
        _lender.configure(2e18 + 1, MockCompositesFlashLender.Behavior.Normal);
        IExecutor.SignedGrant memory signed = _signedTemporaryGrant();
        IExecutor.Funding[] memory funding = new IExecutor.Funding[](2);
        funding[0] = IExecutor.Funding(address(_asset), 10);
        funding[1] = IExecutor.Funding(address(_dai), 15e18);
        IExecutor.Operation[] memory operations = _single(_deposit(10));
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_FlashFeeTooHigh.selector,
                2e18,
                2e18 + 1
            )
        );
        vm.prank(_borrower);
        _executor.executeWithGrant(
            funding,
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(100e18, 2e18),
            type(uint48).max,
            signed
        );
        _assertNoFlashEffects();
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Grant acceptance rolled back"
        );
        assertEq(_position().depositedCollateral, 0, "Deposit never commits");
        assertEq(_asset.balanceOf(address(_depositManager)), 0, "Collateral custody restored");
        assertEq(_asset.balanceOf(_borrower), 10, "Collateral funding restored");
    }

    // Scenarios: BLRFL-N02, BLRFL-N03.
    function test_whenPrincipalPlusFeeOverflows_reverts() public {
        _lender.configure(type(uint256).max, MockCompositesFlashLender.Behavior.Normal);
        vm.expectRevert(IExecutor.BurnerLoansComposites_FlashRepaymentOverflow.selector);
        _executeLoan(_borrower, 100e18, type(uint256).max);
        _assertNoFlashEffects();
    }

    // Scenarios: BLRFL-N01.
    function test_whenPrincipalExceedsCapacity_reverts(uint256 principal_) public {
        principal_ = bound(principal_, 100e18 + 1, type(uint256).max);
        _expectInvalidPrincipal(principal_);
    }

    // Scenarios: BLRFL-N01.
    function test_whenPrincipalBoundarySeeds_reverts() public {
        _expectInvalidPrincipal(100e18 + 1);
        _expectInvalidPrincipal(type(uint256).max);
    }

    // Scenarios: BLRFL-P04.
    function test_whenTwoAccountsExecuteInOneTransaction() public {
        _fundDAI(_recipient, 15e18);
        this.executeForTwoAccounts();
        assertEq(_usds.balanceOf(_borrower), 10e18, "First account receives its operation output");
        assertEq(_usds.balanceOf(_recipient), 2e18, "Second account receives its operation output");
        assertEq(_dai.balanceOf(_borrower), 5e18, "First account receives its unused equity");
        assertEq(_dai.balanceOf(_recipient), 13e18, "Second account receives its unused equity");
        assertEq(_dai.balanceOf(address(_lender)), 100e18, "Both loans repaid");
        assertEq(_dai.balanceOf(address(_executor)), 7e18, "No cross-account residual");
    }

    // Scenarios: BLRFL-P05.
    function test_whenFailedFlashIsCaughtAndRetriedInOneTransaction() public {
        this.executeFailedThenFreshLoan();
        assertEq(_usds.balanceOf(_borrower), 2e18, "Only successful request has effects");
        assertEq(_dai.balanceOf(_borrower), 13e18, "Failed request leaves no wallet debit");
    }

    // Scenarios: BLRFL-I04.
    function test_whenLenderRepeatsCallbackAfterCompletion_reverts() public {
        this.executeThenRejectStaleCallback();
        assertEq(_dai.balanceOf(_borrower), 15e18, "Completed settlement stays intact");
    }

    function executeThenRejectStaleCallback() external {
        _lender.configure(0, MockCompositesFlashLender.Behavior.ReplayDuringContinuation);
        _executeLoan(_borrower, 100e18, 0);
        vm.expectRevert(IExecutor.BurnerLoansComposites_InvalidFlashCallback.selector);
        _lender.repeatActiveCallback();
    }

    /// @dev Keeps both executor calls inside one top-level transaction in isolate mode.
    function executeForTwoAccounts() external {
        _loanAndConvert(_borrower, 10e18);
        _loanAndConvert(_recipient, 2e18);
    }

    /// @dev A failed lender collection must clear its transient writes by reverting.
    function executeFailedThenFreshLoan() external {
        _lender.configure(0, MockCompositesFlashLender.Behavior.SkipCollection);
        vm.expectRevert(IExecutor.BurnerLoansComposites_InexactFlashRepayment.selector);
        _executeLoan(_borrower, 100e18, 0);
        _lender.configure(0, MockCompositesFlashLender.Behavior.Normal);
        _loanAndConvert(_borrower, 2e18);
    }

    function _loanAndConvert(address account_, uint256 amount_) private {
        IExecutor.Operation[] memory operations = _single(_convertDaiUsds(amount_));
        vm.prank(account_);
        bytes[] memory results = _executor.execute(
            _funding(address(_dai), 15e18),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(100e18, 0),
            type(uint48).max
        );
        assertEq(results.length, 1, "Only results from the current request are returned");
        assertEq(
            abi.decode(results[0], (uint256)),
            amount_,
            "Operation result belongs to current request"
        );
    }

    function _expectInvalidPrincipal(uint256 principal_) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InvalidFlashAmount.selector,
                principal_,
                100e18
            )
        );
        _executeLoan(_borrower, principal_, 0);
        _assertNoFlashEffects();
    }

    function _expectIdleRejection(address caller_) private {
        vm.expectRevert(IExecutor.BurnerLoansComposites_InvalidFlashCallback.selector);
        vm.prank(caller_);
        IERC3156FlashBorrower(address(_executor)).onFlashLoan(
            address(_executor),
            address(_dai),
            1,
            0,
            ""
        );
        _assertNoFlashEffects();
    }

    function _signedTemporaryGrant() private view returns (IExecutor.SignedGrant memory signed) {
        signed.grant = _operatorGrant(_borrower, address(_executor), type(uint48).max);
        signed.grant.multiple = false;
        return _signedGrant(signed.grant);
    }

    function _fundDAI(address account_, uint256 amount_) private {
        _dai.mint(account_, amount_);
        vm.prank(account_);
        _dai.approve(address(_executor), amount_);
    }

    function _executeLoan(address account_, uint256 principal_, uint256 maxFee_) private {
        vm.prank(account_);
        _executor.execute(
            _funding(address(_dai), 15e18),
            _roundTrip(),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(principal_, maxFee_),
            type(uint48).max
        );
    }

    function _assertNoFlashEffects() private view {
        assertEq(_dai.balanceOf(address(_lender)), 100e18, "Lender funds restored");
        assertEq(_dai.balanceOf(address(_executor)), 7e18, "Protected balance retained");
        assertEq(_dai.balanceOf(_borrower), 15e18, "Wallet funding restored");
        assertEq(_dai.allowance(address(_executor), address(_lender)), 0, "No approval survives");
    }

    // Scenarios: BLRFL-P02, BLRFL-N01.
    function test_whenPrincipalIsZeroSkipsLender() public {
        vm.expectCall(
            address(_lender),
            abi.encodePacked(IERC3156FlashLender.maxFlashLoan.selector),
            0
        );
        vm.expectCall(address(_lender), abi.encodePacked(IERC3156FlashLender.flashFee.selector), 0);
        vm.expectCall(
            address(_lender),
            abi.encodePacked(IERC3156FlashLender.flashLoan.selector),
            0
        );
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            _funding(address(_dai), 15e18),
            _single(_convertDaiUsds(3e18)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, type(uint256).max),
            type(uint48).max
        );

        // One-to-one conversion of 3e18 DAI leaves 12e18 DAI and delivers 3e18 USDS.
        assertEq(results.length, 1, "Conversion returned one result");
        assertEq(abi.decode(results[0], (uint256)), 3e18, "Result reports USDS received");
        assertEq(_usds.balanceOf(_borrower), 3e18, "Conversion delivered USDS");
        assertEq(_dai.balanceOf(_borrower), 12e18, "Unused DAI refunded");
        assertEq(_dai.balanceOf(address(_lender)), 100e18, "Lender funds untouched");
        assertEq(_dai.balanceOf(address(_executor)), 7e18, "Protected balance retained");
        assertEq(_dai.allowance(address(_executor), address(_lender)), 0, "No lender approval");
    }

    // Scenarios: BLREX-N13, BLREX-P28.
    function test_whenExactOutputTargetsFlashRepayment() public {
        _lender.configure(5e18, MockCompositesFlashLender.Behavior.Normal);
        _adapter.setOutput(address(_dai), 3e18);
        _adapter.setUnspent(2e18);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _convertDaiUsds(13e18);
        operations[1] = _swapExactOutput(
            address(_dai),
            IExecutor.OutputTarget.FlashRepayment,
            0,
            5e18
        );
        uint48 deadline = type(uint48).max - 1;
        vm.expectCall(
            address(_adapter),
            abi.encodeCall(
                IBurnerLoansSwapAdapter.swapExactOutput,
                (
                    IBurnerLoansSwapAdapter.ExactOutputParams(
                        address(_usds),
                        address(_dai),
                        3e18,
                        5e18,
                        deadline,
                        hex"ab"
                    )
                )
            )
        );
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            _funding(address(_dai), 15e18),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(100e18, 6e18),
            deadline
        );
        // 15 funded + 100 borrowed - 13 converted = 102 DAI. The actual fee makes 105 due.
        assertEq(abi.decode(results[1], (uint256)), 3e18, "Swap buys the 3 DAI shortfall");
        assertEq(_usds.balanceOf(_borrower), 10e18, "Unspent USDS refunded");
        assertEq(_dai.balanceOf(address(_lender)), 105e18, "Actual fee collected");
        assertEq(_dai.balanceOf(address(_executor)), 7e18, "Protected DAI excluded");
    }

    // Scenarios: BLREX-P29.
    function test_whenFixedDaiUsdsConversionFundsFlashRepayment(bool feeFree_) public {
        uint256 fee = feeFree_ ? 0 : 5e18;
        _lender.configure(fee, MockCompositesFlashLender.Behavior.Normal);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        // 115 DAI is available. Converting 18 DAI less the fee leaves 97 DAI plus the fee.
        operations[0] = _convertDaiUsds(18e18 - fee);
        operations[1] = _convertUsdsToDai(3e18);
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            _funding(address(_dai), 15e18),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(100e18, feeFree_ ? 0 : 6e18),
            type(uint48).max
        );
        assertEq(abi.decode(results[1], (uint256)), 3e18, "Converts only the 3 DAI shortfall");
        assertEq(_usds.balanceOf(_borrower), 15e18 - fee, "Unused USDS refunded");
        assertEq(
            _dai.balanceOf(address(_lender)),
            100e18 + fee,
            "Principal and actual fee settled"
        );
        assertEq(_dai.balanceOf(address(_executor)), 7e18, "DAI baseline preserved");
    }

    // Scenarios: BLREX-T19.
    function test_whenFixedDaiUsdsConversionLeavesRepaymentShort_reverts() public {
        _lender.configure(5e18, MockCompositesFlashLender.Behavior.Normal);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _convertDaiUsds(13e18);
        operations[1] = _convertUsdsToDai(3e18 - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientFunds.selector,
                address(_dai),
                105e18,
                105e18 - 1
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_dai), 15e18),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(100e18, 5e18),
            type(uint48).max
        );
        _assertNoFlashEffects();
        assertEq(_usds.totalSupply(), 0, "Earlier conversion rolled back");
    }

    // Scenarios: BLREX-I13.
    function test_whenRepaymentTargetIsOutOfContext_reverts(uint8 condition_) public {
        uint8 condition = condition_ % 4;
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](condition == 1 ? 2 : 1);
        operations[0] = _swapExactOutput(
            condition == 2 ? address(_asset) : address(_dai),
            IExecutor.OutputTarget.FlashRepayment,
            condition == 3 ? 1 : 0,
            1e18
        );
        if (condition == 1) operations[1] = _convertDaiUsds(1);
        vm.expectRevert(IExecutor.BurnerLoansComposites_InvalidRepaymentTarget.selector);
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_dai), 15e18),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(condition == 0 ? 0 : 100e18, 0),
            type(uint48).max
        );
        _assertNoFlashEffects();
    }

    // Scenarios: BLRFL-C03.
    function test_givenReusableGrant_whenReplacedDuringLenderCollection_reverts()
        public
        givenReusableGrant
    {
        uint256 epochBefore = _auth.pairEpochs(_borrower, address(_executor));
        _dai.setCallbackFrom(
            address(_lender),
            address(this),
            abi.encodeCall(this.replaceGrant, ())
        );
        _dai.setCallbackPhases(false, true);
        _dai.setCallbackTransferRecipient(address(_lender));
        _dai.setBubbleCallbackFailure(true);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(100e18, 0),
            type(uint48).max
        );
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            epochBefore,
            "Grant replacement reverted"
        );
        assertEq(_position().depositedCollateral, 0, "Deposit reverted");
        _assertNoFlashEffects();
    }

    function replaceGrant() external {
        _approveOperator(_borrower, address(_executor), type(uint48).max);
    }

    // Scenarios: BLRFL-P09.
    function test_givenReusableGrant_whenOnlyTheLoanUsesDai() public givenReusableGrant {
        vm.expectCall(
            address(_lender),
            abi.encodeWithSelector(
                IERC3156FlashLender.flashLoan.selector,
                address(_executor),
                address(_dai),
                uint256(100e18)
            ),
            uint64(1)
        );
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(100e18, 0),
            type(uint48).max
        );
        assertEq(_position().depositedCollateral, 1, "Deposit settled");
        _assertNoFlashEffects();
    }

    // Scenarios: BLREX-P30.
    function test_givenOlderDebt_givenReusableGrant_whenFlashSwapClosesPosition()
        public
        givenOlderDebt
        givenReusableGrant
    {
        _lender.configure(5e18, MockCompositesFlashLender.Behavior.Normal);
        _adapter.setOutput(address(_ohm), 100e9);
        _adapter.setOutput(address(_dai), 105e18);
        uint256 walletBefore = _asset.balanceOf(_borrower);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](4);
        operations[0] = _swapExactInput(address(_dai), address(_ohm), 100e18, 100e9);
        operations[1] = _repay(100e9);
        operations[2] = IExecutor.Operation(
            IExecutor.OperationKind.Withdraw,
            abi.encode(
                IExecutor.Withdraw(
                    address(_asset),
                    2000e6,
                    address(_executor),
                    address(_asset),
                    2000e6
                )
            )
        );
        operations[3] = IExecutor.Operation(
            IExecutor.OperationKind.SwapExactOutput,
            abi.encode(
                IExecutor.SwapExactOutput(
                    address(_asset),
                    address(_dai),
                    IExecutor.OutputTarget.FlashRepayment,
                    0,
                    110e6,
                    hex"ab"
                )
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            new IExecutor.Funding[](0),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(100e18, 5e18),
            type(uint48).max
        );
        assertEq(_position().debtOhm, 0, "Entire OHM debt repaid");
        assertEq(_position().depositedCollateral, 0, "Collateral fully withdrawn");
        assertEq(
            _asset.balanceOf(_borrower),
            walletBefore + 1890e6,
            "Collateral leftover refunded"
        );
        assertEq(_dai.balanceOf(address(_lender)), 105e18, "Lender repaid before refund");
        assertEq(_dai.balanceOf(address(_executor)), 7e18, "Starting DAI preserved");
    }

    function _swapExactOutput(
        address tokenOut_,
        IExecutor.OutputTarget target_,
        uint256 amountOut_,
        uint256 maxAmountIn_
    ) private view returns (IExecutor.Operation memory) {
        return
            IExecutor.Operation(
                IExecutor.OperationKind.SwapExactOutput,
                abi.encode(
                    IExecutor.SwapExactOutput(
                        address(_usds),
                        tokenOut_,
                        target_,
                        amountOut_,
                        maxAmountIn_,
                        hex"ab"
                    )
                )
            );
    }

    function _roundTrip() private view returns (IExecutor.Operation[] memory operations) {
        operations = new IExecutor.Operation[](2);
        operations[0] = _convertDaiUsds(1);
        operations[1] = _convertUsdsToDai(1);
    }

    function _convertDaiUsds(uint256 amount_) private view returns (IExecutor.Operation memory) {
        return _convertDaiUsds(address(_dai), address(_usds), amount_);
    }

    function _convertUsdsToDai(uint256 amount_) private view returns (IExecutor.Operation memory) {
        return _convertDaiUsds(address(_usds), address(_dai), amount_);
    }

    function _swapExactInput(
        address input_,
        address output_,
        uint256 amount_,
        uint256 minimum_
    ) private pure returns (IExecutor.Operation memory) {
        return
            IExecutor.Operation(
                IExecutor.OperationKind.SwapExactInput,
                abi.encode(IExecutor.SwapExactInput(input_, output_, amount_, minimum_, hex"ab"))
            );
    }
}
