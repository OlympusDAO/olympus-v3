// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansSeize} from "src/policies/interfaces/burnerloans/IBurnerLoansSeize.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin-5.7.0/utils/structs/EnumerableSet.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeCall} from "src/libraries/SafeCall.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

/// @title Burner Loans Seizer Task
/// @notice Heart task for bounded round-robin seizure.
/// @dev Gas-bounded scan and seizure failures are isolated from the Heart transaction
///      so later periodic tasks remain runnable.
contract BurnerLoansSeizerTask is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    IBurnerLoansSeizerTask,
    IVersioned,
    IPeriodicTask
{
    using SafeCall for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Maximum revert data copied from the gas-bounded self-call.
    uint16 internal constant _MAX_RETURN_DATA_BYTES = 4;

    /// @dev Reserve enough outer-call gas to persist rotation and report a failed task body.
    uint32 internal constant _TASK_GAS_RESERVE = 50_000;

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Core identity is derived from this bound Seize action when needed.
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    IBurnerLoansSeize public immutable override seize;

    /// @dev Immutable read-only scan helper; Core does not select Lens.
    IBurnerLoansLens internal immutable _LENS;

    /// @inheritdoc IBurnerLoansSeizerTask
    uint16 public override maxBorrowersToCheck;

    /// @inheritdoc IBurnerLoansSeizerTask
    uint8 public override maxBorrowersToSeize;

    /// @inheritdoc IBurnerLoansSeizerTask
    uint32 public override executionGasLimit;

    /// @inheritdoc IBurnerLoansSeizerTask
    uint256 public override nextAssetIndex;

    /// @inheritdoc IBurnerLoansSeizerTask
    mapping(address => uint256) public override assetCursor;

    /// @dev Collateral assets included in round-robin scanning.
    EnumerableSet.AddressSet private _assets;

    /// @notice Deploys a gas-bounded Heart task for a same-Kernel Burner Loans policy.
    /// @dev Reverts if:
    ///      - Seize is invalid or reports another Kernel, Lens reports a different
    ///      Core binding, or any initial execution/scan limit is invalid.
    /// @param kernel_ Kernel shared with the Burner Loans target.
    /// @param seize_ Public Core-bound Seize entry point.
    /// @param lens_ Read-only scan helper bound to that same Core.
    /// @param maxBorrowersToCheck_ Maximum positions checked per asset.
    /// @param maxBorrowersToSeize_ Maximum eligible borrowers returned per batch.
    /// @param executionGasLimit_ Complete task self-call gas budget.
    constructor(
        Kernel kernel_,
        IBurnerLoansSeize seize_,
        IBurnerLoansLens lens_,
        uint16 maxBorrowersToCheck_,
        uint8 maxBorrowersToSeize_,
        uint32 executionGasLimit_
    ) Policy(kernel_) ReEnablerGracePeriod(LoanParameters._REENABLE_GRACE_PERIOD) {
        _LENS = lens_;
        seize = seize_;
        _validateBindings();
        _setScanLimits(maxBorrowersToCheck_, maxBorrowersToSeize_);
        _setExecutionGasLimit(executionGasLimit_);
    }

    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    modifier onlyActive() {
        _requireOwnPolicyActive();
        _;
    }

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - A declared module is missing.
    ///      - A declared module has an incompatible version.
    ///
    /// @dev Resolves the declared modules through this contract's Kernel; dependency errors propagate.
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
    /// @dev Declares only the listed module selectors; no dynamic permissions or token approvals.
    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    /// @dev Reports this implementation's interface version; does not query dependencies or alter lifecycle.
    function VERSION() external pure override returns (uint8, uint8) {
        return (1, 0);
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Reverts if:
    ///      - The caller lacks ADMIN.
    ///      - The asset is already managed.
    ///      - Core has not registered the asset, even if it is an otherwise valid token.
    function addAsset(address asset_) external override onlyActive onlyAdminRole {
        if (!_assets.add(asset_)) revert BurnerLoansSeizer_AssetAlreadyManaged(asset_);
        if (
            !IBurnerLoansCore(IBurnerLoansCoreBound(address(seize)).core()).isAssetRegistered(
                asset_
            )
        ) revert IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured(asset_);
        emit AssetAdded(asset_);
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Reverts if:
    ///      - The caller lacks ADMIN.
    ///      - The asset is not managed.
    function removeAsset(address asset_) external override onlyActive onlyAdminRole {
        if (!_assets.remove(asset_)) revert BurnerLoansSeizer_AssetNotManaged(asset_);
        delete assetCursor[asset_];

        uint256 remaining = _assets.length();
        if (remaining == 0) nextAssetIndex = 0;
        else if (nextAssetIndex >= remaining) nextAssetIndex %= remaining;
        emit AssetRemoved(asset_);
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Reverts if:
    ///      - The caller lacks ADMIN and burner_loans_admin.
    ///      - Either limit is zero.
    ///      - The seizure limit exceeds the scan limit.
    function setScanLimits(
        uint16 maxBorrowersToCheck_,
        uint8 maxBorrowersToSeize_
    ) external override {
        _requireOwnPolicyActive();

        _requireAdminOrBurnerLoansAdmin();
        _setScanLimits(maxBorrowersToCheck_, maxBorrowersToSeize_);
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Reverts if:
    ///      - The caller lacks ADMIN and burner_loans_admin.
    ///      - The execution gas limit is zero.
    function setExecutionGasLimit(uint32 executionGasLimit_) external override {
        _requireOwnPolicyActive();

        _requireAdminOrBurnerLoansAdmin();
        _setExecutionGasLimit(executionGasLimit_);
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive, the caller holds neither ADMIN nor
    ///      burner_loans_admin, or a nonzero index is outside the managed set. Callable while
    ///      disabled. Zero requires no downstream reads; unchanged indices emit no event.
    function setNextAssetIndex(uint256 index_) external override {
        _requireOwnPolicyActive();
        _requireAdminOrBurnerLoansAdmin();
        uint256 count = _assets.length();
        if (index_ != 0 && index_ >= count)
            revert BurnerLoansSeizer_InvalidAssetIndex(index_, count);
        if (nextAssetIndex == index_) return;
        nextAssetIndex = index_;
        emit NextAssetIndexSet(index_);
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive, the caller holds neither ADMIN nor
    ///      burner_loans_admin, or the asset is unmanaged. A nonzero cursor uses a zero-sized
    ///      Lens scan for canonical bounds validation; its errors propagate without writes.
    ///      Zero resets need no downstream reads. Callable while disabled; unchanged valid
    ///      cursors emit no event.
    function setNextAssetBorrowerIndex(address asset_, uint256 index_) external override {
        _requireOwnPolicyActive();
        _requireAdminOrBurnerLoansAdmin();
        if (!_assets.contains(asset_)) revert BurnerLoansSeizer_AssetNotManaged(asset_);
        if (index_ != 0) {
            // Only bounds validation is needed; no positions, Risk or prices are inspected.
            // The zero-sized page's return values are intentionally unused.
            // forge-lint: disable-next-line(unused-return)
            _LENS.getSeizableBorrowersBoundedFor(address(this), asset_, index_, 0, 0);
        }
        if (assetCursor[asset_] == index_) return;
        assetCursor[asset_] = index_;
        emit AssetCursorSet(asset_, index_);
    }

    /// @inheritdoc IPeriodicTask
    /// @dev Reverts if:
    ///      - The caller lacks HEART_ROLE.
    ///      - This policy is inactive in its Kernel, including while disabled.
    ///      - Reading an uninitialized/failed ROLES dependency fails.
    ///      Disabled execution returns immediately; bounded task failures emit ExecutionFailed and are caught.
    function execute() external override onlyActive onlyRole(HEART_ROLE) {
        if (!isEnabled) return;

        bool success;
        bytes memory reason;
        // Keep failure reporting outside the metered self-call. An out-of-gas scan or seizure rolls
        // back that inner call without consuming the reserve needed to rotate assets and return to Heart.
        uint256 availableGas = gasleft();
        if (availableGas > _TASK_GAS_RESERVE) {
            uint256 bodyGas = availableGas - _TASK_GAS_RESERVE;
            if (bodyGas > executionGasLimit) bodyGas = executionGasLimit;
            (success, reason) = address(this).safeCall(
                bodyGas,
                0,
                _MAX_RETURN_DATA_BYTES,
                abi.encodeCall(this.selfExecuteTask, ())
            );
        }
        if (!success) {
            // The failed self-call rolled back its asset rotation. Advance here so a
            // gas-exhausting asset cannot monopolize subsequent Heart beats.
            uint256 assetCount = _assets.length();
            if (assetCount != 0) nextAssetIndex = ((nextAssetIndex % assetCount) + 1) % assetCount;
            // SafeCall copies at most four bytes; selector truncation is intentional.
            // forge-lint: disable-next-line(unsafe-typecast)
            emit ExecutionFailed(bytes4(reason));
        }
    }

    /// @notice Runs the gas-bounded task body through an external self-call.
    /// @dev Reverts if:
    ///      - The gas-bounded task body was called by an account other than this contract.
    ///      - This policy is inactive in its Kernel.
    function selfExecuteTask() external {
        if (msg.sender != address(this)) revert BurnerLoansSeizer_OnlySelf();
        _requireOwnPolicyActive();
        _scanAndSeize();
    }

    /// @dev Scans and optionally seizes one managed asset. All external failures are reported.
    function _scanAndSeize() private {
        uint256 assetCount = _assets.length();
        if (assetCount == 0) return;

        // Advance the asset cursor before external work so every successful Heart tick rotates
        // fairly even when scanning or seizure later fails for this asset.
        uint256 assetIndex = nextAssetIndex % assetCount;
        address asset = _assets.at(assetIndex);
        nextAssetIndex = assetIndex + 1 == assetCount ? 0 : assetIndex + 1;

        if (!_hasRole(address(this), BURNER_LOANS_SEIZER_ROLE)) {
            emit SeizerRoleMissing(asset);
            return;
        }

        _scanAsset(asset, assetCursor[asset]);
    }

    /// @dev Checks a nonzero cursor against the live borrower count before one bounded scan.
    ///      Count, scan and seizure failures are isolated to this asset visit.
    function _scanAsset(address asset, uint256 startIndex) private {
        if (startIndex != 0) {
            try _LENS.getActiveBorrowerCount(asset) returns (uint256 population) {
                if (startIndex >= population) {
                    startIndex = 0;
                    assetCursor[asset] = 0;
                }
            } catch (bytes memory reason) {
                // Only the error selector is reported; preserve the saved cursor on read failure.
                // forge-lint: disable-next-line(unsafe-typecast)
                emit ScanFailed(asset, bytes4(reason));
                return;
            }
        }
        // Quote as this task, not Heart or the transaction sender: protocol seizers earn no keeper
        // incentive. The Lens independently bounds inspected borrowers and the returned seizure batch.
        try
            _LENS.getSeizableBorrowersBoundedFor(
                address(this),
                asset,
                startIndex,
                maxBorrowersToCheck,
                maxBorrowersToSeize
            )
        returns (address[] memory borrowers, uint256 scannedNextIndex, uint256) {
            if (borrowers.length == 0) {
                assetCursor[asset] = scannedNextIndex;
                emit SeizureExecuted(asset, startIndex, scannedNextIndex, 0);
                return;
            }

            // Cursor state must remain unchanged on failure. The bound policy cannot cross the
            // self-only task boundary during a callback.
            // forge-lint: disable-next-line(reentrancy-no-eth)
            try seize.seize(asset, borrowers) {
                // Debt closure removes up to one active-borrower entry per selected borrower.
                // Rewind by that upper bound so swap-and-pop compaction cannot leave an
                // out-of-range cursor. Earlier swapped entries remain reachable after wrap.
                uint256 nextIndex = scannedNextIndex > borrowers.length
                    ? scannedNextIndex - borrowers.length
                    : 0;
                assetCursor[asset] = nextIndex;
                emit SeizureExecuted(asset, startIndex, nextIndex, borrowers.length);
            } catch (bytes memory reason) {
                // The event intentionally reports only the first four bytes of revert data.
                // forge-lint: disable-next-line(unsafe-typecast)
                emit SeizureFailed(asset, bytes4(reason));
            }
        } catch (bytes memory reason) {
            // The event intentionally reports only the first four bytes of revert data.
            // forge-lint: disable-next-line(unsafe-typecast)
            emit ScanFailed(asset, bytes4(reason));
        }
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Reads without state changes; errors from dependency views propagate.
    function isAssetManaged(address asset_) external view override returns (bool) {
        return _assets.contains(asset_);
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Reads without state changes; errors from dependency views propagate.
    function getAssets() external view override returns (address[] memory) {
        return _assets.values();
    }

    /// @notice Requires governance ADMIN or delegated Burner Loans administration.
    /// @dev Reverts if:
    ///      - The caller holds neither ADMIN nor burner_loans_admin.
    function _requireAdminOrBurnerLoansAdmin() private view {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
    }

    /// @notice Authorizes a re-enable transition during the grace period.
    /// @dev Reverts if:
    ///      - The caller holds neither ADMIN nor burner_loans_admin.
    function _authorizeReEnable() internal view override {
        _requireAdminOrBurnerLoansAdmin();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - This policy is locally disabled.
    ///      - The caller lacks ADMIN.
    ///      - The requested period is zero.
    function setGracePeriod(uint32 period_) public override onlyActive {
        super.setGracePeriod(period_);
    }

    /// @dev The public setter applies activity and local enablement before authorization.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @dev Revalidates Seize/Lens bindings and direct Seize readiness before enablement.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();

        _requireSeizeReady();
    }

    /// @dev Preserves the grace-period gate and revalidates Seize before re-enabling.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requireSeizeReady();
    }

    /// @dev Seize is the operational dependency; its own checks govern downstream readiness.
    function _requireSeizeReady() private view {
        _requireOwnPolicyActive();
        _validateBindings();
        if (!kernel.isPolicyActive(Policy(address(seize))) || !IEnabler(address(seize)).isEnabled())
            revert PolicyDependency.PolicyDependency_NotActive(address(seize));
    }

    /// @dev Validate the direct Seize dependency and its shared Core identity with Lens.
    ///      Seize owns validation of Core's interface and Kernel; Task does not repeat it.
    function _validateBindings() private view {
        address action = address(seize);
        if (
            action == address(0) ||
            !ERC165Checker.supportsInterface(action, type(IBurnerLoansSeize).interfaceId)
        ) revert BurnerLoansSeizer_InvalidSeize(action);
        address core = IBurnerLoansCoreBound(address(seize)).core();
        // Kernel migration leaves old membership entries intact; activity cannot prove this binding.
        PolicyDependency.requireSameKernel(action, address(kernel));
        if (address(_LENS).code.length == 0 || IBurnerLoansCoreBound(address(_LENS)).core() != core)
            revert BurnerLoansSeizer_InvalidLens(address(_LENS));
    }

    /// @inheritdoc IPeriodicTask
    /// @dev Pure interface identifiers or inherited lifecycle identifiers only; no dependency calls.
    function supportsInterface(
        bytes4 interfaceId_
    ) public view override(EnablerV2, ReEnablerGracePeriod, IPeriodicTask) returns (bool) {
        return
            interfaceId_ == type(IPeriodicTask).interfaceId ||
            interfaceId_ == type(IBurnerLoansSeizerTask).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @notice Stores validated nonzero scan and seizure limits.
    /// @dev Reverts if:
    ///      - Either limit is zero.
    ///      - The seizure limit exceeds the scan limit.
    /// @param maxBorrowersToCheck_ Maximum positions checked per asset.
    /// @param maxBorrowersToSeize_ Maximum eligible borrowers returned per batch.
    function _setScanLimits(uint16 maxBorrowersToCheck_, uint8 maxBorrowersToSeize_) private {
        if (
            maxBorrowersToCheck_ == 0 ||
            maxBorrowersToSeize_ == 0 ||
            maxBorrowersToSeize_ > maxBorrowersToCheck_
        ) {
            revert BurnerLoansSeizer_InvalidScanLimits(maxBorrowersToCheck_, maxBorrowersToSeize_);
        }
        if (
            maxBorrowersToCheck == maxBorrowersToCheck_ &&
            maxBorrowersToSeize == maxBorrowersToSeize_
        ) return;
        maxBorrowersToCheck = maxBorrowersToCheck_;
        maxBorrowersToSeize = maxBorrowersToSeize_;
        emit ScanLimitsSet(maxBorrowersToCheck_, maxBorrowersToSeize_);
    }

    /// @notice Stores the gas forwarded to the fail-soft self-call.
    /// @dev Reverts if:
    ///      - `executionGasLimit_` is zero.
    /// @param executionGasLimit_ Complete task self-call gas budget.
    function _setExecutionGasLimit(uint32 executionGasLimit_) private {
        if (executionGasLimit_ == 0) revert BurnerLoansSeizer_InvalidExecutionGasLimit();
        if (executionGasLimit == executionGasLimit_) return;
        executionGasLimit = executionGasLimit_;
        emit ExecutionGasLimitSet(executionGasLimit_);
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    function lens() external view returns (address) {
        return address(_LENS);
    }

    /// @notice Validates a local pause payload without requiring downstream readiness.
    /// @dev Reverts if:
    ///      - Data is nonempty; Kernel inactivity does not prevent disable.
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
    }

    /// @notice Applies checked narrowing to the product's inclusive grace deadline.
    /// @dev Reverts if:
    ///      - The deadline overflows uint48 or the grace window has expired.
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }

    /// @notice Checks this policy's own Kernel membership before mutation/activation.
    /// @dev Reverts if:
    ///      - This subject policy is inactive.
    function _requireOwnPolicyActive() private view {
        if (!kernel.isPolicyActive(this))
            revert IBurnerLoansErrors.BurnerLoans_PolicyNotActive(address(this));
    }
}
