// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {LENDRv1} from "src/modules/LENDR/LENDR.v1.sol";
import "src/Kernel.sol";

/// @title  Olympus Lender
/// @notice Olympus Lender (Module) Contract
/// @dev    The Olympus Lender Module tracks approval and debt limits for OHM denominated debt
///         markets. This facilitates the minting of OHM into those markets to provide liquidity.
contract OlympusLender is LENDRv1 {
    //============================================================================================//
    //                                      MODULE SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_) Module(kernel_) {}

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("LENDR");
    }

    /// @inheritdoc Module
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc LENDRv1
    function borrow(uint256 amount_) external override permissioned {
        if (globalDebtOutstanding + amount_ > globalDebtLimit) revert LENDR_GlobalLimitViolation();
        if (marketDebtOutstanding[msg.sender] + amount_ > marketDebtLimit[msg.sender])
            revert LENDR_MarketLimitViolation();

        marketDebtOutstanding[msg.sender] += amount_;
        globalDebtOutstanding += amount_;

        emit Borrow(msg.sender, amount_);
    }

    /// @inheritdoc LENDRv1
    function repay(uint256 amount_) external override permissioned {
        uint256 currentMarketDebt = marketDebtOutstanding[msg.sender];
        uint256 amount = amount_ > currentMarketDebt ? currentMarketDebt : amount_;

        unchecked {
            marketDebtOutstanding[msg.sender] -= amount;
            globalDebtOutstanding -= amount;
        }

        emit Repay(msg.sender, amount);
    }

    /// @inheritdoc LENDRv1
    function setGlobalLimit(uint256 newLimit_) external override permissioned {
        if (newLimit_ < globalDebtOutstanding) revert LENDR_InvalidParams();
        globalDebtLimit = newLimit_;

        emit GlobalLimitUpdated(newLimit_);
    }

    /// @inheritdoc LENDRv1
    function setMarketLimit(address market_, uint256 newLimit_) external override permissioned {
        if (newLimit_ < marketDebtOutstanding[market_]) revert LENDR_InvalidParams();
        marketDebtLimit[market_] = newLimit_;

        emit MarketLimitUpdated(market_, newLimit_);
    }

    /// @inheritdoc LENDRv1
    function setMarketTargetRate(address market_, uint32 newRate_) external override permissioned {
        marketTargetRate[market_] = newRate_;

        emit MarketRateUpdated(market_, newRate_);
    }

    /// @inheritdoc LENDRv1
    function setUnwind(address market_, bool shouldUnwind_) external override permissioned {
        shouldUnwind[market_] = shouldUnwind_;

        emit MarketUnwindUpdated(market_, shouldUnwind_);
    }

    /// @inheritdoc LENDRv1
    function approveMarket(address market_) external override permissioned {
        if (isMarketApproved[market_]) revert LENDR_MarketAlreadyApproved();

        isMarketApproved[market_] = true;
        approvedMarkets.push(market_);
        ++approvedMarketsCount;

        emit MarketApproved(market_);
    }

    /// @inheritdoc LENDRv1
    function removeMarket(uint256 index_, address market_) external override permissioned {
        // Sanity check to ensure the market is approved and the index is correct
        if (!isMarketApproved[market_] || approvedMarkets[index_] != market_)
            revert LENDR_InvalidMarketRemoval();

        isMarketApproved[market_] = false;

        // Delete market from array by swapping with last element and popping
        approvedMarkets[index_] = approvedMarkets[approvedMarketsCount - 1];
        approvedMarkets.pop();
        --approvedMarketsCount;

        emit MarketRemoved(market_);
    }
}
