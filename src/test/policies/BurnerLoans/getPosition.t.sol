// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansGetPositionTest is BurnerLoansTest {
    // getPosition
    // given multiple FLOAN positions
    //  when getPosition is called
    //   then it reverts as ambiguous
    function test_givenMultipleFloanPositions_getPosition_revertsAsAmbiguous() public {
        _addDefaultUsdsAsset();
        uint32 marketId = burnerLoans.marketId(address(usds));
        vm.startPrank(address(burnerLoans));
        floan.createPosition(marketId, alice);
        floan.createPosition(marketId, alice);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousPosition.selector,
                marketId,
                alice,
                2
            )
        );
        burnerLoans.getPosition(address(usds), alice);
    }

    // getPosition
    // given existing position
    //  when getPosition is called
    //   then it returns the FLOAN record
    function test_givenExistingPosition_getPosition_returnsFloanRecord() public {
        _addDefaultUsdsAsset();
        IBurnerLoans.Position memory expected = IBurnerLoans.Position({
            depositedCollateral: 1_500e6,
            debtOhm: 100e9,
            maturity: uint48(block.timestamp + 30 days),
            lastBorrowBlock: 0,
            status: IBurnerLoans.PositionStatus.NoDebt
        });
        burnerLoans.setPositionForTest(address(usds), alice, expected);

        IBurnerLoans.Position memory actual = burnerLoans.getPosition(address(usds), alice);
        assertEq(actual.depositedCollateral, expected.depositedCollateral, "collateral");
        assertEq(actual.debtOhm, expected.debtOhm, "debt");
        assertEq(actual.maturity, expected.maturity, "maturity");
        assertEq(actual.lastBorrowBlock, block.number, "last borrow block");
        assertEq(uint8(actual.status), uint8(IBurnerLoans.PositionStatus.Active), "status");
    }
}
