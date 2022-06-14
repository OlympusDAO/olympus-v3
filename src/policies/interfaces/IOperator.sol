// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IBondAuctioneer} from "interfaces/IBondAuctioneer.sol";
import {IBondCallback} from "interfaces/IBondCallback.sol";

// TODO: add NatSpec
interface IOperator {
    /* ========== STRUCTS =========== */

    struct Config {
        uint32 cushionFactor; // percent of capacity to be used for a single cushion deployment, assumes 2 decimals (i.e. 1000 = 10%)
        uint32 cushionDuration; // duration of a single cushion deployment in seconds
        uint32 cushionDebtBuffer; // Percentage over the initial debt to allow the market to accumulate at anyone time. Percent with 3 decimals, e.g. 1_000 = 1 %. See IBondAuctioneer for more info.
        uint32 cushionDepositInterval; // Target frequency of deposits. Determines max payout of the bond market. See IBondAuctioneer for more info.
        uint32 reserveFactor; // percent of reserves in treasury to be used for a single wall, assumes 2 decimals (i.e. 1000 = 10%)
        uint32 regenWait; // minimum duration to wait to reinstate a wall in seconds
        uint32 regenThreshold; // number of price points on other side of moving average to reinstate a wall
        uint32 regenObserve; // number of price points to observe to determine regeneration
    }

    struct Status {
        Regen low;
        Regen high;
    }

    struct Regen {
        uint32 count; // current number of price points that count towards regeneration
        uint48 lastRegen; // timestamp of the last regeneration
        uint32 nextObservation; // index of the next observation in the observations array
        bool[] observations; // individual observations: true = price on other side of average, false = price on same side of average
    }

    /* ========== HEART FUNCTIONS ========== */

    /// @notice     Executes market operations logic on each system heartbeat.
    /// @notice     Only callable by the Heart contract
    /// @dev        This function is triggered by a keeper on the Heart contract.
    function operate() external;

    /* ========== OPEN MARKET OPERATIONS (WALL) ========== */

    function swap(ERC20 tokenIn_, uint256 amountIn_)
        external
        returns (uint256 amountOut);

    function getAmountOut(ERC20 tokenIn_, uint256 amountIn_)
        external
        view
        returns (uint256);

    /* ========== OPERATOR CONFIGURATION ========== */
    /// Policy
    function setSpreads(uint256 cushionSpread_, uint256 wallSpread_) external;

    function setThresholdFactor(uint256 thresholdFactor_) external;

    function setCushionFactor(uint32 cushionFactor_) external;

    function setCushionParams(
        uint32 duration_,
        uint32 debtBuffer_,
        uint32 depositInterval_
    ) external;

    function setReserveFactor(uint32 reserveFactor_) external;

    function setRegenParams(
        uint32 wait_,
        uint32 threshold_,
        uint32 observe_
    ) external;

    /// Guardian
    function setBondContracts(
        IBondAuctioneer auctioneer_,
        IBondCallback callback_
    ) external;

    function initialize() external;

    /* ========== VIEW FUNCTIONS ========== */

    function fullCapacity(bool high_) external view returns (uint256);

    function status() external view returns (Status memory);

    function config() external view returns (Config memory);
}
