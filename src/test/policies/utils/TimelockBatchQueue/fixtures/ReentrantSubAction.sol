// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test fixtures accept zero addresses to model unset, cleared, and invalid states.
// forge-lint: disable-start(missing-zero-check)

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
        // Required to invoke arbitrary reentry calldata and capture exact revert data.
        // forge-lint: disable-next-line(low-level-calls)
        (bool success, bytes memory returnData) = QUEUE.call(reentryCalldata);
        if (!success) {
            // Assembly preserves the queue's exact revert data for atomic rollback tests.
            // forge-lint: disable-next-line(inline-assembly)
            assembly ("memory-safe") {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    receive() external payable {}
}

// forge-lint: disable-end(missing-zero-check)
