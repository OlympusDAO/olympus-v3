// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {IBondAggregator} from "interfaces/IBondAggregator.sol";
import {IBondAuctioneer} from "interfaces/IBondAuctioneer.sol";
import {IBondTeller} from "interfaces/IBondTeller.sol";

contract MockAggregator {
    IBondAuctioneer public auctioneer;
    IBondTeller public teller;

    constructor(address auctioneer_, address teller_) {
        auctioneer = IBondAuctioneer(auctioneer_);
        teller = IBondTeller(teller_);
    }

    // ========= VIEW FUNCTIONS ========= //

    function getAuctioneer(uint256 id_) external view returns (IBondAuctioneer) {
        return auctioneer;
    }

    function getTeller(uint256 id_) external view returns (IBondTeller) {
        return teller;
    }
}
