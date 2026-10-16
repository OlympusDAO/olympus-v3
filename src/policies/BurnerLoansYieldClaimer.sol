// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/IBurnerLoansYieldClaim.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";

// Libraries
import {SafeCall} from "src/libraries/SafeCall.sol";
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {BURNER_LOANS_ADMIN_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Burner Loans Yield Claimer
/// @notice Heart task that resumes registered-asset claims within a complete-task gas limit.
/// @dev The task reads Burner Loans' append-only registry inside a gas-bounded external self-call.
///      Each claim is separately gas-bounded so its cursor and earlier claims remain committed when
///      one registered asset fails or exhausts its forwarded gas.
contract BurnerLoansYieldClaimer is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    IBurnerLoansYieldClaimer,
    IPeriodicTask,
    IVersioned
{
    using SafeCall for address;

    /// @dev Maximum revert data copied from the Burner Loans claim call.
    uint16 internal constant _MAX_RETURN_DATA_BYTES = 4;
    /// @dev Minimum supported gas retained for failure reporting and task cleanup.
    uint32 internal constant _DEFAULT_GAS_RESERVE = 100_000;
    /// @dev Gas budgeted for cursor arithmetic and a cold zero-to-nonzero cursor write.
    uint32 internal constant _CURSOR_UPDATE_GAS_BUFFER = 50_000;
    /// @dev Default minimum gas required before attempting another registered asset.
    uint32 internal constant _DEFAULT_MINIMUM_GAS_TO_ATTEMPT = 250_000;

    /// @dev Burner Loans policy that owns the permissionless single-asset claim function plus the
    ///      registered-asset view used for periodic iteration.
    address internal immutable _BURNER_LOANS;

    /// @inheritdoc IBurnerLoansYieldClaimer
    uint32 public override executionGasLimit;
    /// @inheritdoc IBurnerLoansYieldClaimer
    uint32 public override minimumGasToAttempt;
    /// @inheritdoc IBurnerLoansYieldClaimer
    uint32 public override gasReserve;
    /// @dev Index of the first unattempted registered asset after execution pauses.
    uint256 internal _nextAssetIndex;

    /// @notice Deploys a Heart task for a same-Kernel Burner Loans policy.
    /// @dev Reverts if:
    ///      - `burnerLoans_` is zero or lacks claim, asset-registry view, or lifecycle support.
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
        bytes4[] memory interfaceIds = new bytes4[](3);
        interfaceIds[0] = type(IBurnerLoansYieldClaim).interfaceId;
        interfaceIds[1] = type(IBurnerLoansView).interfaceId;
        interfaceIds[2] = type(IEnabler).interfaceId;
        if (!ERC165Checker.supportsAllInterfaces(burnerLoans_, interfaceIds)) {
            revert BurnerLoansYieldClaimer_InvalidBurnerLoans(burnerLoans_);
        }

        address burnerLoansKernel = address(Policy(burnerLoans_).kernel());
        if (burnerLoansKernel != address(kernel_)) {
            revert BurnerLoansYieldClaimer_KernelMismatch(address(kernel_), burnerLoansKernel);
        }

        _BURNER_LOANS = burnerLoans_;
        _setExecutionGasLimit(executionGasLimit_);
        _setMinimumGasToAttempt(_DEFAULT_MINIMUM_GAS_TO_ATTEMPT);
        _setGasReserve(_DEFAULT_GAS_RESERVE);
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
    ///      no-op before any registry read. A Kernel-inactive task also returns before its self-call.
    ///      While active and enabled, the complete task body runs in a gas-bounded external
    ///      self-call. Individual asset failures are reported by their bounded revert-data prefixes.
    ///      The task retains cleanup gas and resumes from its stored cursor when the remaining
    ///      budget is too low for another asset.
    function execute() external override onlyRole(HEART_ROLE) {
        if (!kernel.isPolicyActive(Policy(address(this))) || !isEnabled) return;

        (bool success, bytes memory reason) = address(this).safeCall(
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
        if (!kernel.isPolicyActive(Policy(_BURNER_LOANS)) || !IEnabler(_BURNER_LOANS).isEnabled())
            return;

        IBurnerLoansView facility = IBurnerLoansView(_BURNER_LOANS);
        uint256 assetCount = facility.getAssetCount();
        if (assetCount == 0) return;
        uint256 index = _nextAssetIndex % assetCount;
        for (uint256 attempted; attempted < assetCount; ++attempted) {
            if (gasleft() <= minimumGasToAttempt) break;
            // forge-lint: disable-next-line(calls-loop)
            address asset = facility.getAssetAt(index);
            bytes memory callData = abi.encodeCall(IBurnerLoansYieldClaim.claimYield, (asset));
            // Stop before changing the cursor when the indexed lookup has consumed the budget
            // needed to persist progress while preserving the cleanup reserve.
            if (gasleft() <= uint256(gasReserve) + _CURSOR_UPDATE_GAS_BUFFER) break;
            // Advance before the isolated call so a failing or gas-burning asset does not starve
            // later registry entries on subsequent Heart beats.
            index = (index + 1) % assetCount;
            // forge-lint: disable-next-line(costly-loop)
            _nextAssetIndex = index;
            // Measure after persisting the cursor so that storage cost cannot consume the amount
            // intentionally retained from the isolated claim call.
            uint256 availableGas = gasleft();
            (bool success, bytes memory returnData) = _BURNER_LOANS.safeCall(
                availableGas - gasReserve,
                0,
                _MAX_RETURN_DATA_BYTES,
                callData
            );
            if (success) continue;

            // Casting is safe because SafeCall caps returnData at four bytes.
            // forge-lint: disable-next-line(unsafe-typecast)
            emit YieldAssetClaimFailed(asset, bytes4(returnData));
        }
    }

    /// @inheritdoc IBurnerLoansYieldClaimer
    /// @dev Reverts if the caller lacks both accepted authorities or `gasLimit_` is zero.
    function setExecutionGasLimit(uint32 gasLimit_) external override {
        _requireClaimerAdmin();
        _setExecutionGasLimit(gasLimit_);
    }

    /// @inheritdoc IBurnerLoansYieldClaimer
    /// @dev Reverts if the caller lacks both accepted authorities or the threshold does not exceed
    ///      the cleanup reserve. Callable while locally disabled or Kernel-inactive.
    function setMinimumGasToAttempt(uint32 gasLimit_) external override {
        _requireClaimerAdmin();
        _setMinimumGasToAttempt(gasLimit_);
    }

    /// @inheritdoc IBurnerLoansYieldClaimer
    /// @dev Reverts if the caller lacks both accepted authorities or the reserve is below the
    ///      supported minimum or reaches the attempt threshold. Callable while locally disabled or
    ///      Kernel-inactive.
    function setGasReserve(uint32 gasLimit_) external override {
        _requireClaimerAdmin();
        _setGasReserve(gasLimit_);
    }

    /// @inheritdoc IBurnerLoansYieldClaimer
    /// @dev Reverts if the caller lacks both accepted authorities or a nonzero index is outside the
    ///      live asset registry. Callable while locally disabled or Kernel-inactive.
    function setNextAssetIndex(uint256 index_) external override {
        _requireClaimerAdmin();
        if (index_ == 0) {
            if (_nextAssetIndex == 0) return;
            _nextAssetIndex = 0;
            emit NextAssetIndexSet(0);
            return;
        }
        uint256 assetCount = IBurnerLoansView(_BURNER_LOANS).getAssetCount();
        if (index_ >= assetCount) {
            revert BurnerLoansYieldClaimer_InvalidAssetIndex(index_, assetCount);
        }
        if (index_ == _nextAssetIndex) return;
        _nextAssetIndex = index_;
        emit NextAssetIndexSet(index_);
    }

    /// @inheritdoc IBurnerLoansYieldClaimer
    function burnerLoans() external view override returns (address burnerLoans_) {
        return _BURNER_LOANS;
    }

    /// @inheritdoc IBurnerLoansYieldClaimer
    function nextAssetIndex() external view override returns (uint256 index_) {
        return _nextAssetIndex;
    }

    /// @notice Authorizes a re-enable transition during the grace period.
    /// @dev Reverts unless the caller is an OCG admin or Burner Loans admin.
    function _authorizeReEnable() internal view override {
        _requireClaimerAdmin();
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

    /// @dev Reverts unless the caller is an OCG admin or Burner Loans admin.
    function _requireClaimerAdmin() internal view {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
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

    /// @notice Stores and emits a changed nonzero complete-task gas limit.
    function _setExecutionGasLimit(uint32 gasLimit_) private {
        if (gasLimit_ == 0) revert BurnerLoansYieldClaimer_InvalidExecutionGasLimit();
        if (gasLimit_ == executionGasLimit) return;
        executionGasLimit = gasLimit_;
        emit ExecutionGasLimitSet(gasLimit_);
    }

    /// @dev Stores a changed attempt threshold that strictly exceeds the cleanup reserve.
    function _setMinimumGasToAttempt(uint32 gasLimit_) private {
        if (gasLimit_ <= gasReserve) {
            revert BurnerLoansYieldClaimer_InvalidMinimumGasToAttempt();
        }
        if (gasLimit_ == minimumGasToAttempt) return;
        minimumGasToAttempt = gasLimit_;
        emit MinimumGasToAttemptSet(gasLimit_);
    }

    /// @dev Stores a changed supported cleanup reserve below the attempt threshold.
    function _setGasReserve(uint32 gasLimit_) private {
        if (gasLimit_ < _DEFAULT_GAS_RESERVE || gasLimit_ >= minimumGasToAttempt) {
            revert BurnerLoansYieldClaimer_InvalidGasReserve();
        }
        if (gasLimit_ == gasReserve) return;
        gasReserve = gasLimit_;
        emit GasReserveSet(gasLimit_);
    }
}
