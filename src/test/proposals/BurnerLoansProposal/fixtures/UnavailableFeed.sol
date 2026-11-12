// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

/// @dev Fork-only feed replacement for testing unavailable price sources.
contract UnavailableFeed {
    error FeedUnavailable();

    function latestRoundData() external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert FeedUnavailable();
    }
}
