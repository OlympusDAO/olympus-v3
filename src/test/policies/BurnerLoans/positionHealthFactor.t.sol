// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";

contract BurnerLoansPositionHealthFactorTest is BurnerLoansBorrowTestBase {
    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function test_givenExactCollateralBoundary_positionHealthFactor_returnsOneWad() public view {
        // debt = 100 OHM * $10 = $1,000; 115% minimum collateral = $1,150.
        // collateral = 1,150 units * $1 = $1,150, so health = 1e18.
        assertEq(burnerLoans.positionHealthFactor(address(usds), 1_150e18, 100e9), 1e18, "health");
    }
}
