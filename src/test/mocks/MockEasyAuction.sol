// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract MockEasyAuction {
    // ========= DATA STRUCTURES ========= //
    struct AuctionData {
        ERC20 auctioningToken;
        ERC20 biddingToken;
        uint256 orderCancellationEndDate;
        uint256 auctionEndDate;
        uint256 minimumBiddingAmountPerOrder;
        bool minFundingThresholdNotReached;
        bool isAtomicClosureAllowed;
        uint256 minFundingThreshold;
    }

    // ========= STATE ========= //
    mapping(uint256 => AuctionData) public auctionData;
    uint256 public auctionCounter;

    constructor() {}

    function initiateAuction(
        ERC20 tokenToSell,
        ERC20 biddingToken,
        uint256 lastCancellation,
        uint256 auctionEnd,
        uint96 auctionAmount,
        uint96 minimumTotalPurchased,
        uint256 minimumPurchaseAmount,
        uint256 minFundingThreshold,
        bool isAtomicClosureAllowed,
        address accessManager,
        bytes calldata accessManagerData
    ) external returns (uint256) {
        ++auctionCounter;

        auctionData[auctionCounter] = AuctionData(
            tokenToSell,
            biddingToken,
            lastCancellation,
            auctionEnd,
            minimumPurchaseAmount,
            false,
            isAtomicClosureAllowed,
            minFundingThreshold
        );

        tokenToSell.transferFrom(msg.sender, address(this), auctionAmount);
        return auctionCounter;
    }

    function settleAuction(uint256 auctionId) external returns (bytes32) {
        return bytes32(0);
    }
}
