// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(erc20-unchecked-transfer)
pragma solidity >=0.8.0;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract MockERC20FeeOnTransfer is MockERC20 {
    uint256 public constant FEE = 1000; // 10%
    uint256 public constant FEE_DENOMINATOR = 100e2;

    address public immutable FEE_RECIPIENT;

    constructor(
        string memory name,
        string memory symbol,
        address feeRecipient_
    ) MockERC20(name, symbol, 18) {
        FEE_RECIPIENT = feeRecipient_;
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
/// forge-lint: disable-end(erc20-unchecked-transfer)
