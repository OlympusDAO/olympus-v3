// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDLGTEv1} from "src/modules/DLGTE/IDLGTE.v1.sol";
import {IMonoCooler} from "src/policies/interfaces/cooler/IMonoCooler.sol";
import {ICoolerComposites} from "src/periphery/interfaces/ICoolerComposites.sol";

/// @title  ICoolerCompositesV2
/// @notice Interface for the Cooler Composites V2 contract, which extends the ICoolerComposites interface to add auto-delegation and support for providing OHM as collateral
interface ICoolerCompositesV2 is ICoolerComposites {
    // ========= ERRORS ========= //

    /// @notice Thrown if the collateral token does not match the staking contract's gOHM token
    ///
    /// @param  coolerCollateralToken   The address of the collateral token in the Cooler contract
    /// @param  stakingGohm             The address of the gOHM token in the staking contract
    error Params_CollateralTokenMismatch(address coolerCollateralToken, address stakingGohm);

    /// @notice Thrown if the caller is not the owner
    error OnlyOwner();

    /// @notice Thrown if delegation requests are provided while the `autoDelegate` flag is true
    error DelegationRequestsInvalid();

    /// @notice Thrown if the OHM warmup period is active and the caller is supplying OHM as collateral
    error OhmWarmupPeriodActive();

    // ========= FUNCTIONS ========= //

    /// @notice Preview the result of adding collateral and borrowing from Cooler V2
    ///
    /// @param collateralAmount     Amount of OHM or gOHM collateral to deposit
    /// @param borrowAmount         Amount of debt token to borrow
    /// @param useGohm              Whether the caller is supplying OHM (false) or gOHM (true) as collateral
    /// @return success             Whether the operation was successful
    /// @return totalGohmCollateral The total amount of gOHM collateral that will be deposited in Cooler V2 after the transaction
    /// @return remainingBorrowable The amount of debt that can still be borrowed from Cooler V2
    function previewAddCollateralAndBorrow(
        uint128 collateralAmount,
        uint128 borrowAmount,
        bool useGohm
    )
        external
        view
        returns (bool success, uint256 totalGohmCollateral, uint256 remainingBorrowable);

    /// @notice Allow user to add collateral and borrow from Cooler V2
    /// @dev    User must provide authorization signature before using function
    ///
    /// @param authorization        Authorization info. Set the `account` field to the zero address to indicate that authorization has already been provided through `IMonoCooler.setAuthorization()`.
    /// @param signature            Off-chain auth signature. Ignored if `authorization_.account` is the zero address.
    /// @param collateralAmount     Amount of OHM or gOHM collateral to deposit
    /// @param borrowAmount         Amount of debt token to borrow
    /// @param delegationRequests   Resulting collateral delegation
    /// @param autoDelegate         Whether to automatically create delegation requests for the caller/owner
    /// @param useGohm              Whether the caller is supplying OHM (false) or gOHM (true) as collateral
    function addCollateralAndBorrow(
        IMonoCooler.Authorization calldata authorization,
        IMonoCooler.Signature calldata signature,
        uint128 collateralAmount,
        uint128 borrowAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests,
        bool autoDelegate,
        bool useGohm
    ) external;

    /// @notice Preview the result of repaying debt and removing collateral from Cooler V2
    ///
    /// @param repayAmount              Amount of debt token to repay
    /// @param collateralAmount         Amount of OHM or gOHM collateral to withdraw
    /// @param useGohm                  Whether the caller is supplying OHM (false) or gOHM (true) as collateral
    /// @return success                 Whether the operation was successful
    /// @return remainingGohmCollateral The amount of gOHM collateral that will remain in Cooler V2 after the transaction
    /// @return remainingDebt           The amount of debt that will remain in Cooler V2 after the transaction
    function previewRepayAndRemoveCollateral(
        uint128 repayAmount,
        uint128 collateralAmount,
        bool useGohm
    ) external view returns (bool success, uint256 remainingGohmCollateral, uint256 remainingDebt);

    /// @notice Allow user to add collateral and borrow from Cooler V2
    /// @dev    User must provide authorization signature before using function
    ///
    /// @param authorization        Authorization info. Set the `account` field to the zero address to indicate that authorization has already been provided through `IMonoCooler.setAuthorization()`.
    /// @param signature            Off-chain auth signature. Ignored if `authorization_.account` is the zero address.
    /// @param repayAmount          Amount of debt token to repay
    /// @param collateralAmount     Amount of OHM or gOHM collateral to withdraw
    /// @param delegationRequests   Resulting collateral delegation
    /// @param autoDelegate         Whether to automatically create delegation requests for the caller/owner
    /// @param useGohm              Whether the caller wants to receive collateral as OHM (false) or gOHM (true)
    function repayAndRemoveCollateral(
        IMonoCooler.Authorization calldata authorization,
        IMonoCooler.Signature calldata signature,
        uint128 repayAmount,
        uint128 collateralAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests,
        bool autoDelegate,
        bool useGohm
    ) external;
}
