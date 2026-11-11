// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.27;

// Contracts
import {MockERC20} from "src/test/mocks/MockERC20.sol";

/// @notice ERC-20 test token that can revert transfers to selected recipients.
contract MockRevertingTransferToken is MockERC20 {
    error TransferReverted(address recipient);

    mapping(address recipient => bool reverts) internal _revertingRecipients;
    uint256 internal _transferCallCount;
    uint256 internal _revertOnTransferCall;

    constructor(uint8 decimals_) MockERC20("Reverting Transfer Token", "RTT", decimals_) {}

    function setTransferReverts(address recipient_, bool reverts_) external {
        _revertingRecipients[recipient_] = reverts_;
    }

    function setRevertOnTransferCall(uint256 call_) external {
        _transferCallCount = 0;
        _revertOnTransferCall = call_;
    }

    function transferCallCount() external view returns (uint256) {
        return _transferCallCount;
    }

    function transfer(address recipient_, uint256 amount_) public override returns (bool) {
        ++_transferCallCount;
        if (_revertOnTransferCall != 0 && _transferCallCount == _revertOnTransferCall) {
            revert TransferReverted(recipient_);
        }
        if (_revertingRecipients[recipient_]) revert TransferReverted(recipient_);
        return super.transfer(recipient_, amount_);
    }
}
