// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {BurnerLoansAuth} from "src/policies/burnerloans/BurnerLoansAuth.sol";
import {BurnerLoansCompositesGrantModesTest} from "./fixtures/BurnerLoansCompositesGrantModesTest.sol";
import {CompositesAccount} from "./fixtures/CompositesAccount.sol";
import {CoreCallbackToken} from "src/test/policies/BurnerLoansCore/fixtures/CoreCallbackToken.sol";

contract BurnerLoansCompositesExecuteCallbacksTest is BurnerLoansCompositesGrantModesTest {
    CoreCallbackToken internal _callbackToken;
    BurnerLoansAuth internal _replacement;

    function setUp() public override {
        super.setUp();
        _callbackToken = new CoreCallbackToken();
        _callbackToken.mint(_borrower, 1);
        vm.prank(_borrower);
        _callbackToken.approve(address(_executor), 1);
        vm.prank(_borrower);
        _asset.approve(address(_executor), type(uint256).max);
        // Make the token's nested account fully fundable and authorized before testing the entry guard.
        _asset.mint(address(_callbackToken), 1);
        vm.prank(address(_callbackToken));
        _asset.approve(address(_executor), 1);
        _approveOperatorForAsset(
            address(_callbackToken),
            address(_executor),
            type(uint48).max,
            address(_asset)
        );
    }

    function _inputs() internal view returns (IExecutor.Funding[] memory inputs) {
        inputs = new IExecutor.Funding[](2);
        inputs[0] = IExecutor.Funding(address(_callbackToken), 1);
        inputs[1] = IExecutor.Funding(address(_asset), 10);
    }

    // Scenarios: BLREX-O11.
    function test_whenLaterRefundSpendsEarlierOutput_reverts(
        bool inlineGrant_,
        bool multiple_,
        bool spendsRetainedBalance_
    ) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        // Of the five refunded raw units, spending one leaves four and spending six reaches the zero floor.
        uint256 spend = spendsRetainedBalance_ ? 6 : 1;
        uint256 observedReturn = spendsRetainedBalance_ ? 0 : 4;
        IExecutor.Funding[] memory funding = new IExecutor.Funding[](2);
        funding[0] = IExecutor.Funding(address(_asset), 15);
        funding[1] = IExecutor.Funding(address(_callbackToken), 1);
        IExecutor.Output[] memory outputs = new IExecutor.Output[](1);
        outputs[0] = IExecutor.Output(address(_asset), 5);
        vm.prank(_borrower);
        _asset.approve(address(this), spend);
        _callbackToken.setCallbackFrom(
            address(_executor),
            address(this),
            abi.encodeCall(this.spendRefund, (spend))
        );
        _callbackToken.setCallbackPhases(true, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientReturn.selector,
                address(_asset),
                5,
                observedReturn
            )
        );
        _executeGrantMode(inlineGrant_, signed, funding, _single(_deposit(10)), outputs);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
        assertEq(
            _position().depositedCollateral,
            0,
            "Final output failure restores earlier deposit"
        );
        assertEq(
            _asset.balanceOf(_borrower),
            10_000e6,
            "Both refunds and callback spending rolled back"
        );
        assertEq(
            _asset.balanceOf(_recipient),
            0,
            "Callback recipient receives no committed output"
        );
    }

    /// @dev Models an authorized spend during a token refund callback.
    function spendRefund(uint256 amount_) external {
        assertTrue(
            _asset.transferFrom(_borrower, _recipient, amount_),
            "Authorized callback spend succeeds"
        );
    }

    // Scenarios: BLREX-T15.
    function test_givenReusableGrant_whenLaterRefundCreditsSettledToken_reverts()
        public
        givenReusableGrant
    {
        _asset.mint(address(_executor), 17);
        _asset.mint(address(this), 1);
        IExecutor.Funding[] memory funding = new IExecutor.Funding[](2);
        funding[0] = IExecutor.Funding(address(_asset), 15);
        funding[1] = IExecutor.Funding(address(_callbackToken), 1);
        _callbackToken.setCallbackFrom(
            address(_executor),
            address(this),
            abi.encodeCall(this.creditSettledToken, ())
        );
        _callbackToken.setCallbackPhases(true, false);
        _callbackToken.setBubbleCallbackFailure(true);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_UnsettledBalance.selector,
                address(_asset),
                1
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            funding,
            _single(_deposit(10)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(_asset.balanceOf(address(_executor)), 17, "Protected balance preserved");
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Caller inputs restored");
        assertEq(_callbackToken.balanceOf(_borrower), 1, "Second token input restored");
        assertEq(_asset.balanceOf(address(this)), 1, "Callback credit restored");
        assertEq(_position().depositedCollateral, 0, "Earlier deposit rolled back");
    }

    function creditSettledToken() external {
        assertTrue(_asset.transfer(address(_executor), 1), "Callback credit succeeds");
    }

    // Scenarios: BLREX-L09.
    function test_givenReusableGrant_whenOwnerPausesDuringRefund_reverts()
        public
        givenReusableGrant
    {
        uint48 transitionAt = _executor.lastTransitionAt();
        _callbackToken.setCallbackFrom(
            address(_executor),
            address(this),
            abi.encodeCall(this.pauseExecutor, ())
        );
        _callbackToken.setCallbackPhases(true, false);
        _callbackToken.setBubbleCallbackFailure(true);
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vm.prank(_borrower);
        _executor.execute(
            _inputs(),
            _single(_deposit(10)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertTrue(
            _executor.isEnabled(),
            "Owner callback cannot change enablement during execution"
        );
        assertEq(
            _executor.lastTransitionAt(),
            transitionAt,
            "Failed pause preserves transition time"
        );
        assertEq(_position().depositedCollateral, 0, "Callback failure rolls back lending");
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Callback failure restores funding");
    }

    function pauseExecutor() external {
        _executor.disable("");
    }

    // Scenarios: BLREX-C09.
    function test_whenGrantIsReplacedDuringRefund_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public {
        CompositesAccount account = _grantReplacementAccount();
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        grant.multiple = multiple_;
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        _armGrantReplacement(account, grant);

        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(address(_callbackToken));
        if (inlineGrant_) {
            account.run(
                _executor,
                _inputs(),
                _single(_deposit(10)),
                new IExecutor.Output[](0),
                signed
            );
        } else {
            account.approveGrantAndRun(
                _auth,
                grant,
                _executor,
                _inputs(),
                _single(_deposit(10)),
                new IExecutor.Output[](0)
            );
        }
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Both grant writes rolled back"
        );
        assertEq(_position().depositedCollateral, 0, "Deposit rolled back");
        assertEq(_asset.balanceOf(_borrower), 10, "Caller collateral restored");
        assertEq(_callbackToken.balanceOf(_borrower), 1, "Caller callback token restored");
    }

    // Scenarios: BLREX-C10.
    function test_givenOlderDebt_whenSignedRepaymentGrantIsReplaced_reverts(bool multiple_) public {
        CompositesAccount account = _grantReplacementAccount();
        _asset.mint(_borrower, 2100e6);
        vm.startPrank(_borrower);
        _asset.approve(address(_core), type(uint256).max);
        _collateral.depositCollateral(address(_asset), 2000e6, _borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 100e6, address(0));
        vm.stopPrank();
        vm.roll(vm.getBlockNumber() + 1);

        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        grant.multiple = multiple_;
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        _armGrantReplacement(account, grant);
        IExecutor.Funding[] memory funding = new IExecutor.Funding[](2);
        funding[0] = IExecutor.Funding(address(_callbackToken), 1);
        funding[1] = IExecutor.Funding(address(_ohm), 100e9);
        IExecutor.Operation[] memory operations = _single(_repay(100e9));

        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(address(_callbackToken));
        account.run(_executor, funding, operations, new IExecutor.Output[](0), signed);
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Accepted and replacement grants rolled back"
        );
        assertEq(_position().debtOhm, 100e9, "Repayment rolled back");
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Inventory principal restored");
        assertEq(_ohm.balanceOf(_borrower), 100e9, "Repayment funding restored");
        assertEq(_callbackToken.balanceOf(_borrower), 1, "Callback token restored");
    }

    function _grantReplacementAccount() private returns (CompositesAccount account) {
        account = new CompositesAccount(address(_callbackToken), vm.addr(_SIGNER_KEY));
        _borrower = address(account);
        _asset.mint(_borrower, 10);
        _callbackToken.mint(_borrower, 1);
        _callbackToken.setCallbackPhases(true, false);
        _callbackToken.setBubbleCallbackFailure(true);
    }

    function _armGrantReplacement(
        CompositesAccount account_,
        IOperatorAuth.Grant memory grant_
    ) private {
        // Struct assignment aliases memory in Solidity. The external ABI encoding copies
        // the incremented epoch into the callback after the original is signed.
        uint256 originalEpoch = grant_.pairEpoch;
        grant_.pairEpoch = originalEpoch + 1;
        bytes memory replacement = abi.encodeCall(account_.approveGrant, (_auth, grant_));
        grant_.pairEpoch = originalEpoch;
        _callbackToken.setCallbackFrom(address(_executor), address(account_), replacement);
        vm.expectCall(address(account_), replacement, uint64(1));
    }

    function _armNestedExecution(bool onTransfer_, bool onTransferFrom_) internal {
        _callbackToken.setCallbackFrom(
            address(_executor),
            address(_executor),
            abi.encodeCall(
                IExecutor.execute,
                (
                    _funding(address(_asset), 1),
                    _single(_deposit(1)),
                    new IExecutor.Output[](0),
                    IExecutor.FlashLoan(0, 0),
                    type(uint48).max
                )
            )
        );
        _callbackToken.setCallbackPhases(onTransfer_, onTransferFrom_);
    }

    // Scenarios: BLREX-C07.
    function test_whenFundingReentersSignedEntry(bool multiple_) public {
        IExecutor.SignedGrant memory outerGrant = _prepareGrantMode(false, _grant(multiple_));
        CompositesAccount account = new CompositesAccount(
            address(_callbackToken),
            vm.addr(_SIGNER_KEY)
        );
        _asset.mint(address(account), 1);
        IExecutor.SignedGrant memory signed = _signedGrant(
            _operatorGrant(address(account), address(_executor), type(uint48).max)
        );
        _callbackToken.setCallbackFrom(
            address(_executor),
            address(account),
            abi.encodeCall(
                account.run,
                (
                    _executor,
                    _funding(address(_asset), 1),
                    _single(_deposit(1)),
                    new IExecutor.Output[](0),
                    signed
                )
            )
        );
        _callbackToken.setCallbackPhases(false, true);
        _executeGrantMode(
            false,
            outerGrant,
            _inputs(),
            _single(_deposit(10)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _callbackToken.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "Existing-authority entry blocks a fully signed nested entry"
        );
        assertEq(
            _position().depositedCollateral,
            10,
            "Outer deposit applies once across both entry points"
        );
        assertEq(
            _auth.pairEpochs(address(account), address(_executor)),
            0,
            "Nested signed grant is not consumed"
        );
    }

    // Scenarios: BLREX-C08.
    function test_whenSignedEntryFundingReentersExistingAuthorityEntry() public {
        _borrower = vm.addr(_SIGNER_KEY);
        _asset.mint(_borrower, 10);
        _callbackToken.mint(_borrower, 1);
        vm.startPrank(_borrower);
        _asset.approve(address(_executor), 10);
        _callbackToken.approve(address(_executor), 1);
        vm.stopPrank();
        _armNestedExecution(false, true);
        IExecutor.SignedGrant memory signed = _signedGrant(
            _operatorGrant(_borrower, address(_executor), type(uint48).max)
        );
        vm.prank(_borrower);
        _executor.executeWithGrant(
            _inputs(),
            _single(_deposit(10)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(
            _callbackToken.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "Signed entry holds the shared guard throughout funding"
        );
        assertEq(_position().depositedCollateral, 10, "Signed outer action completes exactly once");
        assertEq(
            _lens.getPosition(address(_asset), address(_callbackToken)).depositedCollateral,
            0,
            "Nested existing-authority action applies no deposit"
        );
    }

    // Scenarios: BLREX-C01, BLREX-C08.
    function test_whenFundingReentryCaught(bool inlineGrant_, bool multiple_) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _armNestedExecution(false, true);
        vm.expectCall(
            address(_callbackToken),
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                _borrower,
                address(_executor),
                1
            ),
            1
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _inputs(),
            _single(_deposit(10)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _callbackToken.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "Funded nested execution reaches entry guard"
        );
        assertEq(_position().depositedCollateral, 10, "Outer deposit applies exactly once");
        assertEq(
            _lens.getPosition(address(_asset), address(_callbackToken)).depositedCollateral,
            0,
            "Nested account gets no collateral"
        );
        assertEq(_callbackToken.balanceOf(_borrower), 1, "Unused callback token refunded");
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-C02.
    function test_whenFundingReentryPropagated_reverts(bool inlineGrant_, bool multiple_) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _armNestedExecution(false, true);
        _callbackToken.setBubbleCallbackFailure(true);
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _inputs(),
            _single(_deposit(10)),
            new IExecutor.Output[](0)
        );
        assertEq(_position().depositedCollateral, 0, "Propagated callback creates no position");
        assertEq(_callbackToken.balanceOf(_borrower), 1, "Input transfer restored");
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Other input untouched");
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-C03.
    function test_whenRefundReentryCaught(bool inlineGrant_, bool multiple_) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _armNestedExecution(true, false);
        vm.expectCall(
            address(_callbackToken),
            abi.encodeWithSignature("transfer(address,uint256)", _borrower, 1),
            1
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _inputs(),
            _single(_deposit(10)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _callbackToken.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "Guard remains active during refund"
        );
        assertEq(_position().depositedCollateral, 10, "Outer action completes once");
        assertEq(_callbackToken.balanceOf(address(_executor)), 0, "Refund completes once");
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-C04.
    function test_whenAuthRotatesAwayAndBackDuringRefund_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _replacement = new BurnerLoansAuth(address(_kernel), address(_core));
        uint256 epochBefore = _currentAuthEpoch();
        _callbackToken.setCallbackFrom(
            address(_executor),
            address(this),
            abi.encodeCall(this.rotateAuth, ())
        );
        _callbackToken.setCallbackPhases(true, false);
        vm.expectRevert(IExecutor.BurnerLoansComposites_AuthorityChanged.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _inputs(),
            _single(_deposit(10)),
            new IExecutor.Output[](0)
        );
        assertEq(_currentAuthEpoch(), epochBefore, "Auth rotation rolled back");
        assertEq(_position().depositedCollateral, 0, "Earlier action rolled back");
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Wallet funding restored");
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    /// @dev Called only as a test-token callback; this fixture already holds governance ADMIN.
    function rotateAuth() external {
        _core.setAuth(address(_replacement));
        _core.setAuth(address(_auth));
    }

    // Scenarios: BLREX-C05.
    function test_whenOriginalGrantCancelledDuringRefund_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _callbackToken.setCallbackFrom(
            address(_executor),
            address(this),
            abi.encodeCall(this.cancelGrant, ())
        );
        _callbackToken.setCallbackPhases(true, false);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _inputs(),
            _single(_deposit(10)),
            new IExecutor.Output[](0)
        );
        _assertGrantAfterRevert(inlineGrant_, multiple_);
        assertEq(
            _position().depositedCollateral,
            0,
            "Cancelled authority cannot complete earlier lending"
        );
    }

    /// @dev The account owner requests cancellation and Auth sees the original borrower.
    function cancelGrant() external {
        _account.cancelGrant(_auth, address(_executor));
    }
}
