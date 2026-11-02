// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Libraries
import {LoanPositions} from "src/policies/burnerloans/libraries/LoanPositions.sol";

// Contracts
import {BurnerLoansSeizeTestBase} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeTestBase.sol";

// Literals are independent expected values and boundary seeds.
// Fixture casts are bounded; seed loops intentionally call external contracts.
// Fixture calls and ignored returns are checked through errors and ledger assertions.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, unsafe-typecast, unused-return)

contract BurnerLoansSeizeBatchTest is BurnerLoansSeizeTestBase {
    // Scenarios: BLLIQ-SEIZE-P11.
    function test_whenValidBatchSeized_thenEveryPositionSettledOnce(uint8 length_) public {
        length_ = uint8(bound(length_, 1, type(uint8).max));
        address[] memory borrowers = new address[](length_);
        borrowers[0] = _borrower;
        for (uint256 i = 1; i < length_; ++i) {
            address borrower = address(uint160(0x10000 + i));
            borrowers[i] = borrower;
            _asset.mint(borrower, 20e6);
            vm.startPrank(borrower);
            assertTrue(
                _asset.approve(address(_core), type(uint256).max),
                "Additional borrower approves Core"
            );
            _collateral.depositCollateral(address(_asset), 20e6, borrower);
            _debt.borrow(address(_asset), 1, borrower, borrower, 0);
            vm.stopPrank();
        }
        uint256 debt = 100e9 + length_ - 1;
        uint256 collateral = 2000e6 + (uint256(length_) - 1) * 20e6;
        bytes32 beforeState = _seizeDigest(_recipient);
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            _recipient,
            address(_asset),
            borrowers
        );
        assertEq(_seizeDigest(_recipient), beforeState, "Batch preview preserves state");
        assertEq(quote.seizedDebtOhm, debt, "Sum debt independently in OHM-wei");
        assertEq(quote.seizedCollateral, collateral, "Sum collateral independently in asset-wei");
        assertEq(quote.tokenOut, address(_asset), "Batch quotes underlying output");
        assertEq(quote.keeperReward, 7, "One aggregate Risk reward");
        assertEq(quote.collateralToTreasury, collateral - 7, "One integer output remainder");
        for (uint256 i; i < length_; ++i) {
            vm.expectEmit(address(_core));
            emit IBurnerLoansCore.Seized(
                _recipient,
                address(_asset),
                borrowers[i],
                i == 0 ? 100e9 : 1,
                i == 0 ? 2000e6 : 20e6
            );
        }
        vm.expectEmit(address(_core));
        emit IBurnerLoansCore.SeizureBatchSettled(
            _recipient,
            address(_asset),
            length_,
            debt,
            collateral,
            address(_asset),
            7,
            collateral - 7
        );
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        vm.prank(_recipient);
        (address token, uint256 reward, uint256 treasury) = _liquidation.seize(
            address(_asset),
            borrowers
        );
        assertEq(token, address(_asset), "Batch output token");
        assertEq(reward, 7, "Batch reward once");
        assertEq(treasury, collateral - 7, "Batch remainder");
        assertEq(_asset.balanceOf(_recipient), 7, "Keeper paid aggregate reward once");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + collateral - 7,
            "Treasury receives remainder"
        );
        assertEq(_inventory.activePrincipalOhm(), 0, "All funding entries reconciled");
        uint32 market = _core.marketId(address(_asset));
        assertEq(
            _floan.getMarketPrincipalDefaulted(market),
            debt,
            "All debt defaulted exactly once"
        );
        assertEq(_floan.getMarketPrincipalDue(market), 0, "No batch principal remains");
        assertEq(_floan.getMarketCollateral(market), 0, "No batch collateral remains");
        assertEq(_floan.getActiveBorrowerCount(market), 0, "All active entries removed");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            0,
            "All liabilities released"
        );
        assertEq(_asset.balanceOf(address(_depositManager)), 0, "All batch collateral redeemed");
        assertEq(_asset.balanceOf(address(_payout)), 0, "No delivered collateral retained");
        for (uint256 i; i < length_; ++i) {
            (, , IFLOANv1.Position memory position) = LoanPositions.forCore(
                _core,
                address(_asset),
                borrowers[i]
            );
            assertEq(position.principalDue, 0, "Each borrower defaulted");
            assertEq(position.collateral, 0, "Each collateral settled");
        }
    }

    // Scenarios: BLLIQ-SEIZE-P11.
    function test_whenFiftyOneBorrowersSeized_thenEveryPositionSettledOnce() public {
        test_whenValidBatchSeized_thenEveryPositionSettledOnce(51);
    }

    // Scenarios: BLLIQ-SEIZE-P11.
    function test_whenMaxUint8BorrowersSeized_thenEveryPositionSettledOnce() public {
        test_whenValidBatchSeized_thenEveryPositionSettledOnce(type(uint8).max);
    }

    // Scenarios: BLLIQ-SEIZE-P11.
    function test_whenFiftyBorrowersSeized_thenEveryPositionSettledOnce() public {
        test_whenValidBatchSeized_thenEveryPositionSettledOnce(50);
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unsafe-typecast, unused-return)
