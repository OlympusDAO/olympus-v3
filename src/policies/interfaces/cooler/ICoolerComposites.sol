// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDLGTEv1} from "../../../modules/DLGTE/IDLGTE.v1.sol";
import {IMonoCooler} from "./IMonoCooler.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

interface ICoolerComposites {
    event TokenRefunded(address indexed token, address indexed caller, uint256 amount);

    // ===== Composite Functions ===== //

    /// @notice Allow user to add collateral and borrow from Cooler V2
    /// @dev    User must provide authorization signature before using function
    ///
    /// @param authorization        Authorization info. Set the `account` field to the zero address to indicate that authorization has already been provided through `IMonoCooler.setAuthorization()`.
    /// @param signature            Off-chain auth signature. Ignored if `authorization_.account` is the zero address.
    /// @param collateralAmount     Amount of gOHM collateral to deposit
    /// @param borrowAmount         Amount of USDS to borrow
    /// @param delegationRequests   Resulting collateral delegation
    function addCollateralAndBorrow(
        IMonoCooler.Authorization memory authorization,
        IMonoCooler.Signature calldata signature,
        uint128 collateralAmount,
        uint128 borrowAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external;

    /// @notice Allow user to add collateral and borrow from Cooler V2
    /// @dev    User must provide authorization signature before using function
    ///
    /// @param authorization        Authorization info. Set the `account` field to the zero address to indicate that authorization has already been provided through `IMonoCooler.setAuthorization()`.
    /// @param signature            Off-chain auth signature. Ignored if `authorization_.account` is the zero address.
    /// @param repayAmount          Amount of USDS to repay
    /// @param collateralAmount     Amount of gOHM collateral to withdraw
    /// @param delegationRequests   Resulting collateral delegation
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
