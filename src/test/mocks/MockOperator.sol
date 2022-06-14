// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import {Kernel, Policy} from "../../Kernel.sol";
import {OlympusAuthority} from "modules/AUTHR.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";

import {IOperator, ERC20, IBondAuctioneer, IBondCallback} from "../../policies/interfaces/IOperator.sol";

/**
 * @notice Mock Operator to test Heart
 */
contract MockOperator is Policy, IOperator, Auth {
    bool public result;
    error Operator_CustomError();

    constructor(Kernel kernel_)
        Policy(kernel_)
        Auth(address(kernel_), Authority(address(0)))
    {
        result = true;
    }

    /* ========== FRAMEWORK CONFIFURATION ========== */
    function configureReads() external override onlyKernel {
        setAuthority(Authority(getModuleAddress("AUTHR")));
    }

    function requestWrites()
        external
        view
        override
        onlyKernel
        returns (bytes5[] memory permissions)
    {}

    /* ========== HEART FUNCTIONS ========== */
    function operate() external requiresAuth {
        if (!result) revert Operator_CustomError();
    }

    function setResult(bool result_) external {
        result = result_;
    }

    /* ========== OPEN MARKET OPERATIONS (WALL) ========== */

    function swap(ERC20 tokenIn_, uint256 amountIn_)
        external
        pure
        returns (uint256 amountOut)
    {
        amountOut = 0;
    }

    function getAmountOut(ERC20 tokenIn_, uint256 amountIn_)
        external
        pure
        returns (uint256)
    {
        return 0;
    }

    /* ========== OPERATOR CONFIGURATION ========== */
    function setSpreads(uint256 cushionSpread_, uint256 wallSpread_) external {}

    function setThresholdFactor(uint256 thresholdFactor_) external {}

    function setCushionFactor(uint32 cushionFactor_) external override {}

    function setCushionParams(
        uint32 duration_,
        uint32 debtBuffer_,
        uint32 depositInterval_
    ) external override {}

    function setReserveFactor(uint32 reserveFactor_) external override {}

    function setRegenParams(
        uint32 wait_,
        uint32 threshold_,
        uint32 observe_
    ) external override {}

    function setBondContracts(
        IBondAuctioneer auctioneer_,
        IBondCallback callback_
    ) external override {}

    function initialize() external override {}

    /* ========== VIEW FUNCTIONS ========== */

    function fullCapacity(bool high_) external view override returns (uint256) {
        return 0;
    }

    function status() external view override returns (Status memory) {
        return
            Status(
                Regen(0, 0, 0, new bool[](0)),
                Regen(0, 0, 0, new bool[](0))
            );
    }

    function config() external view override returns (Config memory) {
        return Config(0, 0, 0, 0, 0, 0, 0, 0);
    }
}
