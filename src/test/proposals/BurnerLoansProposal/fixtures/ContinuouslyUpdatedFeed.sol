// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

/// @dev Fork-only adapter: preserves a witnessed external feed answer while simulating continuous
///      publication during governance and servicing time advances. Only latestRoundData is redirected.
contract ContinuouslyUpdatedFeed {
    uint80 internal immutable _roundId;
    int256 internal immutable _answer;
    uint80 internal immutable _answeredInRound;

    constructor(uint80 roundId_, int256 answer_, uint80 answeredInRound_) {
        _roundId = roundId_;
        _answer = answer_;
        _answeredInRound = answeredInRound_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (_roundId, _answer, block.timestamp, block.timestamp, _answeredInRound);
    }
}
