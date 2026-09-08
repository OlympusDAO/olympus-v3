// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/IBurnerLoansYieldClaim.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";

// Libraries
import {ExcessivelySafeCall} from "@excessively-safe-call-0.0.1/ExcessivelySafeCall.sol";
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {BURNER_LOANS_ADMIN_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Burner Loans Yield Claimer
/// @notice Heart task that attempts registered-asset claims within a complete-task gas limit.
/// @dev The task reads Burner Loans' append-only registry inside a gas-bounded external self-call.
///      Individual asset failures are isolated, while complete-task failure rolls back every claim.
contract BurnerLoansYieldClaimer is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    IBurnerLoansYieldClaimer,
    IPeriodicTask,
    IVersioned
{
    using ExcessivelySafeCall for address;

    /// @dev Maximum revert data copied from the Burner Loans claim call.
    uint16 internal constant _MAX_RETURN_DATA_BYTES = 4;

    /// @dev Burner Loans policy that owns the permissionless single-asset claim function plus the
    ///      registered-asset view used for periodic iteration.
    address internal immutable _BURNER_LOANS;

    /// @inheritdoc IBurnerLoansYieldClaimer
    uint32 public override executionGasLimit;

    /// @notice Deploys a Heart task for a same-Kernel Burner Loans policy.
    /// @dev Reverts if:
    ///      - `burnerLoans_` is zero or lacks claim or asset-registry view support.
    ///      - `burnerLoans_` reports a Kernel different from `kernel_`.
    ///      - `executionGasLimit_` is zero.
    /// @param kernel_ Kernel shared with the Burner Loans target.
    /// @param burnerLoans_ Burner Loans policy whose registered assets are claimed.
    /// @param executionGasLimit_ Initial gas limit for one complete task execution.
    constructor(
        Kernel kernel_,
        address burnerLoans_,
        uint32 executionGasLimit_
    ) Policy(kernel_) ReEnablerGracePeriod(BurnerLoansConstants.REENABLE_GRACE_PERIOD) {
        if (burnerLoans_ == address(0)) revert BurnerLoansYieldClaimer_ZeroAddress();
        bytes4[] memory interfaceIds = new bytes4[](2);
        interfaceIds[0] = type(IBurnerLoansYieldClaim).interfaceId;
        interfaceIds[1] = type(IBurnerLoansView).interfaceId;
        if (!ERC165Checker.supportsAllInterfaces(burnerLoans_, interfaceIds)) {
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

        // ROLES compatibility depends only on its major version.
        // forge-lint: disable-next-line(unused-return)
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

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @inheritdoc IPeriodicTask
    /// @dev The Heart role check remains active while disabled, but an authorized call is then a
    ///      no-op before any registry read. While enabled, the complete task body runs in a
    ///      gas-bounded external self-call. Individual asset failures are reported by their bounded
    ///      revert-data prefixes and do not block later assets. If the complete task fails, all
    ///      claims performed by that task are rolled back and one aggregate failure is reported.
    function execute() external override onlyRole(HEART_ROLE) {
        if (!isEnabled) return;

        (bool success, bytes memory reason) = address(this).excessivelySafeCall(
            executionGasLimit,
            0,
            _MAX_RETURN_DATA_BYTES,
            abi.encodeCall(this.selfExecuteTask, ())
        );
        // The event intentionally reports only the first four bytes of bounded revert data.
        // forge-lint: disable-next-line(unsafe-typecast)
        if (!success) emit ExecutionFailed(bytes4(reason));
    }

    /// @inheritdoc IBurnerLoansYieldClaimer
    function selfExecuteTask() external override {
        if (msg.sender != address(this)) revert BurnerLoansYieldClaimer_OnlySelf();

        IBurnerLoansView facility = IBurnerLoansView(_BURNER_LOANS);
        uint256 assetCount = facility.getAssetCount();
        for (uint256 i; i < assetCount; ++i) {
            // The governance-controlled registry is expected to remain small, and the task must
            // attempt every configured asset while isolating individual claim failures.
            // forge-lint: disable-next-line(calls-loop)
            address asset = facility.getAssetAt(i);
            (bool success, bytes memory returnData) = _BURNER_LOANS.excessivelySafeCall(
                gasleft(),
                0,
                _MAX_RETURN_DATA_BYTES,
                abi.encodeCall(IBurnerLoansYieldClaim.claimYield, (asset))
            );
            if (success) continue;

            // Casting is safe because ExcessivelySafeCall caps returnData at four bytes.
            // forge-lint: disable-next-line(unsafe-typecast)
            emit YieldAssetClaimFailed(asset, bytes4(returnData));
        }
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

    /// @notice Authorizes a re-enable transition during the grace period.
    /// @dev Reverts unless the caller is an OCG admin or Burner Loans admin.
    function _authorizeReEnable() internal view override {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
    }

    /// @notice Authorizes a grace-period update.
    /// @dev Reverts unless the caller has the OCG admin role.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @dev Revalidates the constructor-bound Burner Loans policy before operational enablement.
    function _beforeEnable(bytes calldata) internal view override {
        _requireBurnerLoansPolicyActive();
    }

    /// @dev Preserves the grace-period gate and revalidates Burner Loans before re-enabling.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requireBurnerLoansPolicyActive();
    }

    /// @dev Reverts unless the constructor-bound Burner Loans policy is active in this Kernel.
    function _requireBurnerLoansPolicyActive() internal view {
        if (!kernel.isPolicyActive(Policy(_BURNER_LOANS))) {
            revert BurnerLoansYieldClaimer_InvalidBurnerLoans(_BURNER_LOANS);
        }
    }

    /// @inheritdoc IPeriodicTask
    function supportsInterface(
        bytes4 interfaceId_
    ) public view override(EnablerV2, ReEnablerGracePeriod, IPeriodicTask) returns (bool) {
        return
            interfaceId_ == type(IPeriodicTask).interfaceId ||
            interfaceId_ == type(IBurnerLoansYieldClaimer).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @notice Stores a nonzero complete-task gas limit and emits the configuration event.
    function _setExecutionGasLimit(uint32 gasLimit_) private {
        if (gasLimit_ == 0) revert BurnerLoansYieldClaimer_InvalidExecutionGasLimit();
        executionGasLimit = gasLimit_;
        emit ExecutionGasLimitSet(gasLimit_);
    }
}
