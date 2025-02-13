// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDLGTEv1} from "modules/DLGTE/IDLGTE.v1.sol";
import {IMonoCooler} from "./IMonoCooler.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

interface ICoolerComposites {
    // ===== Composite Functions ===== //

    /// @notice Allow user to add collateral and borrow from Cooler V2
    /// @dev    User must have already authorized the composites contract to act on their behalf
    ///
    /// @param  collateralAmount        amount of gOHM collateral to deposit
    /// @param  borrowAmount            amount of USDS to borrow
    /// @param  delegationRequests      resulting collateral delegation
    function addCollateralAndBorrow(
        uint128 collateralAmount,
        uint128 borrowAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external;

    /// @notice Allow user to add collateral and borrow from Cooler V2
    /// @dev    User must provide authorization signature before using function
    ///
    /// @param  authorization           authorization info
    /// @param  signature               offchain auth signature
    /// @param  collateralAmount        amount of gOHM collateral to deposit
    /// @param  borrowAmount            amount of USDS to borrow
    /// @param  delegationRequests      resulting collateral delegation
    function addCollateralAndBorrow(
        IMonoCooler.Authorization memory authorization,
        IMonoCooler.Signature calldata signature,
        uint128 collateralAmount,
        uint128 borrowAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external;

    /// @notice Allow user to repay debt and remove collateral from Cooler V2
    /// @dev    User must have already authorized the composites contract to act on their behalf
    ///
    /// @param  repayAmount         amount of USDS to repay
    /// @param  collateralAmount    amount of gOHM collateral to withdraw
    /// @param  delegationRequests  resulting collateral delegation
    function repayAndRemoveCollateral(
        uint128 repayAmount,
        uint128 collateralAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external;

    /// @notice Allow user to repay debt and remove collateral from Cooler V2
    /// @dev    User must provide authorization signature before using function
    ///
    /// @param  authorization       authorization info
    /// @param  signature           offchain auth signature
    /// @param  repayAmount         amount of USDS to repay
    /// @param  collateralAmount    amount of gOHM collateral to withdraw
    /// @param  delegationRequests  resulting collateral delegation
    function repayAndRemoveCollateral(
        IMonoCooler.Authorization memory authorization,
        IMonoCooler.Signature calldata signature,
        uint128 repayAmount,
        uint128 collateralAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external;

    // ===== View Functions ===== //

    /// @notice Get the Cooler contract address
    function COOLER() external view returns (IMonoCooler);

    /// @notice Get the collateral token contract address
    function collateralToken() external view returns (IERC20);

    /// @notice Get the debt token contract address
    function debtToken() external view returns (IERC20);
}
