// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Contracts
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

/// @dev Preserve the nested queue/guard error so the forwarding boundary can be asserted exactly.
contract PayoutRecoveryCallbackToken is ReentrantFeeToken {
    function _revertCallbackFailure(bytes memory reason_) internal pure override {
        assembly ("memory-safe") {
            revert(add(reason_, 32), mload(reason_))
        }
    }
}
