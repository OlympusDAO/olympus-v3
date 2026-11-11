// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.27;

// Contracts
import {MockERC20} from "src/test/mocks/MockERC20.sol";

/// @notice Token fixture that can require more gas than a fixed payout call forwards.
contract GasSensitivePayoutToken is MockERC20 {
    error InsufficientTransferGas();

    bool public needsMoreGas;

    constructor() MockERC20("Gas sensitive", "GAS", 18) {}

    function setNeedsMoreGas(bool required_) external {
        needsMoreGas = required_;
    }

    function transfer(address to_, uint256 amount_) public override returns (bool) {
        if (needsMoreGas && gasleft() < 200_000) revert InsufficientTransferGas();
        return super.transfer(to_, amount_);
    }
}
