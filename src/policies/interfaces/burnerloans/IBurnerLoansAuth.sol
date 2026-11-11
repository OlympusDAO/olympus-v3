// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

/// @notice Core-bound authorization and canonical lending permission interpretation.
interface IBurnerLoansAuth is IOperatorAuth, IBurnerLoansCoreBound, IVersioned {
    /// @notice The supplied Core does not advertise the required ERC165 target interface.
    /// @param core Rejected Core address.
    error BurnerLoansAuth_InvalidCore(address core);
    /// @notice The independently supplied trusted Kernel is the zero address.
    /// @param kernel Rejected Kernel address.
    error BurnerLoansAuth_InvalidKernel(address kernel);
    /// @notice Core currently selects a different Auth instance.
    error BurnerLoansAuth_NotSelected();
    /// @notice Permission bytes are not the canonical lending record encoding.
    error BurnerLoansAuth_InvalidPermissions();
    /// @notice A selected grant asset is zero or is not registered by Core.
    /// @param asset Invalid asset selected by the grant.
    error BurnerLoansAuth_InvalidAsset(address asset);
    /// @notice The operation's asset differs from its selected permission record.
    /// @param expected Asset required by the grant.
    /// @param actual Asset supplied by the operation.
    error BurnerLoansAuth_AssetMismatch(address expected, address actual);
    /// @notice The operation's destination differs from its fixed permission recipient.
    /// @param expected Nonzero recipient required by the grant.
    /// @param actual Destination supplied by the operation.
    error BurnerLoansAuth_RecipientMismatch(address expected, address actual);

    /// @notice Ten canonical ABI words containing independent constraints for each action.
    /// @dev Collateral uses raw asset units; debt uses raw 9-decimal OHM; maturity is absolute seconds.
    /// @param depositAsset Explicit configured deposit asset.
    /// @param maxCollateral Maximum resulting credited collateral; zero is literal.
    /// @param borrowAsset Explicit configured position asset for borrowing.
    /// @param borrowRecipient Required destination, or zero for any otherwise-valid destination.
    /// @param maxDebt Maximum resulting principal due in raw OHM units.
    /// @param withdrawAsset Explicit configured withdrawal position asset.
    /// @param withdrawRecipient Required destination, or zero for any otherwise-valid destination.
    /// @param minCollateral Minimum remaining credited collateral; zero imposes no positive floor.
    /// @param extendAsset Explicit configured position asset for extension.
    /// @param maxMaturity Maximum resulting absolute maturity timestamp.
    struct Permissions {
        address depositAsset;
        uint128 maxCollateral;
        address borrowAsset;
        address borrowRecipient;
        uint128 maxDebt;
        address withdrawAsset;
        address withdrawRecipient;
        uint128 minCollateral;
        address extendAsset;
        uint48 maxMaturity;
    }

    /// @notice Authenticates original delegated authority and resolves its selected position bound.
    /// @param account Position owner.
    /// @param operator Actual operator forwarded by an admitted first-party action.
    /// @param action One action bit: deposit 1, borrow 2, withdraw 4, or extend 8.
    /// @param asset Actual collateral asset identifying the position.
    /// @param recipient Actual borrow/withdraw destination; unused for deposit/extend.
    /// @param originalGrantStamp Grant identity captured before external preparation.
    /// @return bound Maximum resulting collateral/debt/maturity, or minimum remaining collateral.
    function validate(
        address account,
        address operator,
        uint8 action,
        address asset,
        address recipient,
        bytes32 originalGrantStamp
    ) external view returns (uint128 bound);
}
