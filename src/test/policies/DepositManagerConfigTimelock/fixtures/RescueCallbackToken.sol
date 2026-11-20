// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

/// @notice Callback token that preserves the nested operation's exact failure bytes.
contract RescueCallbackToken is ReentrantFeeToken {
    function _revertCallbackFailure(bytes memory reason_) internal pure override {
        assembly ("memory-safe") {
            revert(add(reason_, 32), mload(reason_))
        }
    }
}
