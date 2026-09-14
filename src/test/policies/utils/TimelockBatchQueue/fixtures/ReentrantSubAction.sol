// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

contract ReentrantSubAction {
    address public immutable QUEUE;
    bytes public reentryCalldata;

    constructor(address queue_) {
        QUEUE = queue_;
    }

    function arm(bytes calldata reentryCalldata_) external {
        reentryCalldata = reentryCalldata_;
    }

    fallback() external payable {
        (bool success, bytes memory returnData) = QUEUE.call(reentryCalldata);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    receive() external payable {}
}
