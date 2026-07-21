// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @notice Recipient that rejects native transfers, used to exercise native-transfer failure
///         paths (e.g. in `Rescueable.rescue()`).
contract RejectingReceiver {
    error NoNative();

    receive() external payable {
        revert NoNative();
    }
}
