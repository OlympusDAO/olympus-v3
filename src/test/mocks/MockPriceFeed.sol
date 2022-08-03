// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";

contract MockPriceFeed is AggregatorV2V3Interface {
    int256 public s_answer;
    uint8 public s_decimals;
    uint256 public s_timestamp;

    function setLatestAnswer(int256 answer) public {
        s_answer = answer;
    }

    function latestAnswer() public view override returns (int256) {
        return s_answer;
    }

    function setDecimals(uint8 decimals_) public {
        s_decimals = decimals_;
    }

    function decimals() external view override returns (uint8) {
        return s_decimals;
    }

    function setTimestamp(uint256 timestamp_) public {
        s_timestamp = timestamp_;
    }

    function latestTimestamp() external view override returns (uint256) {
        return s_timestamp;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, s_answer, 0, s_timestamp, 0);
    }

    /// Not implemented but required by interface

    function latestRound() external view override returns (uint256) {}

    function getAnswer(uint256 roundId) external view override returns (int256) {}

    function getTimestamp(uint256 roundId) external view override returns (uint256) {}

    function description() external view override returns (string memory) {}

    function version() external view override returns (uint256) {}

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {}
}
