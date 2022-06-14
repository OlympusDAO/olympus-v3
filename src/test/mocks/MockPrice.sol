// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Kernel, Module} from "../../Kernel.sol";

/**
 * @notice Mock implementation of Price to use for testing
 */
contract MockPrice is Module {
    uint256 public movingAverage;
    uint256 public lastPrice;
    uint256 public currentPrice;
    uint8 public decimals;
    bool public result;

    error Price_CustomError();

    constructor(Kernel kernel_) Module(kernel_) {
        result = true;
    }

    /* ========== FRAMEWORK CONFIGURATION ========== */
    function KEYCODE() public pure override returns (bytes5) {
        return "PRICE";
    }

    /* ========== HEART FUNCTIONS ========== */
    function updateMovingAverage() external view {
        if (!result) revert Price_CustomError();
    }

    function setResult(bool result_) external {
        result = result_;
    }

    /* ========== POLICY FUNCTIONS ========== */
    function initialize(
        uint256[] memory startObservations_,
        uint48 lastObservationTime_
    ) external {}

    function changeMovingAverageDuration(uint48 movingAverageDuration_)
        external
    {}

    function changeObservationFrequency(uint48 observationFrequency_)
        external
    {}

    /* ========== VIEW FUNCTIONS ========== */
    function getMovingAverage() external view returns (uint256) {
        return movingAverage;
    }

    function getLastPrice() external view returns (uint256) {
        return lastPrice;
    }

    function getCurrentPrice() external view returns (uint256) {
        return currentPrice;
    }

    function getDecimals() external view returns (uint8) {
        return decimals;
    }

    /* ========== TESTING FUNCTIONS ========== */
    function setMovingAverage(uint256 movingAverage_) external {
        movingAverage = movingAverage_;
    }

    function setLastPrice(uint256 lastPrice_) external {
        lastPrice = lastPrice_;
    }

    function setCurrentPrice(uint256 currentPrice_) external {
        currentPrice = currentPrice_;
    }

    function setDecimals(uint8 decimals_) external {
        decimals = decimals_;
    }
}
