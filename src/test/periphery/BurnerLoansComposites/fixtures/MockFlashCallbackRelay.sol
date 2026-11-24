// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.34;

import {IERC3156FlashBorrower} from "src/interfaces/maker-dao/IERC3156FlashBorrower.sol";

/// @dev Calls the receiver from an address other than the configured test lender.
contract MockFlashCallbackRelay {
    function forward(
        IERC3156FlashBorrower receiver_,
        address initiator_,
        address token_,
        uint256 amount_,
        uint256 fee_,
        bytes calldata data_
    ) external returns (bytes32) {
        return receiver_.onFlashLoan(initiator_, token_, amount_, fee_, data_);
    }
}
