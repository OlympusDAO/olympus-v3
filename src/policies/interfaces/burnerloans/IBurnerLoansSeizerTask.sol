// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansSeize} from "src/policies/interfaces/burnerloans/IBurnerLoansSeize.sol";

/// @title Burner Loans Seizer Task Interface
/// @notice Bounded periodic scanning and seizure.
interface IBurnerLoansSeizerTask {
    // ========== EVENTS ========== //

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

    /// @notice Emitted when governance selects the next managed asset to scan.
    /// @param index New index in the managed asset set.
    event NextAssetIndexSet(uint256 index);

    /// @notice Emitted when governance selects an asset's next borrower offset.
    /// @param asset Managed collateral asset.
    /// @param cursor New offset in the canonical active-borrower list.
    event AssetCursorSet(address indexed asset, uint256 cursor);

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

    // ========== ERRORS ========== //

    /// @notice The proposed Core is zero or does not support the required interface.
    /// @param core Invalid Core address.
    error BurnerLoansSeizerTask_InvalidCore(address core);

    /// @notice The configured Seize target is zero or lacks the required interface.
    /// @param seize Invalid Seize target.
    error BurnerLoansSeizer_InvalidSeize(address seize);

    /// @notice The gas forwarded to one complete task execution is zero.
    error BurnerLoansSeizer_InvalidExecutionGasLimit();

    /// @notice The gas-bounded task body was called by an account other than this contract.
    error BurnerLoansSeizer_OnlySelf();

    /// @notice A scan or seizure bound is zero, or the seizure limit exceeds the scan limit.
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

    /// @notice A nonzero asset index is outside the managed asset set.
    /// @param index Requested next asset index.
    /// @param count Current number of managed assets.
    error BurnerLoansSeizer_InvalidAssetIndex(uint256 index, uint256 count);

    /// @notice The supplied scan helper is not deployed or reports another Core.
    /// @param lens Invalid scan helper.
    error BurnerLoansSeizer_InvalidLens(address lens);

    // ========== FUNCTIONS ========== //

    /// @notice Returns the Seize action called by this task.
    /// @return action Directly bound action; its shared Core binding identifies the accounting Core.
    function seize() external view returns (IBurnerLoansSeize action);

    /// @notice Adds a collateral asset to the round-robin seizure scan.
    /// @dev The asset must already be registered in the bound Core. Registration is
    ///      independent of Core enablement and whether new originations are permitted.
    ///
    /// @dev Required revert behavior:
    ///      - For an otherwise valid add request, an unregistered asset, including zero,
    ///        must revert with BurnerLoansCore_AssetNotConfigured(asset).
    /// @param asset Collateral asset to manage.
    function addAsset(address asset) external;

    /// @notice Removes a collateral asset from the round-robin seizure scan.
    ///
    /// @param asset Collateral asset to stop managing.
    function removeAsset(address asset) external;

    /// @notice Sets the maximum borrowers scanned and seized in one execution.
    /// @dev ADMIN or burner_loans_admin may configure either limit. Both must be nonzero,
    ///      and the seizure limit must not exceed the scan limit. The input types define their maxima.
    /// @param maxBorrowersToCheck Maximum active borrowers inspected per execution.
    /// @param maxBorrowersToSeize Maximum seizable borrowers settled per execution.
    function setScanLimits(uint16 maxBorrowersToCheck, uint8 maxBorrowersToSeize) external;

    /// @notice Sets the maximum gas forwarded to one complete task execution.
    ///
    /// @param gasLimit Maximum gas forwarded to the self-call.
    function setExecutionGasLimit(uint32 gasLimit) external;

    /// @notice Selects the next managed asset for periodic execution.
    /// @dev ADMIN and burner_loans_admin can recover traversal while locally paused.
    ///      Zero resets traversal even when no assets are managed; other values select an existing index.
    /// @param index Index in getAssets() order.
    function setNextAssetIndex(uint256 index) external;

    /// @notice Selects a managed asset's next active-borrower offset.
    /// @dev ADMIN and burner_loans_admin can recover borrower traversal while locally paused.
    ///      Zero resets without downstream reads; nonzero offsets are validated through Lens.
    /// @param asset Managed collateral asset.
    /// @param index Offset in the canonical active-borrower list.
    function setNextAssetBorrowerIndex(address asset, uint256 index) external;

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

    /// @notice Returns the immutable scan helper used by this task.
    /// @return helper Directly bound Lens address.
    function lens() external view returns (address helper);
}
