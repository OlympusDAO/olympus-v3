// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IMonoCooler} from "./IMonoCooler.sol";
import {IDLGTEv1} from "../../../modules/DLGTE/IDLGTE.v1.sol";

/// @title  Cooler V2 Migrator
/// @notice Interface for contracts that migrate Cooler V1 loans to Cooler V2
interface ICoolerV2Migrator {
    // ========= ERRORS ========= //

    /// @notice Thrown when the caller is not the contract itself.
    error OnlyThis();

    /// @notice Thrown when the caller is not the flash lender.
    error OnlyLender();

    /// @notice Thrown when the Cooler is not owned by the caller
    error Only_CoolerOwner();

    /// @notice Thrown when the number of Clearinghouses does not equal the number of Coolers
    error Params_InvalidArrays();

    /// @notice Thrown when the Clearinghouse is not valid
    error Params_InvalidClearinghouse();

    /// @notice Thrown when the Cooler is not valid
    error Params_InvalidCooler();

    /// @notice Thrown when the new owner address provided does not match the authorization
    error Params_InvalidNewOwner();

    /// @notice Thrown when the Cooler is duplicated
    error Params_DuplicateCooler();

    /// @notice Thrown when the address is invalid
    error Params_InvalidAddress(string reason_);

    // ========= FUNCTIONS ========= //

    /// @notice Preview the consolidation of a set of loans.
    ///
    /// @param  coolers_            The Coolers to consolidate the loans from.
    /// @param  callerPays_         True if the caller will pay the interest owed and any fees
    /// @return collateralAmount    The amount of collateral that will be migrated into Cooler V2.
    /// @return borrowAmount        The amount of debt that will be borrowed from Cooler V2.
    /// @return paymentAmount       The amount of DAI that the caller will need to approve and provide to the migrator.
    function previewConsolidate(
        address[] calldata coolers_,
        bool callerPays_
    ) external view returns (uint256 collateralAmount, uint256 borrowAmount, uint256 paymentAmount);

    /// @notice Consolidate Cooler V1 loans into Cooler V2
    ///
    ///         This function supports consolidation of loans from multiple Clearinghouses and Coolers, provided that the caller is the owner.
    ///
    ///         The funds for paying interest owed and fees will be provided by the caller if `callerPays_` is true, otherwise it will be borrowed from Cooler V2. Note that if the LTV of Cooler V2 is not higher than Cooler V1, it will trigger a liquidation and the migration will fail.
    ///
    ///         It is expected that the caller will have already provided approval for this contract to spend the required tokens. See `previewConsolidate()` for more details.
    ///
    /// @dev    The implementing function is expected to handle the following:
    ///         - Ensure that `clearinghouses_` and `coolers_` are valid
    ///         - Ensure that the caller is the owner of the Coolers
    ///         - Repay all loans in the Coolers
    ///         - Deposit the collateral into Cooler V2
    ///         - Borrow the required amount from Cooler V2 to repay the Cooler V1 loans
    ///
    /// @param  coolers_            The Coolers from which the loans will be migrated.
    /// @param  clearinghouses_     The respective Clearinghouses that created and issued the loans in `coolers_`. This array must be the same length as `coolers_`.
    /// @param  newOwner_           Address of the owner of the Cooler V2 position. This can be the same as the caller, or a different address.
    /// @param  callerPays_         True if the caller will pay the interest owed and fees, in terms of DAI.
    /// @param  authorization_      Authorization parameters for the new owner. Set the `account` field to the zero address to indicate that authorization has already been provided through `IMonoCooler.setAuthorization()`.
    /// @param  signature_          Authorization signature for the new owner. Ignored if `authorization_.account` is the zero address.
    /// @param  delegationRequests_ Delegation requests for the new owner.
    function consolidate(
        address[] memory coolers_,
        address[] memory clearinghouses_,
        address newOwner_,
        bool callerPays_,
        IMonoCooler.Authorization memory authorization_,
        IMonoCooler.Signature calldata signature_,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests_
    ) external;
}
