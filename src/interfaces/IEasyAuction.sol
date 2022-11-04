// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

interface IEasyAuction {
    /// @notice                         Initiates an auction through Gnosis Auctions
    /// @param tokenToSell              The token being sold
    /// @param biddingToken             The token used to bid on the sale token and set its price
    /// @param lastCancellation         The last timestamp a user can cancel their bid at
    /// @param auctionEnd               The timestamp the auction ends at
    /// @param auctionAmount            The number of sale tokens to sell
    /// @param minimumTotalPurchased    The minimum number of sale tokens that need to be sold for the auction to finalize
    /// @param minimumPurchaseAmount    The minimum purchase size in bidding tokens
    /// @param minFundingThreshold      The minimal funding thresholding for finalizing settlement
    /// @param isAtomicClosureAllowed   Can users call settleAuctionAtomically when end date has been reached
    /// @param accessManager            The contract to manage an allowlist
    /// @param accessManagerData        The data for managing an allowlist
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
    ) external returns (uint256);

    /// @notice                         Settles the auction and determines the clearing orders
    /// @param auctionId                The auction to settle
    function settleAuction(uint256 auctionId) external returns (bytes32);
}
