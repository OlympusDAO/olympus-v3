// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";

contract TransferHelperHarness {
    using TransferHelper for ERC20;

    /// @notice Pulls an exact token amount into `recipient_` for testing.
    function safeTransferFromExact(
        ERC20 token_,
        address sender_,
        address recipient_,
        uint256 amount_
    ) external returns (uint256 recipientBalanceBefore_) {
        return token_.safeTransferFromExact(sender_, recipient_, amount_);
    }
}
