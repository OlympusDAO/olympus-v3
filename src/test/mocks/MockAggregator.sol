// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {IBondAggregator} from "interfaces/IBondAggregator.sol";
import {IBondAuctioneer} from "interfaces/IBondAuctioneer.sol";

contract MockAggregator {
    IBondAuctioneer public auctioneer;

    constructor(address auctioneer_) {
        auctioneer = IBondAuctioneer(auctioneer_);
    }

    // ========= VIEW FUNCTIONS ========= //

    function getAuctioneer(uint256 id_) external view returns (IBondAuctioneer) {
        return auctioneer;
    }
}
