// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansSeizerTaskCursorCases} from "./fixtures/BurnerLoansSeizerTaskCursorCases.t.sol";

contract BurnerLoansSeizerTaskSetExpiredAssetCursorTest is BurnerLoansSeizerTaskCursorCases {
    function _isExpired() internal pure override returns (bool) {
        return true;
    }
}
