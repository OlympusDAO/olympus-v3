// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";

/// @dev Arbitrary scheduler calls, cursor recovery, scan-limit updates and pause/re-enable transitions.
contract SeizerTaskProgressHandler is Test {
    BurnerLoansSeizerTask internal immutable _TASK;
    bool public progressValid = true;

    constructor(BurnerLoansSeizerTask task_) {
        _TASK = task_;
    }

    function beat(bool exhaust_, uint16 checks_, uint8 results_) external {
        // Bounds fit the target numeric types and the task's admitted intervals.
        // forge-lint: disable-start(unsafe-typecast)
        checks_ = uint16(bound(checks_, 1, type(uint16).max));
        results_ = uint8(bound(results_, 1, checks_ < type(uint8).max ? checks_ : type(uint8).max));
        // forge-lint: disable-end(unsafe-typecast)
        _TASK.setScanLimits(checks_, results_);
        _TASK.setExecutionGasLimit(exhaust_ ? 1 : 10_000_000);
        uint256 beforeIndex = _TASK.nextAssetIndex();
        bool enabled = _TASK.isEnabled();
        _TASK.execute();
        // Two fixed assets: every enabled beat changes the selected asset, even on body failure.
        if (_TASK.nextAssetIndex() != (enabled ? 1 - beforeIndex : beforeIndex))
            progressValid = false;
    }

    function pause(bool paused_) external {
        if (paused_ && _TASK.isEnabled()) _TASK.disable("");
        if (!paused_ && !_TASK.isEnabled()) _TASK.reEnable();
    }

    function recover(uint256 assetIndex_, uint256 borrowerIndex_) external {
        address[] memory assets = _TASK.getAssets();
        uint256 index = assetIndex_ % assets.length;
        _TASK.setNextAssetIndex(index);
        address asset = assets[index];
        uint256 count = IBurnerLoansLens(_TASK.lens()).getActiveBorrowers(asset).length;
        _TASK.setNextAssetBorrowerIndex(asset, count == 0 ? 0 : borrowerIndex_ % count);
    }
}
