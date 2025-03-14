// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IMonoCooler} from "src/policies/interfaces/cooler/IMonoCooler.sol";
import {IDLGTEv1} from "src/modules/DLGTE/IDLGTE.v1.sol";

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

    // ========= EVENTS ========= //

    /// @notice Emitted when a CoolerFactory is added to the migrator
    event CoolerFactoryAdded(address indexed coolerFactory);

    /// @notice Emitted when a CoolerFactory is removed from the migrator
    event CoolerFactoryRemoved(address indexed coolerFactory);

    // ========= FUNCTIONS ========= //

    /// @notice Preview the consolidation of a set of loans.
    ///
    /// @param  coolers_            The Coolers to consolidate the loans from.
    /// @return collateralAmount    The amount of collateral that will be migrated into Cooler V2.
    /// @return borrowAmount        The amount of debt that will be borrowed from Cooler V2.
    function previewConsolidate(
        address[] calldata coolers_
    ) external view returns (uint256 collateralAmount, uint256 borrowAmount);

    /// @notice Consolidate Cooler V1 loans into Cooler V2
    ///
    ///         This function supports consolidation of loans from multiple Clearinghouses and Coolers, provided that the caller is the owner.
    ///
    ///         The funds for paying interest owed and fees will be borrowed from Cooler V2.
    ///
    ///         It is expected that the caller will have already provided approval for this contract to spend the required tokens. See `previewConsolidate()` for more details.
    ///
    /// @dev    The implementing function is expected to handle the following:
    ///         - Ensure that `coolers_` are valid
    ///         - Ensure that the caller is the owner of the Coolers
    ///         - Repay all loans in the Coolers
    ///         - Deposit the collateral into Cooler V2
    ///         - Borrow the required amount from Cooler V2 to repay the Cooler V1 loans
    ///
    /// @param  coolers_            The Coolers from which the loans will be migrated.
    /// @param  newOwner_           Address of the owner of the Cooler V2 position. This can be the same as the caller, or a different address.
    /// @param  authorization_      Authorization parameters for the new owner. Set the `account` field to the zero address to indicate that authorization has already been provided through `IMonoCooler.setAuthorization()`.
    /// @param  signature_          Authorization signature for the new owner. Ignored if `authorization_.account` is the zero address.
    /// @param  delegationRequests_ Delegation requests for the new owner.
    function consolidate(
        address[] memory coolers_,
        address newOwner_,
        IMonoCooler.Authorization memory authorization_,
        IMonoCooler.Signature calldata signature_,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests_
    ) external;

    // ===== ADMIN FUNCTIONS ===== //

    /// @notice Add a CoolerFactory to the migrator
    ///
    /// @param  coolerFactory_ The CoolerFactory to add
    function addCoolerFactory(address coolerFactory_) external;

    /// @notice Remove a CoolerFactory from the migrator
    ///
    /// @param  coolerFactory_ The CoolerFactory to remove
    function removeCoolerFactory(address coolerFactory_) external;

    /// @notice Get the list of CoolerFactories
    ///
    /// @return coolerFactories The list of CoolerFactories
    function getCoolerFactories() external view returns (address[] memory coolerFactories);
}
