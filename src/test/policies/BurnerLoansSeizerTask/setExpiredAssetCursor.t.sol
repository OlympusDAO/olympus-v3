// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansSeizerTaskCursorCases} from "./fixtures/BurnerLoansSeizerTaskCursorCases.t.sol";

contract BurnerLoansSeizerTaskSetExpiredAssetCursorTest is BurnerLoansSeizerTaskCursorCases {
    // Scenarios: BLSEIZ-EXPIRED-CURSOR-P09.
    function test_givenUnequalCursors_whenOnlyExpirySelected_thenUnhealthyIsPreserved() public {
        _mockCount(10);
        vm.prank(_seizerAdmin);
        _task.setScanLimits(2, 1);
        vm.prank(_seizerAdmin);
        _task.setExpiredAssetCursor(address(_asset), 2);
        vm.prank(_seizerAdmin);
        _task.setUnhealthyAssetCursor(address(_asset), 8);
        assertEq(_task.expiredAssetCursor(address(_asset)), 2, "Independent expiry setup offset");
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            8,
            "Independent unhealthy setup offset"
        );
        vm.prank(_seizerAdmin);
        _task.setExpiredAssetCursor(address(_asset), 7);
        assertEq(_task.expiredAssetCursor(address(_asset)), 7, "Selected expiry lane changes");
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            8,
            "Unselected unhealthy lane stays pending"
        );
    }

    function _isExpired() internal pure override returns (bool) {
        return true;
    }
}
