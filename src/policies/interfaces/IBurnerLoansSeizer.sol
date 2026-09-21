// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";

/// @title Burner Loans Seizer Interface
/// @notice Bounded periodic scanning and seizure.
interface IBurnerLoansSeizer is IPeriodicTask {
    /// @notice A required constructor or asset address is zero.
    error BurnerLoansSeizer_ZeroAddress();

    /// @notice The configured target does not advertise the required Burner Loans interfaces.
    /// @param burnerLoans Invalid Burner Loans target.
    error BurnerLoansSeizer_InvalidBurnerLoans(address burnerLoans);

    /// @notice The configured Burner Loans target belongs to a different Kernel.
    /// @param expectedKernel Kernel that manages the Seizer.
    /// @param actualKernel Kernel reported by the Burner Loans target.
    error BurnerLoansSeizer_KernelMismatch(address expectedKernel, address actualKernel);

    /// @notice The gas forwarded to one complete task execution is zero.
    error BurnerLoansSeizer_InvalidExecutionGasLimit();

    /// @notice The gas-bounded task body was called by an account other than this contract.
    error BurnerLoansSeizer_OnlySelf();

    /// @notice A scan or seizure bound is zero, exceeds its maximum, or is internally inconsistent.
    /// @param maxBorrowersToCheck Proposed borrower scan limit.
    /// @param maxBorrowersToSeize Proposed borrower seizure limit.
    error BurnerLoansSeizer_InvalidScanLimits(
        uint16 maxBorrowersToCheck,
        uint8 maxBorrowersToSeize
    );

    /// @notice An asset is already included in the round-robin scan.
    /// @param asset Duplicate managed asset.
    error BurnerLoansSeizer_AssetAlreadyManaged(address asset);

    /// @notice An asset is not included in the round-robin scan.
    /// @param asset Unmanaged asset.
    error BurnerLoansSeizer_AssetNotManaged(address asset);

    /// @notice Emitted when an asset is added to the round-robin scan.
    /// @param asset Added collateral asset.
    event AssetAdded(address indexed asset);

    /// @notice Emitted when an asset is removed from the round-robin scan.
    /// @param asset Removed collateral asset.
    event AssetRemoved(address indexed asset);

    /// @notice Emitted when the scan and seizure bounds change.
    /// @param maxBorrowersToCheck New borrower scan limit.
    /// @param maxBorrowersToSeize New borrower seizure limit.
    event ScanLimitsSet(uint16 maxBorrowersToCheck, uint8 maxBorrowersToSeize);

    /// @notice Emitted when the gas forwarded to one task execution changes.
    /// @param gasLimit New task gas limit.
    event ExecutionGasLimitSet(uint32 gasLimit);

    /// @notice Emitted when the gas-bounded task body fails.
    /// @param reason First four bytes of the task's bounded revert data.
    event ExecutionFailed(bytes4 reason);

    /// @notice Emitted after an asset scan completes and any returned borrowers are seized.
    /// @param asset Scanned collateral asset.
    /// @param startIndex Borrower cursor used at the start of the scan.
    /// @param nextIndex Borrower cursor stored after successful processing.
    /// @param seizedBorrowers Number of borrowers submitted for seizure.
    event SeizureExecuted(
        address indexed asset,
        uint256 startIndex,
        uint256 nextIndex,
        uint256 seizedBorrowers
    );

    /// @notice Emitted when borrower scanning fails without reverting the Heart task.
    /// @param asset Collateral asset whose scan failed.
    /// @param reason Selector of the underlying error, or zero when unavailable.
    event ScanFailed(address indexed asset, bytes4 reason);

    /// @notice Emitted when a seizure fails without reverting the Heart task.
    /// @param asset Collateral asset whose seizure failed.
    /// @param reason Selector of the underlying error, or zero when unavailable.
    event SeizureFailed(address indexed asset, bytes4 reason);

    /// @notice Emitted when this task lacks the protocol seizer role for an asset.
    /// @param asset Collateral asset skipped because authority was missing.
    event SeizerRoleMissing(address indexed asset);

    /// @notice Scans one managed asset and seizes eligible positions.
    /// @dev Scan and seizure failures are isolated and reported so execution does
    ///      not block later Heart periodic tasks. Gas exhaustion in the task body is also isolated.
    ///      Returns without work while the policy is disabled. Reverts if the caller does not hold
    ///      the `heart` role.
    function execute() external override;

    /// @notice Executes the gas-bounded task body through an external self-call.
    /// @dev Reverts unless called by this contract itself. The outer `execute` call catches failure.
    function selfExecuteTask() external;

    /// @notice Adds a collateral asset to the round-robin seizure scan.
    /// @dev Reverts if the caller is not the policy admin, the asset is zero, or the asset is already
    ///      managed.
    /// @param asset Collateral asset to manage.
    function addAsset(address asset) external;

    /// @notice Removes a collateral asset from the round-robin seizure scan.
    /// @dev Reverts if the caller is not the policy admin or the asset is not managed.
    /// @param asset Collateral asset to stop managing.
    function removeAsset(address asset) external;

    /// @notice Sets the maximum borrowers scanned and seized in one execution.
    /// @dev Reverts if the caller is unauthorized or either limit is outside the supported bounds.
    /// @param maxBorrowersToCheck Maximum active borrowers inspected per execution.
    /// @param maxBorrowersToSeize Maximum seizable borrowers settled per execution.
    function setScanLimits(uint16 maxBorrowersToCheck, uint8 maxBorrowersToSeize) external;

    /// @notice Sets the maximum gas forwarded to one complete task execution.
    /// @dev Reverts for zero gas or a caller without the admin or `burner_loans_admin` role.
    /// @param gasLimit Maximum gas forwarded to the self-call.
    function setExecutionGasLimit(uint32 gasLimit) external;

    /// @notice Returns the Burner Loans policy scanned and reconciled by this task.
    /// @return burnerLoans_ Burner Loans policy address.
    function burnerLoans() external view returns (address burnerLoans_);

    /// @notice Returns the maximum active borrowers inspected per execution.
    /// @return maxBorrowersToCheck_ Borrower scan limit.
    function maxBorrowersToCheck() external view returns (uint16 maxBorrowersToCheck_);

    /// @notice Returns the maximum seizable borrowers settled per execution.
    /// @return maxBorrowersToSeize_ Borrower seizure limit.
    function maxBorrowersToSeize() external view returns (uint8 maxBorrowersToSeize_);

    /// @notice Returns the gas limit forwarded to the self-call.
    /// @return executionGasLimit_ Maximum task-body gas.
    function executionGasLimit() external view returns (uint32 executionGasLimit_);

    /// @notice Returns the index of the asset scanned by the next execution.
    /// @return nextAssetIndex_ Next managed-asset index.
    function nextAssetIndex() external view returns (uint256 nextAssetIndex_);

    /// @notice Returns the next active-borrower index scanned for an asset.
    /// @param asset Collateral asset whose cursor is queried.
    /// @return cursor_ Next borrower index.
    function assetCursor(address asset) external view returns (uint256 cursor_);

    /// @notice Returns whether an asset is included in round-robin scanning.
    /// @param asset Collateral asset to query.
    /// @return isManaged_ True when the asset is managed.
    function isAssetManaged(address asset) external view returns (bool isManaged_);

    /// @notice Returns all collateral assets included in round-robin scanning.
    /// @return assets_ Managed collateral assets.
    function getAssets() external view returns (address[] memory assets_);
}
