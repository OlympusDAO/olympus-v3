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
    mapping(address => uint256) public override expiredAssetCursor;

    /// @inheritdoc IBurnerLoansSeizerTask
    mapping(address => uint256) public override unhealthyAssetCursor;

    /// @dev If true, scan this asset's unhealthy borrowers first on its next visit.
    mapping(address => bool) private _scanUnhealthyFirst;

    /// @dev Collateral assets included in round-robin scanning.
    EnumerableSet.AddressSet private _assets;

    /// @notice Deploys a gas-bounded Heart task for a same-Kernel Burner Loans policy.
    /// @dev Reverts if:
    ///      - Seize is invalid or reports another Kernel, Lens reports a different
    ///      Core binding, Core lacks IBurnerLoansCore, or an initial execution/scan limit is invalid.
    /// @param kernel_ Kernel shared with the Burner Loans target.
    /// @param seize_ Public Core-bound Seize entry point.
    /// @param lens_ Read-only scan helper bound to that same Core.
    /// @param maxBorrowersToCheck_ Maximum borrowers checked by each discovery lane per asset visit.
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
    ///      Does not intentionally revert.
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
    ///      Does not intentionally revert.
    function VERSION() external pure override returns (uint8, uint8) {
        return (1, 0);
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - The caller lacks ADMIN.
    ///      - The asset is already managed.
    ///      - Core has not registered the asset, even if it is an otherwise valid token.
    ///      - Reading caller roles or the Core binding/asset registration fails.
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
    ///      - This policy is Kernel-inactive.
    ///      - The caller lacks ADMIN.
    ///      - The asset is not managed.
    ///      - Reading caller roles fails.
    function removeAsset(address asset_) external override onlyActive onlyAdminRole {
        if (!_assets.remove(asset_)) revert BurnerLoansSeizer_AssetNotManaged(asset_);
        delete expiredAssetCursor[asset_];
        delete unhealthyAssetCursor[asset_];
        delete _scanUnhealthyFirst[asset_];

        uint256 remaining = _assets.length();
        if (remaining == 0) nextAssetIndex = 0;
        else if (nextAssetIndex >= remaining) nextAssetIndex %= remaining;
        emit AssetRemoved(asset_);
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - The caller lacks ADMIN and burner_loans_admin.
    ///      - Either limit is zero.
    ///      - The seizure limit exceeds the scan limit.
    ///      - Reading caller roles fails.
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
    ///      - This policy is Kernel-inactive.
    ///      - The caller lacks ADMIN and burner_loans_admin.
    ///      - The execution gas limit is zero.
    ///      - Reading caller roles fails.
    function setExecutionGasLimit(uint32 executionGasLimit_) external override {
        _requireOwnPolicyActive();

        _requireAdminOrBurnerLoansAdmin();
        _setExecutionGasLimit(executionGasLimit_);
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - The caller holds neither ADMIN nor burner_loans_admin, or reading roles fails.
    ///      - A nonzero index is outside the managed asset set.
    ///      Callable while disabled. Zero needs no borrower reads; unchanged indices emit no event.
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
    ///      - This policy is Kernel-inactive.
    ///      - The caller holds neither ADMIN nor burner_loans_admin, or reading roles fails.
    ///      - The asset is not managed.
    ///      - A nonzero offset is outside the active-borrower list, or Lens cannot validate it.
    ///      Callable while disabled. Zero needs no borrower reads; unchanged offsets emit no event.
    function setExpiredAssetCursor(address asset_, uint256 index_) external override {
        _setAssetBorrowerCursor(asset_, index_, true);
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - The caller holds neither ADMIN nor burner_loans_admin, or reading roles fails.
    ///      - The asset is not managed.
    ///      - A nonzero offset is outside the active-borrower list, or Lens cannot validate it.
    ///      Callable while disabled. Zero needs no borrower reads; unchanged offsets emit no event.
    function setUnhealthyAssetCursor(address asset_, uint256 index_) external override {
        _setAssetBorrowerCursor(asset_, index_, false);
    }

    /// @notice Validates the selected lane before equality; zero needs no downstream reads.
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - The caller holds neither ADMIN nor burner_loans_admin, or reading roles fails.
    ///      - The asset is not managed.
    ///      - A nonzero offset is outside the active-borrower list, or Lens cannot validate it.
    function _setAssetBorrowerCursor(address asset_, uint256 index_, bool expired_) private {
        _requireOwnPolicyActive();
        _requireAdminOrBurnerLoansAdmin();
        if (!_assets.contains(asset_)) revert BurnerLoansSeizer_AssetNotManaged(asset_);
        if (index_ != 0) {
            // Bounds only: no positions, Risk or prices are inspected.
            // forge-lint: disable-next-line(unused-return)
            _LENS.getSeizableBorrowersBoundedFor(address(this), asset_, index_, 0, 0);
        }
        if (expired_) {
            if (expiredAssetCursor[asset_] == index_) return;
            expiredAssetCursor[asset_] = index_;
        } else {
            if (unhealthyAssetCursor[asset_] == index_) return;
            unhealthyAssetCursor[asset_] = index_;
        }
        emit AssetCursorSet(
            asset_,
            index_,
            expired_ ? IBurnerLoansLens.Selection.Expired : IBurnerLoansLens.Selection.Unhealthy
        );
    }

    /// @inheritdoc IPeriodicTask
    /// @dev Reverts if:
    ///      - The caller lacks HEART_ROLE.
    ///      - This policy is inactive in its Kernel, including while disabled.
    ///      - Reading an uninitialized/failed ROLES dependency fails.
    ///      Disabled execution returns immediately; bounded task failures emit ExecutionFailed and are caught.
    function execute() external override onlyActive onlyRole(HEART_ROLE) {
        if (!isEnabled) return;

        // Keep lane fairness even if the entire body exhausts gas. Each asset needs its own turn:
        // a single global toggle would pin every asset to one lane when the asset count is even.
        uint256 scheduledAssets = _assets.length();
        address scheduledAsset;
        if (scheduledAssets != 0) {
            scheduledAsset = _assets.at(nextAssetIndex % scheduledAssets);
        }

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
            // The reserve covers this write and failed-body asset rotation. A call too short to
            // enter the body must retain enough gas for the original fail-soft cleanup path.
            if (scheduledAssets != 0 && _assets.contains(scheduledAsset))
                _scanUnhealthyFirst[scheduledAsset] = !_scanUnhealthyFirst[scheduledAsset];
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

    /// @notice Scans and optionally seizes one managed asset.
    /// @dev Reverts if:
    ///      - Reading the task's seizer role fails.
    ///      - Returned scan data is malformed or the task body exhausts gas.
    ///      Other count, discovery and settlement failures are caught and reported.
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

        _scanAsset(asset);
    }

    /// @notice Alternates preferred lanes per asset. Empty pages permit the other lane; failed
    ///      priced discovery permits expiry discovery while retaining its unhealthy cursor.
    /// @dev Reverts if:
    ///      - Returned scan data is malformed or the task body exhausts gas.
    ///      Other count, discovery and settlement failures are caught and reported.
    function _scanAsset(address asset) private {
        uint256 expiredStartIndex = expiredAssetCursor[asset];
        uint256 unhealthyStartIndex = unhealthyAssetCursor[asset];
        if (expiredStartIndex != 0 || unhealthyStartIndex != 0) {
            try _LENS.getActiveBorrowerCount(asset) returns (uint256 population) {
                if (expiredStartIndex >= population) {
                    expiredStartIndex = 0;
                    expiredAssetCursor[asset] = 0;
                }
                if (unhealthyStartIndex >= population) {
                    unhealthyStartIndex = 0;
                    unhealthyAssetCursor[asset] = 0;
                }
            } catch (bytes memory reason) {
                // The count must be authoritative before repairing a stale cursor.
                // forge-lint: disable-next-line(unsafe-typecast)
                emit ScanFailed(asset, bytes4(reason));
                return;
            }
        }

        if (!_scanUnhealthyFirst[asset]) {
            if (_scanExpired(asset, expiredStartIndex)) return;
            _scanUnhealthy(asset, unhealthyStartIndex);
        } else {
            if (_scanUnhealthy(asset, unhealthyStartIndex)) return;
            _scanExpired(asset, expiredStartIndex);
        }
    }

    /// @notice A selected batch consumes the visit, whether it settles or is rejected.
    /// @dev Reverts if:
    ///      - Returned scan data is malformed or the task body exhausts gas.
    ///      Caught dependency errors emit ScanFailed or SeizureFailed instead.
    function _scanExpired(address asset, uint256 expiredStartIndex) private returns (bool) {
        try
            _LENS.getExpiredBorrowersBoundedFor(
                address(this),
                asset,
                expiredStartIndex,
                maxBorrowersToCheck,
                maxBorrowersToSeize
            )
        returns (address[] memory borrowers, uint256 scannedNextIndex, uint256) {
            if (borrowers.length != 0) {
                _seizeScannedBorrowers(
                    asset,
                    expiredStartIndex,
                    borrowers,
                    scannedNextIndex,
                    IBurnerLoansLens.Selection.Expired
                );
                return true;
            }
            expiredAssetCursor[asset] = scannedNextIndex;
        } catch (bytes memory reason) {
            // FLOAN reads and custody/Risk quote failures retain the retry cursor.
            // forge-lint: disable-next-line(unsafe-typecast)
            emit ScanFailed(asset, bytes4(reason));
            return true;
        }
        return false;
    }

    /// @notice A failed priced scan retains pending work and permits same-visit expiry discovery.
    /// @dev Reverts if:
    ///      - Returned scan data is malformed or the task body exhausts gas.
    ///      Caught dependency errors emit ScanFailed or SeizureFailed instead.
    function _scanUnhealthy(address asset, uint256 unhealthyStartIndex) private returns (bool) {
        try
            _LENS.getUnhealthyBorrowersBoundedFor(
                address(this),
                asset,
                unhealthyStartIndex,
                maxBorrowersToCheck,
                maxBorrowersToSeize
            )
        returns (address[] memory borrowers, uint256 scannedNextIndex, uint256) {
            _seizeScannedBorrowers(
                asset,
                unhealthyStartIndex,
                borrowers,
                scannedNextIndex,
                IBurnerLoansLens.Selection.Unhealthy
            );
            return borrowers.length != 0;
        } catch (bytes memory reason) {
            // Preserve the unhealthy retry cursor and the successful expiry scan's progress.
            // forge-lint: disable-next-line(unsafe-typecast)
            emit ScanFailed(asset, bytes4(reason));
        }
        return false;
    }

    /// @dev Applies identical progress and atomic settlement rules to either discovery mode.
    ///      Seize call failures are caught here; local failures escape to execute's self-call boundary.
    ///      No contract-defined reverts; gas exhaustion rolls back the complete task body.
    function _seizeScannedBorrowers(
        address asset_,
        uint256 startIndex_,
        address[] memory borrowers_,
        uint256 scannedNextIndex_,
        IBurnerLoansLens.Selection selection_
    ) private {
        if (borrowers_.length == 0) {
            if (selection_ == IBurnerLoansLens.Selection.Expired)
                expiredAssetCursor[asset_] = scannedNextIndex_;
            else unhealthyAssetCursor[asset_] = scannedNextIndex_;
            emit SeizureExecuted(asset_, selection_, startIndex_, scannedNextIndex_, 0);
            return;
        }

        // Seize retains all admission, custody and atomic batch checks.
        // forge-lint: disable-next-line(reentrancy-no-eth)
        try seize.seize(asset_, borrowers_) {
            // Rewind by the maximum number of removals so swap-and-pop cannot strand a suffix.
            // Earlier swapped entries remain reachable after wrap; an end cursor stays zero.
            uint256 nextIndex = scannedNextIndex_ > borrowers_.length
                ? scannedNextIndex_ - borrowers_.length
                : 0;
            if (selection_ == IBurnerLoansLens.Selection.Expired) {
                expiredAssetCursor[asset_] = nextIndex;
            } else {
                unhealthyAssetCursor[asset_] = nextIndex;
            }
            emit SeizureExecuted(asset_, selection_, startIndex_, nextIndex, borrowers_.length);
        } catch (bytes memory reason) {
            // Report the error category only. Seize's full pricing-cause bytes remain available
            // in a call trace or direct Seize revert, rather than in this four-byte event field.
            // forge-lint: disable-next-line(unsafe-typecast)
            emit SeizureFailed(asset_, bytes4(reason));
            if (_isPriceFailure(selection_, reason)) {
                // Leave unhealthyAssetCursor[asset_] unchanged: every borrower needs the same
                // unavailable prices, so passing this position cannot make the next one settle.
                return;
            }
            // Pass only one active-list offset after an ordinary seizure failure, not the whole
            // page: other candidates may still settle. Admin can recover persistent failures with
            // the cursor setter and a smaller batch limit; this visit makes no second attempt.
            _advanceRejectedCursor(asset_, startIndex_, selection_);
        }
    }

    /// @dev Advances one saved offset after a non-price seizure failure, not the full scanned
    ///      page, so other candidates remain reachable. Governance can isolate persistent failures.
    ///      No contract-defined reverts; a failed count read emits ScanFailed and retains the offset.
    function _advanceRejectedCursor(
        address asset_,
        uint256 startIndex_,
        IBurnerLoansLens.Selection selection_
    ) private {
        try _LENS.getActiveBorrowerCount(asset_) returns (uint256 population) {
            uint256 next = population == 0 || startIndex_ >= population - 1 ? 0 : startIndex_ + 1;
            if (selection_ == IBurnerLoansLens.Selection.Expired) expiredAssetCursor[asset_] = next;
            else unhealthyAssetCursor[asset_] = next;
        } catch (bytes memory reason) {
            // Unknown population cannot justify an invalid recovery cursor.
            // forge-lint: disable-next-line(unsafe-typecast)
            emit ScanFailed(asset_, bytes4(reason));
        }
    }

    /// @dev Identifies refresh-stage failures so unhealthy debt is retried after price recovery.
    ///      Does not intentionally revert; short reason data is zero-padded.
    function _isPriceFailure(
        IBurnerLoansLens.Selection selection_,
        bytes memory reason_
    ) private pure returns (bool) {
        if (selection_ != IBurnerLoansLens.Selection.Unhealthy) return false;
        // Only the four-byte stage selector is compared; shorter data is zero-padded.
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes4(reason_) == IBurnerLoansSeize.BurnerLoans_PriceSnapshotUnavailable.selector;
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Reads local membership only; does not intentionally revert.
    function isAssetManaged(address asset_) external view override returns (bool) {
        return _assets.contains(asset_);
    }

    /// @inheritdoc IBurnerLoansSeizerTask
    /// @dev Reads the local managed set only; does not intentionally revert.
    function getAssets() external view override returns (address[] memory) {
        return _assets.values();
    }

    /// @notice Requires governance ADMIN or delegated Burner Loans administration.
    /// @dev Reverts if:
    ///      - The caller holds neither ADMIN nor burner_loans_admin.
    ///      - Reading caller roles fails.
    function _requireAdminOrBurnerLoansAdmin() private view {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
    }

    /// @notice Authorizes a re-enable transition during the grace period.
    /// @dev Reverts if:
    ///      - The caller holds neither ADMIN nor burner_loans_admin.
    ///      - Reading caller roles fails.
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

    /// @dev Reverts if:
    ///      - The caller lacks ADMIN, or reading caller roles fails.
    ///      The public setter applies activity and local enablement before authorization.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @notice Revalidates Seize/Lens bindings and direct Seize readiness before enablement.
    /// @dev Reverts if:
    ///      - Data is nonempty.
    ///      - This policy is Kernel-inactive, Seize is inactive/disabled, or a binding is invalid.
    ///      - Reading a required dependency identity or readiness fails.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();

        _requireSeizeReady();
    }

    /// @notice Preserves the grace-period gate and revalidates Seize before re-enabling.
    /// @dev Reverts if:
    ///      - The grace deadline overflows uint48 or the grace window has expired.
    ///      - This policy is Kernel-inactive, Seize is inactive/disabled, or a binding is invalid.
    ///      - Reading a required dependency identity or readiness fails.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requireSeizeReady();
    }

    /// @notice Checks the operational Seize dependency; Seize governs its downstream readiness.
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - Seize is inactive/disabled, or a Seize/Lens/Core binding is invalid.
    ///      - Reading a required dependency identity or readiness fails.
    function _requireSeizeReady() private view {
        _requireOwnPolicyActive();
        _validateBindings();
        if (!kernel.isPolicyActive(Policy(address(seize))) || !IEnabler(address(seize)).isEnabled())
            revert PolicyDependency.PolicyDependency_NotActive(address(seize));
    }

    /// @notice Validates the direct Seize dependency and its shared Core identity with Lens.
    ///      Core's interface is consumed by addAsset; its Kernel and lifecycle remain Seize's concern.
    /// @dev Reverts if:
    ///      - Seize is zero, lacks its interface, or reports another Kernel.
    ///      - Lens lacks its interface or reports a different Core.
    ///      - Core lacks its required interface, or reading a dependency identity fails.
    function _validateBindings() private view {
        address action = address(seize);
        if (
            action == address(0) ||
            !ERC165Checker.supportsInterface(action, type(IBurnerLoansSeize).interfaceId)
        ) revert BurnerLoansSeizer_InvalidSeize(action);
        address core = IBurnerLoansCoreBound(address(seize)).core();
        // Kernel migration leaves old membership entries intact; activity cannot prove this binding.
        PolicyDependency.requireSameKernel(action, address(kernel));
        if (
            !ERC165Checker.supportsInterface(address(_LENS), type(IBurnerLoansLens).interfaceId) ||
            IBurnerLoansCoreBound(address(_LENS)).core() != core
        ) revert BurnerLoansSeizer_InvalidLens(address(_LENS));
        // addAsset calls Core.isAssetRegistered() directly. Check that callable boundary here.
        if (!ERC165Checker.supportsInterface(core, type(IBurnerLoansCore).interfaceId))
            revert BurnerLoansSeizerTask_InvalidCore(core);
    }

    /// @inheritdoc IPeriodicTask
    /// @dev Pure interface identifiers or inherited lifecycle identifiers only; no dependency calls.
    ///      Does not intentionally revert.
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
    /// @param maxBorrowersToCheck_ Maximum borrowers checked by each discovery lane per asset visit.
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
    /// @dev Returns the immutable Lens binding; does not intentionally revert.
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
