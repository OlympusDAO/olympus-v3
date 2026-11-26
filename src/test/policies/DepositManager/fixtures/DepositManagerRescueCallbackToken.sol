// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.27;

// Contracts
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

/// @notice Preserves the exact nested error when a rescue transfer propagates callback failure.
contract DepositManagerRescueCallbackToken is ReentrantFeeToken {
    function _revertCallbackFailure(bytes memory data_) internal pure override {
        assembly ("memory-safe") {
            revert(add(data_, 0x20), mload(data_))
        }
    }
}
