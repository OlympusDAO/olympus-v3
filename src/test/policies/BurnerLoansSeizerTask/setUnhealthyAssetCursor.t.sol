// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Contracts
import {BurnerLoansSeizerTaskCursorCases} from "./fixtures/BurnerLoansSeizerTaskCursorCases.t.sol";

contract BurnerLoansSeizerTaskSetUnhealthyAssetCursorTest is BurnerLoansSeizerTaskCursorCases {
    // Scenarios: BLSEIZ-EXPIRED-CURSOR-P08, BLSEIZ-UNHEALTHY-CURSOR-P08.
    function test_givenUnequalCursors_whenBothSettersRun_thenBothCursorsAreUpdated() public {
        _mockCount(10);
        _task.setScanLimits(2, 1);
        _task.setExpiredAssetCursor(address(_asset), 2);
        _task.setUnhealthyAssetCursor(address(_asset), 8);
        assertEq(_task.expiredAssetCursor(address(_asset)), 2, "Independent expiry setup offset");
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            8,
            "Independent unhealthy setup offset"
        );
        vm.recordLogs();
        _task.setExpiredAssetCursor(address(_asset), 2);
        assertEq(vm.getRecordedLogs().length, 0, "Unchanged expiry setter emits no event");
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.AssetCursorSet(
            address(_asset),
            2,
            IBurnerLoansLens.Selection.Unhealthy
        );
        _task.setUnhealthyAssetCursor(address(_asset), 2);
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            2,
            "Expiry cursor keeps the selected value"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            2,
            "Setter must not return early while the other lane differs"
        );
    }

    // Scenarios: BLSEIZ-UNHEALTHY-CURSOR-P09.
    function test_givenUnequalCursors_whenOnlyUnhealthySelected_thenExpiryIsPreserved() public {
        _mockCount(10);
        _task.setScanLimits(2, 1);
        _task.setExpiredAssetCursor(address(_asset), 2);
        _task.setUnhealthyAssetCursor(address(_asset), 8);
        assertEq(_task.expiredAssetCursor(address(_asset)), 2, "Independent expiry setup offset");
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            8,
            "Independent unhealthy setup offset"
        );
        _task.setUnhealthyAssetCursor(address(_asset), 3);
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            2,
            "Unselected expiry lane keeps its offset"
        );
        assertEq(_task.unhealthyAssetCursor(address(_asset)), 3, "Selected unhealthy lane changes");
    }

    function _isExpired() internal pure override returns (bool) {
        return false;
    }
}
