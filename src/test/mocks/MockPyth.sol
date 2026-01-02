// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-variable)
pragma solidity ^0.8.0;

import {IPyth} from "interfaces/IPyth.sol";

contract MockPyth is IPyth {
    mapping(bytes32 => Price) public s_prices;

    function setPrice(
        bytes32 priceId,
        int64 price,
        uint64 conf,
        int32 expo,
        uint256 publishTime
    ) public {
        s_prices[priceId] = Price({price: price, conf: conf, expo: expo, publishTime: publishTime});
    }

    function getPriceNoOlderThan(
        bytes32 priceId,
        uint256 age
    ) external view override returns (Price memory) {
        Price memory priceData = s_prices[priceId];

        // Check if price exists
        if (priceData.publishTime == 0) {
            revert("PriceFeedNotFound");
        }

        // Check if price is stale
        if (priceData.publishTime < block.timestamp - age) {
            revert("StalePrice");
        }

        return priceData;
    }
}
/// forge-lint: disable-end(mixed-case-variable)
