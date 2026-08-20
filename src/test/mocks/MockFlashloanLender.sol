// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.15;

import {IERC3156FlashLender} from "src/interfaces/maker-dao/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "src/interfaces/maker-dao/IERC3156FlashBorrower.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract MockFlashloanLender is IERC3156FlashLender {
    uint16 public feePercent;
    uint16 public constant MAX_FEE_PERCENT = 10000;

    ERC20 public immutable token;

    error InvalidToken();

    constructor(uint16 feePercent_, address token_) {
        feePercent = feePercent_;
        token = ERC20(token_);
    }

    function setFeePercent(uint16 feePercent_) external {
        feePercent = feePercent_;
    }

    function maxFlashLoan(address token_) external view override returns (uint256) {
        if (token_ != address(token)) revert InvalidToken();

        return type(uint256).max;
    }

    function _flashFee(uint256 amount) internal view returns (uint256) {
        return (amount * feePercent) / MAX_FEE_PERCENT;
    }

    function flashFee(address token_, uint256 amount) external view override returns (uint256) {
        if (token_ != address(token)) revert InvalidToken();

        return _flashFee(amount);
    }

    function flashLoan(
        IERC3156FlashBorrower receiver_,
        address token_,
        uint256 amount_,
        bytes calldata data_
    ) external override returns (bool) {
        if (token_ != address(token)) revert InvalidToken();

        // Transfer the funds to the receiver
        token.transfer(address(receiver_), amount_);

        // Calculate the lender fee
        uint256 lenderFee = _flashFee(amount_);

        // Call the receiver's onFlashLoan function
        receiver_.onFlashLoan(msg.sender, token_, amount_, lenderFee, data_);

        // Calculate the amount to be returned to the caller
        uint256 amountToReturn = amount_ + lenderFee;

        // Transfer the funds back to this contract
        token.transferFrom(address(receiver_), address(this), amountToReturn);

        return true;
    }
}
