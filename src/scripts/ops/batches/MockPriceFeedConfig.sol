// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

// Mock Price Feed
import {MockPriceFeedOwned} from "src/test/mocks/MockPriceFeedOwned.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

/// @notice Configures MockPriceFeedOwned contracts with price data
/// @dev    This script sets the latest answer, timestamp, and round ID for mock price feeds
contract MockPriceFeedConfig is BatchScriptV2 {
    /// @notice Configure a mock price feed with the specified values
    function configurePriceFeed(
        bool useDaoMS_,
        string calldata argsFile_
    ) external setUpWithChainIdAndArgsFile(useDaoMS_, argsFile_) {
        // Read arguments
        string memory priceFeedName = _readBatchArgString("configurePriceFeed", "priceFeedName");
        int256 latestAnswer = int256(_readBatchArgUint256("configurePriceFeed", "latestAnswer"));
        uint256 timestamp = _readBatchArgUint256("configurePriceFeed", "timestamp");
        uint80 roundId = uint80(_readBatchArgUint256("configurePriceFeed", "roundId"));

        // Get price feed address
        address priceFeed = _envAddressNotZero(priceFeedName);

        console2.log("=== Configuring Mock Price Feed ===");
        console2.log("Price feed:", priceFeedName);
        console2.log("Address:", priceFeed);
        console2.log("Latest answer:", latestAnswer);
        console2.log("Timestamp:", timestamp);
        console2.log("Round ID:", roundId);

        // Set latest answer
        addToBatch(
            priceFeed,
            abi.encodeWithSelector(MockPriceFeedOwned.setLatestAnswer.selector, latestAnswer)
        );

        // Set timestamp
        addToBatch(
            priceFeed,
            abi.encodeWithSelector(MockPriceFeedOwned.setTimestamp.selector, timestamp)
        );

        // Set round ID
        addToBatch(
            priceFeed,
            abi.encodeWithSelector(MockPriceFeedOwned.setRoundId.selector, roundId)
        );

        // Set answered in round to the same as round ID
        addToBatch(
            priceFeed,
            abi.encodeWithSelector(MockPriceFeedOwned.setAnsweredInRound.selector, roundId)
        );

        console2.log("Mock price feed configuration batch prepared");
        proposeBatch();
    }
}
