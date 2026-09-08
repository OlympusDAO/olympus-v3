// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

// Interfaces
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

/// @title Config Operator Single Step
/// @notice Reusable single-step configuration-operator storage and rotation.
/// @dev The operator starts unset. Implementations must explicitly override
///      `_authorizeSetConfigOperator` to permit rotation; the default implementation denies every
///      caller. A rotation to the operator already configured, the zero address included, reverts
///      with `ConfigOperator_Unchanged` once the caller is authorized, so a call that lands always
///      changes the operator. Product setters remain responsible for composing operator authority
///      with any other accepted authority.
abstract contract ConfigOperatorSingleStep is IConfigOperator {
    // ========== STATE ========== //

    /// @inheritdoc IConfigOperator
    address public override configOperator;

    // ========== STATE-CHANGING FUNCTIONS ========== //

    /// @inheritdoc IConfigOperator
    /// @dev The zero address is a valid value: it revokes delegated access.
    ///
    ///      Reverts if:
    ///      - `_authorizeSetConfigOperator` denies the caller (`ConfigOperator_Unauthorized`).
    ///      - `configOperator_` is the operator already configured (`ConfigOperator_Unchanged`),
    ///        the zero address over an unset operator included.
    function setConfigOperator(address configOperator_) public virtual override {
        if (!_authorizeSetConfigOperator()) {
            revert ConfigOperator_Unauthorized(msg.sender);
        }
        if (configOperator_ == configOperator) revert ConfigOperator_Unchanged();

        configOperator = configOperator_;
        emit ConfigOperatorSet(configOperator_);
    }

    // ========== AUTHORIZATION ========== //

    /// @notice Validates a caller before an immediate operator rotation or revocation.
    /// @dev Returns false by default. Implementations must explicitly override this hook to grant
    ///      authority and may revert while applying lifecycle or role checks.
    /// @return authorized True when the caller may set the config operator.
    function _authorizeSetConfigOperator() internal view virtual returns (bool authorized) {
        return false;
    }

    /// @notice Returns whether an account is the current non-zero config operator.
    /// @param account_ Account to check.
    /// @return authorized True when `account_` is the current non-zero config operator.
    function _isConfigOperator(address account_) internal view returns (bool authorized) {
        return account_ != address(0) && account_ == configOperator;
    }
}
