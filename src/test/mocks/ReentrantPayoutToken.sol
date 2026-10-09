// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

/// @dev Allows production payout helpers to defer liabilities before a recovery callback is armed.
contract ReentrantPayoutToken is ReentrantFeeToken {
    error TransferBlocked(address recipient);

    mapping(address recipient => bool blocked) internal _blocked;

    function setTransferBlocked(address recipient_, bool blocked_) external {
        _blocked[recipient_] = blocked_;
    }

    function transfer(address recipient_, uint256 amount_) public virtual override returns (bool) {
        if (_blocked[recipient_]) revert TransferBlocked(recipient_);
        return super.transfer(recipient_, amount_);
    }
}
