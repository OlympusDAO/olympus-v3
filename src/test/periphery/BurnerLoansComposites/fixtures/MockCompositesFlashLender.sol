// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.34;

import {IERC3156FlashBorrower} from "src/interfaces/maker-dao/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "src/interfaces/maker-dao/IERC3156FlashLender.sol";
import {MockFlashCallbackRelay} from "./MockFlashCallbackRelay.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract MockCompositesFlashLender is IERC3156FlashLender {
    enum Behavior {
        Normal,
        ReturnFalse,
        SkipCallback,
        ShortReceipt,
        SkipCollection,
        ReplayCallback,
        WrongInitiator,
        WrongToken,
        WrongAmount,
        ChangedData,
        WrongCaller,
        ReplayDuringContinuation,
        ExcessReceipt,
        RequireHigherRepayment
    }

    error UnexpectedCallbackResult();
    error TransferFailed();
    error RepaymentShortfall(uint256 expectedBalance, uint256 actualBalance);

    MockERC20 internal immutable _DAI;
    MockFlashCallbackRelay internal immutable _RELAY;
    uint256 internal _fee;
    Behavior internal _behavior;
    IERC3156FlashBorrower internal _activeReceiver;
    uint256 internal _activeAmount;
    bytes internal _activeData;

    constructor(MockERC20 dai_) {
        _DAI = dai_;
        _RELAY = new MockFlashCallbackRelay();
    }

    function configure(uint256 fee_, Behavior behavior_) external {
        _fee = fee_;
        _behavior = behavior_;
    }

    function maxFlashLoan(address token_) external view returns (uint256) {
        return token_ == address(_DAI) ? _DAI.balanceOf(address(this)) : 0;
    }

    function flashFee(address, uint256) external view returns (uint256) {
        return _fee;
    }

    function flashLoan(
        IERC3156FlashBorrower receiver_,
        address token_,
        uint256 amount_,
        bytes calldata data_
    ) external returns (bool) {
        Behavior behavior = _behavior;
        if (behavior == Behavior.SkipCallback) return true;
        uint256 balanceBefore = _DAI.balanceOf(address(this));
        uint256 sent = amount_;
        if (behavior == Behavior.ShortReceipt) --sent;
        if (behavior == Behavior.ExcessReceipt) ++sent;
        if (!_DAI.transfer(address(receiver_), sent)) revert TransferFailed();
        if (behavior == Behavior.ReplayDuringContinuation) {
            _activeReceiver = receiver_;
            _activeAmount = amount_;
            _activeData = data_;
        }
        bytes32 result;
        if (behavior == Behavior.WrongCaller) {
            result = _RELAY.forward(receiver_, msg.sender, token_, amount_, _fee, data_);
        } else {
            result = receiver_.onFlashLoan(
                behavior == Behavior.WrongInitiator ? address(this) : msg.sender,
                behavior == Behavior.WrongToken ? address(this) : token_,
                behavior == Behavior.WrongAmount ? amount_ - 1 : amount_,
                _fee,
                behavior == Behavior.ChangedData ? bytes("different") : data_
            );
        }
        if (result != keccak256("ERC3156FlashBorrower.onFlashLoan"))
            revert UnexpectedCallbackResult();
        if (behavior == Behavior.ReplayCallback) {
            // forge-lint: disable-next-line(unused-return)
            receiver_.onFlashLoan(msg.sender, token_, amount_, _fee, data_);
        }
        if (behavior == Behavior.ReturnFalse) return false;
        if (
            behavior != Behavior.SkipCollection &&
            !_DAI.transferFrom(address(receiver_), address(this), amount_ + _fee)
        ) revert TransferFailed();
        if (behavior == Behavior.RequireHigherRepayment) {
            uint256 expectedBalance = balanceBefore + _fee + 1;
            uint256 actualBalance = _DAI.balanceOf(address(this));
            if (actualBalance < expectedBalance)
                revert RepaymentShortfall(expectedBalance, actualBalance);
        }
        return true;
    }

    function repeatActiveCallback() external {
        // forge-lint: disable-next-line(unused-return)
        _activeReceiver.onFlashLoan(
            address(_activeReceiver),
            address(_DAI),
            _activeAmount,
            _fee,
            _activeData
        );
    }
}
