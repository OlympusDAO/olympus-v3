// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {Owned} from "@solmate-6.2.0/auth/Owned.sol";

contract MockPriceFeedOwned is AggregatorV2V3Interface, Owned {
    int256 internal _answer;
    uint8 internal _decimals;
    uint256 internal _timestamp;
    uint80 internal _roundId;
    uint80 internal _answeredInRound;
    string internal _description;

    constructor() Owned(msg.sender) {}

    function setLatestAnswer(int256 answer) public onlyOwner {
        _answer = answer;
    }

    function latestAnswer() public view override returns (int256) {
        return _answer;
    }

    function setDecimals(uint8 decimals_) public onlyOwner {
        _decimals = decimals_;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function setTimestamp(uint256 timestamp_) public onlyOwner {
        _timestamp = timestamp_;
    }

    function latestTimestamp() external view override returns (uint256) {
        return _timestamp;
    }

    function setRoundId(uint80 roundId_) public onlyOwner {
        _roundId = roundId_;
    }

    function latestRound() external view override returns (uint256) {
        return uint256(_roundId);
    }

    function setAnsweredInRound(uint80 answeredInRound_) public onlyOwner {
        _answeredInRound = answeredInRound_;
    }

    function latestAnsweredInRound() external view returns (uint256) {
        return uint256(_answeredInRound);
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
        return (_roundId, _answer, 0, _timestamp, _answeredInRound);
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function setDescription(string memory description_) public onlyOwner {
        _description = description_;
    }

    /// Not implemented but required by interface

    function getAnswer(uint256 roundId) external view override returns (int256) {}

    function getTimestamp(uint256 roundId) external view override returns (uint256) {}

    function version() external view override returns (uint256) {}

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(
        uint80 roundId_
    )
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
