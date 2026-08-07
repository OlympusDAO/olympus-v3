// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";

/// @title Burner Loans Seizer Interface
/// @notice Bounded periodic scanning, seizure, and MINTR approval reconciliation for Burner Loans.
interface IBurnerLoansSeizer is IPeriodicTask {
    error BurnerLoansSeizer_ZeroAddress();
    error BurnerLoansSeizer_InvalidBurnerLoans(address burnerLoans);
    error BurnerLoansSeizer_KernelMismatch(address expectedKernel, address actualKernel);
    error BurnerLoansSeizer_InvalidExecutionGasLimit();
    error BurnerLoansSeizer_OnlySelf();
    error BurnerLoansSeizer_InvalidScanLimits(
        uint16 maxBorrowersToCheck,
        uint8 maxBorrowersToSeize
    );
    error BurnerLoansSeizer_AssetAlreadyManaged(address asset);
    error BurnerLoansSeizer_AssetNotManaged(address asset);

    event AssetAdded(address indexed asset);
    event AssetRemoved(address indexed asset);
    event ScanLimitsSet(uint16 maxBorrowersToCheck, uint8 maxBorrowersToSeize);
    event ExecutionGasLimitSet(uint32 gasLimit);
    event ExecutionFailed(bytes4 reason);
    event Executed(
        address indexed asset,
        uint256 startIndex,
        uint256 nextIndex,
        uint256 seizedBorrowers
    );
    event ScanFailed(address indexed asset, bytes4 reason);
    event SeizureFailed(address indexed asset, bytes4 reason);
    event SeizerRoleMissing(address indexed asset);
    event MintApprovalSynchronized(uint256 approval);
    event MintApprovalSyncFailed(bytes4 reason);

    /// @notice Scans one managed asset and attempts MINTR approval reconciliation.
    /// @dev Scan, seizure, and reconciliation failures are isolated and reported so execution does
    ///      not block later Heart periodic tasks. Gas exhaustion in the task body is also isolated.
    ///      Reverts if the caller does not hold the `heart` role.
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
