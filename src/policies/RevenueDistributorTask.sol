// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {SafeCall} from "src/libraries/SafeCall.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {HEART_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Revenue Distributor Task
/// @notice Heart task that settles listed asset balances.
contract RevenueDistributorTask is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    IRevenueDistributorTask,
    IPeriodicTask,
    IVersioned
{
    using SafeCall for address;

    /// @dev Return data is bounded to the four-byte error selector.
    uint16 internal constant _MAX_RETURN_DATA_BYTES = 4;
    /// @dev Time allowed for governance to re-enable a disabled task.
    uint32 internal constant _REENABLE_GRACE_PERIOD = 7 days;
    /// @dev Gas retained for cursor storage and task cleanup after an isolated call.
    uint32 internal constant _DEFAULT_GAS_RESERVE = 100_000;
    /// @dev Default minimum gas required before attempting another asset.
    uint32 internal constant _DEFAULT_MINIMUM_GAS_TO_ATTEMPT = 250_000;

    /// @dev Distributor serviced by this periodic task.
    address internal immutable _DISTRIBUTOR;
    /// @inheritdoc IRevenueDistributorTask
    uint32 public override executionGasLimit;
    /// @inheritdoc IRevenueDistributorTask
    uint32 public override minimumGasToAttempt;
    /// @inheritdoc IRevenueDistributorTask
    uint32 public override gasReserve;
    /// @dev Index of the first unattempted asset after an execution runs out of gas budget.
    uint256 internal _nextAssetIndex;

    /// @dev Reverts if:
    ///      - The distributor is zero, incompatible, or bound to another Kernel.
    ///      - The execution gas limit is zero.
    constructor(
        Kernel kernel_,
        address distributor_,
        uint32 executionGasLimit_
    ) Policy(kernel_) ReEnablerGracePeriod(_REENABLE_GRACE_PERIOD) {
        if (
            !ERC165Checker.supportsInterface(distributor_, type(IRevenueDistributor).interfaceId) ||
            !ERC165Checker.supportsInterface(distributor_, type(IEnabler).interfaceId)
        ) {
            revert RevenueDistributorTask_InvalidDistributor(distributor_);
        }
        address reportedKernel = address(Policy(distributor_).kernel());
        if (reportedKernel != address(kernel_)) {
            revert RevenueDistributorTask_KernelMismatch(address(kernel_), reportedKernel);
        }
        _DISTRIBUTOR = distributor_;
        _setExecutionGasLimit(executionGasLimit_);
        _setMinimumGasToAttempt(_DEFAULT_MINIMUM_GAS_TO_ATTEMPT);
        _setGasReserve(_DEFAULT_GAS_RESERVE);
    }

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - The installed ROLES module has an incompatible major version.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = Module(address(ROLES)).VERSION();
        if (rolesMajor != 1) revert Policy_WrongModuleVersion(abi.encode([1]));
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @inheritdoc IPeriodicTask
    /// @dev Reverts if:
    ///      - The caller lacks the Heart role.
    ///      Internal task failures are caught and emitted as `ExecutionFailed`; a Kernel-inactive
    ///      or locally disabled task returns without settlement.
    function execute() external override onlyRole(HEART_ROLE) {
        if (!kernel.isPolicyActive(Policy(address(this))) || !isEnabled) return;
        (bool success, bytes memory reason) = address(this).safeCall(
            executionGasLimit,
            0,
            _MAX_RETURN_DATA_BYTES,
            abi.encodeCall(this.selfExecuteTask, ())
        );
        // SafeCall bounds reason to four bytes.
        // forge-lint: disable-next-line(unsafe-typecast)
        if (!success) emit ExecutionFailed(bytes4(reason));
    }

    /// @inheritdoc IRevenueDistributorTask
    /// @dev Reverts if:
    ///      - The caller is not this task contract.
    ///      In production, this function is reached only through `execute`, which verifies that
    ///      this task is Kernel-active and locally enabled before making the external self-call.
    ///      Returns without settlement while the bound distributor is Kernel-inactive or locally
    ///      disabled. Otherwise, attempts active assets until each has been visited or the execution
    ///      budget is too low for another isolated call.
    function selfExecuteTask() external override {
        if (msg.sender != address(this)) revert RevenueDistributorTask_OnlySelf();
        if (!kernel.isPolicyActive(Policy(_DISTRIBUTOR)) || !IEnabler(_DISTRIBUTOR).isEnabled())
            return;
        uint256 count = IRevenueDistributor(_DISTRIBUTOR).getActiveAssetCount();
        if (count == 0) return;
        uint256 index = _nextAssetIndex % count;
        for (uint256 attempted; attempted < count; ++attempted) {
            if (gasleft() <= minimumGasToAttempt) break;
            // Indexed reads avoid copying an unbounded active-asset array into this task.
            // forge-lint: disable-next-line(calls-loop)
            address asset = IRevenueDistributor(_DISTRIBUTOR).getActiveAssetAt(index);
            bytes memory callData = abi.encodeCall(IRevenueDistributor.distribute, (asset));
            uint256 availableGas = gasleft();
            // Read gas again after the external indexed lookup. Its cost varies by distributor
            // implementation; the current value is needed to preserve the cleanup reserve.
            if (availableGas <= gasReserve) break;
            // Wrap the cursor to the first asset after the last active asset. Advance before
            // the external call so even a failed distribution is not retried on this beat.
            index = (index + 1) % count;
            // forge-lint: disable-next-line(costly-loop)
            _nextAssetIndex = index;
            (bool success, bytes memory reason) = _DISTRIBUTOR.safeCall(
                availableGas - gasReserve,
                0,
                _MAX_RETURN_DATA_BYTES,
                callData
            );
            if (!success) {
                // forge-lint: disable-next-line(unsafe-typecast)
                emit AssetDistributionFailed(asset, bytes4(reason));
            }
        }
    }

    /// @inheritdoc IRevenueDistributorTask
    /// @dev Reverts if:
    ///      - The caller lacks admin and revenue_distributor_admin roles.
    ///      - This task is Kernel-inactive.
    ///      - The gas limit is zero.
    ///      Callable while locally disabled.
    function setExecutionGasLimit(uint32 gasLimit_) external override {
        _requireDistributorAdmin();
        _requirePolicyActive();
        _setExecutionGasLimit(gasLimit_);
    }

    /// @inheritdoc IRevenueDistributorTask
    /// @dev Reverts if:
    ///      - The caller lacks admin and revenue_distributor_admin roles.
    ///      - This task is Kernel-inactive.
    ///      - The threshold is at or below the cleanup reserve.
    ///      Callable while locally disabled so governance can tune the next execution.
    function setMinimumGasToAttempt(uint32 gasLimit_) external override {
        _requireDistributorAdmin();
        _requirePolicyActive();
        _setMinimumGasToAttempt(gasLimit_);
    }

    /// @inheritdoc IRevenueDistributorTask
    /// @dev Reverts if:
    ///      - The caller lacks admin and revenue_distributor_admin roles.
    ///      - This task is Kernel-inactive.
    ///      - The reserve is zero or at or above the current attempt threshold.
    ///      Callable while locally disabled.
    function setGasReserve(uint32 gasLimit_) external override {
        _requireDistributorAdmin();
        _requirePolicyActive();
        _setGasReserve(gasLimit_);
    }

    /// @inheritdoc IRevenueDistributorTask
    /// @dev Reverts if:
    ///      - The caller lacks admin and revenue_distributor_admin roles.
    ///      - This task is Kernel-inactive.
    ///      - The index is nonzero and outside the active asset set.
    ///      Callable while locally disabled so governance can select the next asset before
    ///      re-enabling.
    function setNextAssetIndex(uint256 index_) external override {
        _requireDistributorAdmin();
        _requirePolicyActive();
        uint256 count = IRevenueDistributor(_DISTRIBUTOR).getActiveAssetCount();
        if (index_ != 0 && index_ >= count) {
            revert RevenueDistributorTask_InvalidAssetIndex(index_, count);
        }
        if (index_ == _nextAssetIndex) return;
        _nextAssetIndex = index_;
        emit NextAssetIndexSet(index_);
    }

    /// @inheritdoc IRevenueDistributorTask
    function distributor() external view override returns (address) {
        return _DISTRIBUTOR;
    }

    /// @inheritdoc IRevenueDistributorTask
    function nextAssetIndex() external view override returns (uint256) {
        return _nextAssetIndex;
    }

    /// @dev Reverts if:
    ///      - The caller lacks admin and revenue_distributor_admin roles.
    function _authorizeReEnable() internal view override {
        _requireDistributorAdmin();
    }

    /// @dev Reverts if:
    ///      - The caller lacks the admin role.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @dev Reverts if:
    ///      - The bound distributor is Kernel-inactive or locally disabled.
    function _beforeEnable(bytes calldata) internal view override {
        _requireDistributorAvailable();
    }

    /// @dev Reverts if:
    ///      - The re-enable grace period has expired.
    ///      - The bound distributor is Kernel-inactive or locally disabled.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requireDistributorAvailable();
    }

    /// @dev Reverts if:
    ///      - The constructor-bound distributor is Kernel-inactive or locally disabled.
    function _requireDistributorAvailable() internal view {
        if (!kernel.isPolicyActive(Policy(_DISTRIBUTOR)) || !IEnabler(_DISTRIBUTOR).isEnabled()) {
            revert RevenueDistributorTask_InvalidDistributor(_DISTRIBUTOR);
        }
    }

    /// @dev Reverts if this task is not active in its current Kernel.
    function _requirePolicyActive() internal view {
        if (!kernel.isPolicyActive(Policy(address(this)))) {
            revert RevenueDistributorTask_PolicyInactive();
        }
    }

    /// @dev Reverts if:
    ///      - The caller lacks admin and revenue_distributor_admin roles.
    function _requireDistributorAdmin() internal view {
        _requireAuthorized(
            !_isAdmin(msg.sender) && !_hasRole(msg.sender, REVENUE_DISTRIBUTOR_ADMIN_ROLE)
        );
    }

    /// @inheritdoc IPeriodicTask
    function supportsInterface(
        bytes4 interfaceId_
    ) public view override(EnablerV2, ReEnablerGracePeriod, IPeriodicTask) returns (bool) {
        return
            interfaceId_ == type(IPeriodicTask).interfaceId ||
            interfaceId_ == type(IRevenueDistributorTask).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @dev Reverts if:
    ///      - The complete-task gas limit is zero.
    ///      Stores and emits a changed valid limit; an unchanged valid limit is a no-op.
    function _setExecutionGasLimit(uint32 gasLimit_) internal {
        if (gasLimit_ == 0) revert RevenueDistributorTask_InvalidExecutionGasLimit();
        if (gasLimit_ == executionGasLimit) return;
        executionGasLimit = gasLimit_;
        emit ExecutionGasLimitSet(gasLimit_);
    }

    /// @dev Reverts if:
    ///      - The threshold is at or below the cleanup reserve.
    ///      Stores and emits a changed valid threshold; an unchanged valid threshold is a no-op.
    function _setMinimumGasToAttempt(uint32 gasLimit_) internal {
        if (gasLimit_ <= gasReserve) {
            revert RevenueDistributorTask_InvalidMinimumGasToAttempt();
        }
        if (gasLimit_ == minimumGasToAttempt) return;
        minimumGasToAttempt = gasLimit_;
        emit MinimumGasToAttemptSet(gasLimit_);
    }

    /// @dev Reverts if:
    ///      - The reserve is zero or at or above the minimum attempt threshold.
    ///      Stores and emits a changed valid reserve; an unchanged valid reserve is a no-op.
    function _setGasReserve(uint32 gasLimit_) internal {
        if (gasLimit_ == 0 || gasLimit_ >= minimumGasToAttempt) {
            revert RevenueDistributorTask_InvalidGasReserve();
        }
        if (gasLimit_ == gasReserve) return;
        gasReserve = gasLimit_;
        emit GasReserveSet(gasLimit_);
    }
}
