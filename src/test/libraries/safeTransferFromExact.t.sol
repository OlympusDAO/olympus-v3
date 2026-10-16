// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test actions assert their effects directly; return values are intentionally unused.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {Vm} from "@forge-std-1.16.2/Vm.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {ERC20Mock} from "@openzeppelin-5.7.0/mocks/token/ERC20Mock.sol";
import {MockERC20BalanceQueryFailure} from "src/test/libraries/fixtures/MockERC20BalanceQueryFailure.sol";
import {MockERC20ConfiguredReturnData} from "src/test/libraries/fixtures/MockERC20ConfiguredReturnData.sol";
import {MockERC20FalseAfterTransfer} from "src/test/libraries/fixtures/MockERC20FalseAfterTransfer.sol";
import {MockERC20NoReturn} from "src/test/libraries/fixtures/MockERC20NoReturn.sol";
import {MockERC20Overcredit} from "src/test/libraries/fixtures/MockERC20Overcredit.sol";
import {MockERC20RevertingAfterTransfer} from "src/test/libraries/fixtures/MockERC20RevertingAfterTransfer.sol";
import {SafeERC20Harness} from "src/test/libraries/fixtures/SafeERC20Harness.sol";
import {MockERC20FeeOnTransfer} from "src/test/mocks/MockERC20FeeOnTransfer.sol";
import {MockRecipientBalanceDecreasingToken} from "src/test/mocks/MockRecipientBalanceDecreasingToken.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

contract SafeERC20ExactSafeTransferFromExactTest is Test {
    error CallbackRejected();

    uint256 internal constant _AMOUNT = 40;
    uint256 internal constant _EXISTING_BALANCE = 7e18;

    address internal _sender;
    address internal _recipient;
    address internal _feeRecipient;

    ERC20Mock internal _token;
    SafeERC20Harness internal _helper;

    function setUp() public {
        _sender = makeAddr("sender");
        _recipient = makeAddr("recipient");
        _feeRecipient = makeAddr("feeRecipient");

        _token = new ERC20Mock();
        _helper = new SafeERC20Harness();
        vm.label(address(_token), "ERC20Mock");
        vm.label(address(_helper), "SafeERC20Harness");
    }

    // Scenarios: EXACT-P01.
    function test_givenRecipientHasExistingBalance_whenTransferIsExact(
        address caller_,
        uint256 amount_,
        uint256 existingBalance_
    ) public {
        existingBalance_ = bound(existingBalance_, 0, type(uint256).max - 1);
        amount_ = bound(amount_, 1, type(uint256).max - existingBalance_);
        _token.mint(_sender, amount_);
        _token.mint(_recipient, existingBalance_);
        _approve(_token, amount_);

        vm.recordLogs();
        vm.prank(caller_);
        uint256 balanceBefore = _helper.safeTransferFromExact(_token, _sender, _recipient, amount_);

        assertEq(balanceBefore, existingBalance_, "returned recipient balance before transfer");
        assertEq(_token.balanceOf(_sender), 0, "sender balance after transfer");
        assertEq(
            _token.balanceOf(_recipient),
            existingBalance_ + amount_,
            "recipient balance after transfer"
        );
        assertEq(
            _token.allowance(_sender, address(_helper)),
            amount_ == type(uint256).max ? type(uint256).max : 0,
            "allowance after transfer"
        );
        _assertSingleTransferLog(address(_token), _sender, _recipient, amount_);
    }

    // Scenarios: EXACT-P01.
    function test_whenAmountIsZero_preservesBalances(address caller_) public {
        uint256 existingBalance = _EXISTING_BALANCE;
        _token.mint(_recipient, existingBalance);

        vm.recordLogs();
        vm.prank(caller_);
        uint256 balanceBefore = _helper.safeTransferFromExact(_token, _sender, _recipient, 0);

        assertEq(balanceBefore, existingBalance, "returned recipient balance before transfer");
        assertEq(_token.balanceOf(_sender), 0, "sender balance after transfer");
        assertEq(_token.balanceOf(_recipient), existingBalance, "recipient balance after transfer");
        assertEq(_token.allowance(_sender, address(_helper)), 0, "zero allowance stays zero");
        _assertSingleTransferLog(address(_token), _sender, _recipient, 0);
    }

    // Scenarios: EXACT-P01.
    function test_whenAmountIsOne_transfersExactAmount(address caller_) public {
        _token.mint(_sender, 1);
        _approve(_token, 1);

        vm.recordLogs();
        vm.prank(caller_);
        uint256 balanceBefore = _helper.safeTransferFromExact(_token, _sender, _recipient, 1);

        assertEq(balanceBefore, 0, "returned recipient balance before transfer");
        assertEq(_token.balanceOf(_sender), 0, "sender balance after transfer");
        assertEq(_token.balanceOf(_recipient), 1, "recipient balance after transfer");
        assertEq(_token.allowance(_sender, address(_helper)), 0, "allowance consumed");
        _assertSingleTransferLog(address(_token), _sender, _recipient, 1);
    }

    // Scenarios: EXACT-P01.
    function test_whenAmountIsMaximum_transfersExactAmount(address caller_) public {
        uint256 amount = type(uint256).max;
        _token.mint(_sender, amount);
        _approve(_token, amount);

        vm.recordLogs();
        vm.prank(caller_);
        uint256 balanceBefore = _helper.safeTransferFromExact(_token, _sender, _recipient, amount);

        assertEq(balanceBefore, 0, "returned recipient balance before transfer");
        assertEq(_token.balanceOf(_sender), 0, "sender balance after transfer");
        assertEq(_token.balanceOf(_recipient), amount, "recipient balance after transfer");
        assertEq(
            _token.allowance(_sender, address(_helper)),
            type(uint256).max,
            "maximum allowance remains infinite"
        );
        _assertSingleTransferLog(address(_token), _sender, _recipient, amount);
    }

    // Scenarios: EXACT-I01.
    function test_givenFeeOnTransferToken_reverts(address caller_) public {
        MockERC20FeeOnTransfer feeToken = new MockERC20FeeOnTransfer(
            "Fee Token",
            "FEE",
            _feeRecipient
        );
        uint256 amount = 100e18;
        uint256 existingBalance = _EXISTING_BALANCE;
        uint256 receivedAmount = 90e18;
        feeToken.mint(_sender, amount);
        feeToken.mint(_recipient, existingBalance);
        _approve(IERC20(address(feeToken)), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(feeToken),
                _recipient,
                amount,
                receivedAmount
            )
        );
        vm.prank(caller_);
        _helper.safeTransferFromExact(IERC20(address(feeToken)), _sender, _recipient, amount);

        assertEq(feeToken.balanceOf(_sender), amount, "sender balance rolled back");
        assertEq(feeToken.balanceOf(_recipient), existingBalance, "recipient balance rolled back");
        assertEq(feeToken.balanceOf(_feeRecipient), 0, "fee recipient balance rolled back");
        assertEq(
            feeToken.allowance(_sender, address(_helper)),
            amount,
            "allowance consumption rolled back"
        );
    }

    // Scenarios: EXACT-I01.
    function test_givenTokenOvercreditsRecipient_revertsAndRollsBack(address caller_) public {
        MockERC20Overcredit overcreditToken = new MockERC20Overcredit();
        overcreditToken.mint(_sender, _AMOUNT + 1);
        _approve(overcreditToken, _AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(overcreditToken),
                _recipient,
                _AMOUNT,
                _AMOUNT + 1
            )
        );
        vm.prank(caller_);
        _helper.safeTransferFromExact(overcreditToken, _sender, _recipient, _AMOUNT);

        assertEq(overcreditToken.balanceOf(_sender), _AMOUNT + 1, "sender balance rolled back");
        assertEq(overcreditToken.balanceOf(_recipient), 0, "recipient balance rolled back");
        assertEq(
            overcreditToken.allowance(_sender, address(_helper)),
            _AMOUNT,
            "allowance consumption rolled back"
        );
    }

    // Scenarios: EXACT-I01.
    function test_givenRecipientBalanceDecreases_revertsAndRollsBack(address caller_) public {
        MockRecipientBalanceDecreasingToken decreasingToken = new MockRecipientBalanceDecreasingToken();
        decreasingToken.mint(_recipient, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(decreasingToken),
                _recipient,
                1,
                0
            )
        );
        vm.prank(caller_);
        _helper.safeTransferFromExact(decreasingToken, _sender, _recipient, 1);

        assertEq(decreasingToken.balanceOf(_recipient), 1, "recipient balance rolled back");
    }

    // Scenarios: EXACT-I01.
    function test_givenRecipientBalanceDecreases_whenAmountIsZero_revertsAndRollsBack(
        address caller_
    ) public {
        MockRecipientBalanceDecreasingToken decreasingToken = new MockRecipientBalanceDecreasingToken();
        decreasingToken.mint(_recipient, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(decreasingToken),
                _recipient,
                0,
                0
            )
        );
        vm.prank(caller_);
        _helper.safeTransferFromExact(decreasingToken, _sender, _recipient, 0);

        assertEq(decreasingToken.balanceOf(_recipient), 1, "recipient balance rolled back");
    }

    // Scenarios: EXACT-I02.
    function test_whenSenderEqualsRecipient_revertsAndRollsBack(
        address caller_,
        uint256 amount_
    ) public {
        amount_ = bound(amount_, 1, type(uint256).max);
        _token.mint(_sender, amount_);
        _approve(_token, amount_);

        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(_token),
                _sender,
                amount_,
                0
            )
        );
        vm.prank(caller_);
        _helper.safeTransferFromExact(_token, _sender, _sender, amount_);

        assertEq(_token.balanceOf(_sender), amount_, "sender balance rolled back");
        assertEq(
            _token.allowance(_sender, address(_helper)),
            amount_,
            "allowance consumption rolled back"
        );
    }

    // Scenarios: EXACT-T05.
    function test_whenTransferFromReturnsNoDataAfterExactTransfer_succeeds(
        address caller_,
        uint256 amount_
    ) public {
        amount_ = bound(amount_, 1, type(uint256).max);
        MockERC20NoReturn noReturnToken = new MockERC20NoReturn();
        noReturnToken.mint(_sender, amount_);
        _approve(noReturnToken, amount_);

        vm.recordLogs();
        vm.prank(caller_);
        uint256 balanceBefore = _helper.safeTransferFromExact(
            noReturnToken,
            _sender,
            _recipient,
            amount_
        );

        assertEq(balanceBefore, 0, "returned recipient balance before transfer");
        assertEq(noReturnToken.balanceOf(_sender), 0, "sender balance after transfer");
        assertEq(noReturnToken.balanceOf(_recipient), amount_, "recipient balance after transfer");
        assertEq(
            noReturnToken.allowance(_sender, address(_helper)),
            amount_ == type(uint256).max ? type(uint256).max : 0,
            "allowance after transfer"
        );
        _assertSingleTransferLog(address(noReturnToken), _sender, _recipient, amount_);
    }

    // Scenarios: EXACT-T06.
    function test_whenTransferFromReturnsShortData_revertsAndRollsBack(
        address caller_,
        uint256 returnLength_
    ) public {
        returnLength_ = bound(returnLength_, 1, 31);
        bytes memory returnData = new bytes(returnLength_);
        returnData[returnLength_ - 1] = 0x01;
        MockERC20ConfiguredReturnData malformedToken = new MockERC20ConfiguredReturnData(
            returnData
        );
        malformedToken.mint(_sender, _AMOUNT);
        _approve(malformedToken, _AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, malformedToken)
        );
        vm.prank(caller_);
        _helper.safeTransferFromExact(malformedToken, _sender, _recipient, _AMOUNT);

        _assertExactTransferRollback(malformedToken, _AMOUNT);
    }

    // Scenarios: EXACT-T06.
    function test_whenTransferFromReturnsNoncanonicalWord_revertsAndRollsBack(
        address caller_,
        uint256 returnWord_
    ) public {
        vm.assume(returnWord_ != 1);
        MockERC20ConfiguredReturnData malformedToken = new MockERC20ConfiguredReturnData(
            abi.encode(returnWord_)
        );
        malformedToken.mint(_sender, _AMOUNT);
        _approve(malformedToken, _AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, malformedToken)
        );
        vm.prank(caller_);
        _helper.safeTransferFromExact(malformedToken, _sender, _recipient, _AMOUNT);

        _assertExactTransferRollback(malformedToken, _AMOUNT);
    }

    // Scenarios: EXACT-T01.
    function test_whenTransferFromReturnsFalse_revertsAndRollsBack(address caller_) public {
        MockERC20FalseAfterTransfer falseToken = new MockERC20FalseAfterTransfer();
        falseToken.mint(_sender, _AMOUNT);
        _approve(falseToken, _AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, falseToken)
        );
        vm.prank(caller_);
        _helper.safeTransferFromExact(falseToken, _sender, _recipient, _AMOUNT);

        _assertExactTransferRollback(falseToken, _AMOUNT);
    }

    // Scenarios: EXACT-T04.
    function test_whenTransferFromReverts_bubblesAndRollsBack(address caller_) public {
        MockERC20RevertingAfterTransfer revertingToken = new MockERC20RevertingAfterTransfer();
        revertingToken.mint(_sender, _AMOUNT);
        _approve(revertingToken, _AMOUNT);

        vm.expectRevert(MockERC20RevertingAfterTransfer.TransferRejected.selector);
        vm.prank(caller_);
        _helper.safeTransferFromExact(revertingToken, _sender, _recipient, _AMOUNT);

        _assertExactTransferRollback(revertingToken, _AMOUNT);
    }

    // Scenarios: EXACT-T02.
    function test_givenPreTransferBalanceQueryReverts_bubblesWithoutTransfer(
        address caller_
    ) public {
        MockERC20BalanceQueryFailure queryToken = new MockERC20BalanceQueryFailure();
        queryToken.mint(_sender, _AMOUNT);
        _approve(queryToken, _AMOUNT);
        queryToken.setBalanceQueryFailure(
            _recipient,
            0,
            MockERC20BalanceQueryFailure.Failure.Revert
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                MockERC20BalanceQueryFailure.BalanceQueryFailed.selector,
                _recipient
            )
        );
        vm.prank(caller_);
        _helper.safeTransferFromExact(queryToken, _sender, _recipient, _AMOUNT);

        queryToken.setBalanceQueryFailure(_recipient, 0, MockERC20BalanceQueryFailure.Failure.None);
        _assertExactTransferRollback(queryToken, _AMOUNT);
    }

    // Scenarios: EXACT-T02.
    function test_givenPreTransferBalanceQueryReturnsMalformedData_revertsWithoutTransfer(
        address caller_,
        bool emptyData_
    ) public {
        MockERC20BalanceQueryFailure queryToken = new MockERC20BalanceQueryFailure();
        queryToken.mint(_sender, _AMOUNT);
        _approve(queryToken, _AMOUNT);
        queryToken.setBalanceQueryFailure(
            _recipient,
            0,
            emptyData_
                ? MockERC20BalanceQueryFailure.Failure.EmptyData
                : MockERC20BalanceQueryFailure.Failure.ShortData
        );

        vm.expectRevert(bytes(""));
        vm.prank(caller_);
        _helper.safeTransferFromExact(queryToken, _sender, _recipient, _AMOUNT);

        queryToken.setBalanceQueryFailure(_recipient, 0, MockERC20BalanceQueryFailure.Failure.None);
        _assertExactTransferRollback(queryToken, _AMOUNT);
    }

    // Scenarios: EXACT-T02.
    function test_whenTokenHasNoCode_revertsBeforeTransfer(address caller_) public {
        address token = makeAddr("tokenWithoutCode");

        vm.expectRevert(bytes(""));
        vm.prank(caller_);
        _helper.safeTransferFromExact(IERC20(token), _sender, _recipient, _AMOUNT);
    }

    // Scenarios: EXACT-T03.
    function test_givenPostTransferBalanceQueryReverts_bubblesAndRollsBack(address caller_) public {
        MockERC20BalanceQueryFailure queryToken = new MockERC20BalanceQueryFailure();
        queryToken.mint(_sender, _AMOUNT);
        _approve(queryToken, _AMOUNT);
        queryToken.setBalanceQueryFailure(
            _recipient,
            _AMOUNT,
            MockERC20BalanceQueryFailure.Failure.Revert
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                MockERC20BalanceQueryFailure.BalanceQueryFailed.selector,
                _recipient
            )
        );
        vm.prank(caller_);
        _helper.safeTransferFromExact(queryToken, _sender, _recipient, _AMOUNT);

        _assertExactTransferRollback(queryToken, _AMOUNT);
    }

    // Scenarios: EXACT-T03.
    function test_givenPostTransferBalanceQueryReturnsMalformedData_revertsAndRollsBack(
        address caller_,
        bool emptyData_
    ) public {
        MockERC20BalanceQueryFailure queryToken = new MockERC20BalanceQueryFailure();
        queryToken.mint(_sender, _AMOUNT);
        _approve(queryToken, _AMOUNT);
        queryToken.setBalanceQueryFailure(
            _recipient,
            _AMOUNT,
            emptyData_
                ? MockERC20BalanceQueryFailure.Failure.EmptyData
                : MockERC20BalanceQueryFailure.Failure.ShortData
        );

        vm.expectRevert(bytes(""));
        vm.prank(caller_);
        _helper.safeTransferFromExact(queryToken, _sender, _recipient, _AMOUNT);

        _assertExactTransferRollback(queryToken, _AMOUNT);
    }

    // Scenarios: EXACT-C01.
    function test_givenCallbackOvercreditsRecipient_revertsAndRollsBack(address caller_) public {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        callbackToken.mint(_sender, _AMOUNT);
        _approve(callbackToken, _AMOUNT);
        callbackToken.setCallbackFrom(
            address(_helper),
            address(this),
            abi.encodeWithSelector(
                this.mintRecipientFromCallback.selector,
                callbackToken,
                _recipient
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(callbackToken),
                _recipient,
                _AMOUNT,
                _AMOUNT + 1
            )
        );
        vm.prank(caller_);
        _helper.safeTransferFromExact(callbackToken, _sender, _recipient, _AMOUNT);

        _assertExactTransferRollback(callbackToken, _AMOUNT);
        assertTrue(callbackToken.callbackEnabled(), "callback state rolled back");
    }

    // Scenarios: EXACT-C01.
    function test_givenCallbackFailureIsCaught_whenTransferIsExact_succeeds(
        address caller_
    ) public {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        callbackToken.mint(_sender, _AMOUNT);
        _approve(callbackToken, _AMOUNT);
        callbackToken.setCallbackFrom(
            address(_helper),
            address(this),
            abi.encodeWithSelector(this.revertFromCallback.selector)
        );

        vm.recordLogs();
        vm.prank(caller_);
        uint256 balanceBefore = _helper.safeTransferFromExact(
            callbackToken,
            _sender,
            _recipient,
            _AMOUNT
        );

        assertEq(balanceBefore, 0, "returned recipient balance before transfer");
        assertEq(callbackToken.balanceOf(_sender), 0, "sender balance after transfer");
        assertEq(callbackToken.balanceOf(_recipient), _AMOUNT, "recipient balance after transfer");
        assertFalse(callbackToken.callbackSucceeded(), "callback failure is recorded");
        assertEq(
            callbackToken.callbackRevertSelector(),
            CallbackRejected.selector,
            "callback revert selector is recorded"
        );
        _assertSingleTransferLog(address(callbackToken), _sender, _recipient, _AMOUNT);
    }

    // Scenarios: EXACT-C01.
    function test_givenCallbackFailureIsPropagated_bubblesAndRollsBack(address caller_) public {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        callbackToken.mint(_sender, _AMOUNT);
        _approve(callbackToken, _AMOUNT);
        callbackToken.setCallbackFrom(
            address(_helper),
            address(this),
            abi.encodeWithSelector(this.revertFromCallback.selector)
        );
        callbackToken.setBubbleCallbackFailure(true);

        vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
        vm.prank(caller_);
        _helper.safeTransferFromExact(callbackToken, _sender, _recipient, _AMOUNT);

        _assertExactTransferRollback(callbackToken, _AMOUNT);
        assertTrue(callbackToken.callbackEnabled(), "callback state rolled back");
    }

    function mintRecipientFromCallback(ReentrantFeeToken token_, address recipient_) external {
        token_.mint(recipient_, 1);
    }

    function revertFromCallback() external pure {
        revert CallbackRejected();
    }

    function _approve(IERC20 token_, uint256 amount_) internal {
        vm.prank(_sender);
        token_.approve(address(_helper), amount_);
    }

    function _assertExactTransferRollback(IERC20 token_, uint256 amount_) internal view {
        assertEq(token_.balanceOf(_sender), amount_, "sender balance rolled back");
        assertEq(token_.balanceOf(_recipient), 0, "recipient balance rolled back");
        assertEq(
            token_.allowance(_sender, address(_helper)),
            amount_,
            "allowance consumption rolled back"
        );
    }

    function _assertSingleTransferLog(
        address token_,
        address sender_,
        address recipient_,
        uint256 amount_
    ) internal view {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "one token transfer event emitted");
        assertEq(logs[0].emitter, token_, "transfer event emitter");
        assertEq(logs[0].topics.length, 3, "transfer event topic count");
        assertEq(logs[0].topics[0], IERC20.Transfer.selector, "transfer event signature");
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(sender_))), "transfer event sender");
        assertEq(
            logs[0].topics[2],
            bytes32(uint256(uint160(recipient_))),
            "transfer event recipient"
        );
        assertEq(abi.decode(logs[0].data, (uint256)), amount_, "transfer event amount");
    }
}

// forge-lint: disable-end(unused-return)
