// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";

/// @title Burner Loans Seizer Interface
/// @notice Bounded periodic scanning and seizure for configured Burner Loans collateral assets.
interface IBurnerLoansSeizer is IPeriodicTask {
    error BurnerLoansSeizer_ZeroAddress();
    error BurnerLoansSeizer_InvalidScanLimits(
        uint16 maxBorrowersToCheck,
        uint8 maxBorrowersToSeize
    );
    error BurnerLoansSeizer_AssetAlreadyManaged(address asset);
    error BurnerLoansSeizer_AssetNotManaged(address asset);

    event AssetAdded(address indexed asset);
    event AssetRemoved(address indexed asset);
    event ScanLimitsSet(uint16 maxBorrowersToCheck, uint8 maxBorrowersToSeize);
    event Executed(
        address indexed asset,
        uint256 startIndex,
        uint256 nextIndex,
        uint256 seizedBorrowers
    );
    event ScanFailed(address indexed asset, bytes4 reason);
    event SeizureFailed(address indexed asset, bytes4 reason);
    event SeizerRoleMissing(address indexed asset);

    function addAsset(address asset) external;

    function removeAsset(address asset) external;

    function setScanLimits(uint16 maxBorrowersToCheck, uint8 maxBorrowersToSeize) external;

    function burnerLoans() external view returns (address);

    function maxBorrowersToCheck() external view returns (uint16);

    function maxBorrowersToSeize() external view returns (uint8);

    function nextAssetIndex() external view returns (uint256);

    function assetCursor(address asset) external view returns (uint256);

    function isAssetManaged(address asset) external view returns (bool);

    function getAssets() external view returns (address[] memory);
}
