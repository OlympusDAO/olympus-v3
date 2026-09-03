// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockRecipientBalanceDecreasingToken} from "src/test/libraries/fixtures/MockRecipientBalanceDecreasingToken.sol";
import {TransferHelperHarness} from "src/test/libraries/fixtures/TransferHelperHarness.sol";
import {MockERC20FeeOnTransfer} from "src/test/mocks/MockERC20FeeOnTransfer.sol";

contract TransferHelperSafeTransferFromExactTest is Test {
    address internal _sender;
    address internal _recipient;
    address internal _feeRecipient;

    MockERC20 internal _token;
    TransferHelperHarness internal _helper;

    function setUp() public {
        _sender = makeAddr("sender");
        _recipient = makeAddr("recipient");
        _feeRecipient = makeAddr("feeRecipient");

        _token = new MockERC20("Token", "TKN", 18);
        _helper = new TransferHelperHarness();
    }

    function test_givenRecipientHasExistingBalance_whenTransferIsExact(
        uint256 amount_,
        uint256 existingBalance_
    ) public {
        existingBalance_ = bound(existingBalance_, 0, type(uint256).max - 1);
        amount_ = bound(amount_, 1, type(uint256).max - existingBalance_);
        _token.mint(_sender, amount_);
        _token.mint(_recipient, existingBalance_);
        vm.prank(_sender);
        _token.approve(address(_helper), amount_);

        uint256 balanceBefore = _helper.safeTransferFromExact(_token, _sender, _recipient, amount_);

        assertEq(balanceBefore, existingBalance_, "returned recipient balance before transfer");
        assertEq(_token.balanceOf(_sender), 0, "sender balance after transfer");
        assertEq(
            _token.balanceOf(_recipient),
            existingBalance_ + amount_,
            "recipient balance after transfer"
        );
    }

    function test_whenAmountIsZero_preservesBalances() public {
        uint256 existingBalance = 7e18;
        _token.mint(_recipient, existingBalance);

        uint256 balanceBefore = _helper.safeTransferFromExact(_token, _sender, _recipient, 0);

        assertEq(balanceBefore, existingBalance, "returned recipient balance before transfer");
        assertEq(_token.balanceOf(_sender), 0, "sender balance after transfer");
        assertEq(_token.balanceOf(_recipient), existingBalance, "recipient balance after transfer");
    }

    function test_whenAmountIsMaximum_transfersExactAmount() public {
        uint256 amount = type(uint256).max;
        _token.mint(_sender, amount);
        vm.prank(_sender);
        _token.approve(address(_helper), amount);

        uint256 balanceBefore = _helper.safeTransferFromExact(_token, _sender, _recipient, amount);

        assertEq(balanceBefore, 0, "returned recipient balance before transfer");
        assertEq(_token.balanceOf(_sender), 0, "sender balance after transfer");
        assertEq(_token.balanceOf(_recipient), amount, "recipient balance after transfer");
    }

    function test_givenFeeOnTransferToken_reverts() public {
        MockERC20FeeOnTransfer feeToken = new MockERC20FeeOnTransfer(
            "Fee Token",
            "FEE",
            _feeRecipient
        );
        uint256 amount = 100e18;
        uint256 existingBalance = 7e18;
        uint256 receivedAmount = 90e18;
        feeToken.mint(_sender, amount);
        feeToken.mint(_recipient, existingBalance);
        vm.prank(_sender);
        feeToken.approve(address(_helper), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                TransferHelper.TransferHelper_InexactTransferFrom.selector,
                address(feeToken),
                _recipient,
                amount,
                receivedAmount
            )
        );
        _helper.safeTransferFromExact(ERC20(address(feeToken)), _sender, _recipient, amount);

        assertEq(feeToken.balanceOf(_sender), amount, "sender balance rolled back");
        assertEq(feeToken.balanceOf(_recipient), existingBalance, "recipient balance rolled back");
        assertEq(feeToken.balanceOf(_feeRecipient), 0, "fee recipient balance rolled back");
    }

    function test_givenRecipientBalanceDecreases_revertsAndRollsBack() public {
        MockRecipientBalanceDecreasingToken decreasingToken = new MockRecipientBalanceDecreasingToken();
        decreasingToken.mint(_recipient, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                TransferHelper.TransferHelper_InexactTransferFrom.selector,
                address(decreasingToken),
                _recipient,
                1,
                0
            )
        );
        _helper.safeTransferFromExact(ERC20(address(decreasingToken)), _sender, _recipient, 1);

        assertEq(decreasingToken.balanceOf(_recipient), 1, "recipient balance rolled back");
    }
}
