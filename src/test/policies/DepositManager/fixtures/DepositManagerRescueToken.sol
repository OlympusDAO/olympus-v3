// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.27;

// Contracts
import {MockERC20} from "src/test/mocks/MockERC20.sol";

/// @notice Rescue fixture with exact dependency errors and mutations before a failed transfer.
contract DepositManagerRescueToken is MockERC20 {
    error RescueBalanceReadFailed();
    error RescueTransferFailed();

    bool public balanceReadFails;
    bool public transferFails;
    uint256 public transferCalls;

    constructor(uint8 decimals_) MockERC20("Rescue token", "RSC", decimals_) {}

    function setBalanceReadFails(bool fails_) external {
        balanceReadFails = fails_;
    }

    function setTransferFails(bool fails_) external {
        transferFails = fails_;
    }

    function balanceOf(address account_) public view override returns (uint256) {
        if (balanceReadFails) revert RescueBalanceReadFailed();
        return super.balanceOf(account_);
    }

    function transfer(address recipient_, uint256 amount_) public override returns (bool) {
        ++transferCalls;
        bool success = super.transfer(recipient_, amount_);
        if (transferFails) revert RescueTransferFailed();
        return success;
    }
}
