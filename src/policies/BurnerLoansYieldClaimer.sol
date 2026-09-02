// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/IBurnerLoansYieldClaim.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";

// Libraries
import {ExcessivelySafeCall} from "@excessively-safe-call-0.0.1/ExcessivelySafeCall.sol";
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyAdminOptimized} from "src/policies/utils/PolicyAdminOptimized.sol";
import {BURNER_LOANS_ADMIN_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Burner Loans Yield Claimer
/// @notice Heart task that claims every Burner Loans asset without propagating failure.
/// @dev The task forwards one gas-bounded call and has no independent asset configuration.
contract BurnerLoansYieldClaimer is
    Policy,
    PolicyAdminOptimized,
    IBurnerLoansYieldClaimer,
    IPeriodicTask
{
    using ExcessivelySafeCall for address;

    /// @dev Maximum revert data copied from the Burner Loans claim call.
    uint16 internal constant _MAX_RETURN_DATA_BYTES = 4;

    /// @dev Burner Loans policy that owns the permissionless all-asset claim function.
    address internal immutable _BURNER_LOANS;

    /// @inheritdoc IBurnerLoansYieldClaimer
    uint32 public override executionGasLimit;

    /// @notice Deploys a Heart task for a same-Kernel Burner Loans policy.
    /// @dev Reverts if:
    ///      - `burnerLoans_` is zero or lacks `IBurnerLoansYieldClaim` support.
    ///      - `burnerLoans_` reports a Kernel different from `kernel_`.
    ///      - `executionGasLimit_` is zero.
    /// @param kernel_ Kernel shared with the Burner Loans target.
    /// @param burnerLoans_ Burner Loans policy whose aggregate yield is claimed.
    /// @param executionGasLimit_ Initial gas forwarded to `BurnerLoans.claimYield`.
    constructor(Kernel kernel_, address burnerLoans_, uint32 executionGasLimit_) Policy(kernel_) {
        if (burnerLoans_ == address(0)) revert BurnerLoansYieldClaimer_ZeroAddress();
        if (
            !ERC165Checker.supportsInterface(burnerLoans_, type(IBurnerLoansYieldClaim).interfaceId)
        ) {
            revert BurnerLoansYieldClaimer_InvalidBurnerLoans(burnerLoans_);
        }

        address burnerLoansKernel = address(Policy(burnerLoans_).kernel());
        if (burnerLoansKernel != address(kernel_)) {
            revert BurnerLoansYieldClaimer_KernelMismatch(address(kernel_), burnerLoansKernel);
        }

        _BURNER_LOANS = burnerLoans_;
        _setExecutionGasLimit(executionGasLimit_);
    }

    /// @inheritdoc Policy
    /// @dev Reverts if the installed ROLES module does not use major version 1.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        (uint8 rolesMajor, ) = Module(address(ROLES)).VERSION();
        if (rolesMajor != 1) revert Policy_WrongModuleVersion(abi.encode([1]));
    }

    /// @inheritdoc Policy
    /// @dev This task does not call permissioned modules.
    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](0);
    }

    /// @notice Returns the version of the policy.
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @inheritdoc IPeriodicTask
    /// @dev The Heart role check is intentionally fail-closed. After authorization, claim failure
    ///      is reported by its bounded revert-data prefix and does not propagate to Heart. Burner
    ///      Loans emits asset-specific events for successful claims.
    function execute() external override onlyRole(HEART_ROLE) {
        (bool success, bytes memory returnData) = _BURNER_LOANS.excessivelySafeCall(
            executionGasLimit,
            0,
            _MAX_RETURN_DATA_BYTES,
            abi.encodeCall(IBurnerLoansYieldClaim.claimYield, ())
        );
        if (success) return;

        // Casting is safe because ExcessivelySafeCall caps returnData at four bytes.
        // forge-lint: disable-next-line(unsafe-typecast)
        emit YieldClaimFailed(_BURNER_LOANS, bytes4(returnData));
    }

    /// @inheritdoc IBurnerLoansYieldClaimer
    /// @dev Reverts if the caller lacks both accepted authorities or `gasLimit_` is zero.
    function setExecutionGasLimit(uint32 gasLimit_) external override {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
        _setExecutionGasLimit(gasLimit_);
    }

    /// @inheritdoc IBurnerLoansYieldClaimer
    function burnerLoans() external view override returns (address burnerLoans_) {
        return _BURNER_LOANS;
    }

    /// @inheritdoc IPeriodicTask
    function supportsInterface(bytes4 interfaceId_) external pure override returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IPeriodicTask).interfaceId ||
            interfaceId_ == type(IBurnerLoansYieldClaimer).interfaceId;
    }

    /// @notice Stores a nonzero claim gas limit and emits the configuration event.
    function _setExecutionGasLimit(uint32 gasLimit_) private {
        if (gasLimit_ == 0) revert BurnerLoansYieldClaimer_InvalidExecutionGasLimit();
        executionGasLimit = gasLimit_;
        emit ExecutionGasLimitSet(gasLimit_);
    }
}
