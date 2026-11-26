// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

/// @dev Propagates the actual nested error so rollback tests can assert the Core guard selector.
contract CoreCallbackToken is ReentrantFeeToken {
    function _revertCallbackFailure(bytes memory reason_) internal pure override {
        assembly ("memory-safe") {
            revert(add(reason_, 32), mload(reason_))
        }
    }
}
