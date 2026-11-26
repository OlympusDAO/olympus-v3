// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";

contract MockERC20FeeOnTransfer is ERC20 {
    error InvalidFeeRecipient();
    uint256 public constant FEE = 1000; // 10%
    uint256 public constant FEE_DENOMINATOR = 100e2;

    address public immutable FEE_RECIPIENT;

    constructor(
        string memory name,
        string memory symbol,
        address feeRecipient_
    ) ERC20(name, symbol) {
        if (feeRecipient_ == address(0)) revert InvalidFeeRecipient();
        FEE_RECIPIENT = feeRecipient_;
    }

    function mint(address recipient_, uint256 amount_) public {
        _mint(recipient_, amount_);
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        // Determine the fee amount
        uint256 fee = (value * FEE) / FEE_DENOMINATOR;

        // Transfer the amount to the recipient
        super.transfer(to, value - fee);

        // Transfer the fee to the fee recipient
        super.transfer(FEE_RECIPIENT, fee);

        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        // Determine the fee amount
        uint256 fee = (value * FEE) / FEE_DENOMINATOR;

        // Transfer the amount to the recipient
        super.transferFrom(from, to, value - fee);

        // Transfer the fee to the fee recipient
        super.transferFrom(from, FEE_RECIPIENT, fee);

        return true;
    }
}
