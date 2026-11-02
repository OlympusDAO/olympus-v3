// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";

// Contracts
import {BurnerLoansSeizerTaskProgressTest} from "../fixtures/BurnerLoansSeizerTaskProgressTest.sol";

// Fixed role/state partitions and loan quantities seed the recovery boundaries.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop)
contract BurnerLoansSeizerTaskSetNextAssetBorrowerIndexIntegrationTest is
    BurnerLoansSeizerTaskProgressTest
{
    error CursorReadFailed();

    function setUp() public override {
        super.setUp();
        _task.addAsset(address(_asset));
        _task.addAsset(address(_otherAsset));
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _seedDebt(_CAROL, 10e6, 1e9);
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-P04.
    function test_whenBorrowerCursorSelected_thenExecutionResumesThere() public {
        _task.setNextAssetBorrowerIndex(address(_asset), 2);
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 2), uint64(1));
        _task.execute();
        assertEq(_task.assetCursor(address(_asset)), 0, "Healthy suffix reaches population end");
        assertEq(
            _task.nextAssetIndex(),
            1,
            "Asset rotation remains independent of borrower cursor"
        );
        assertEq(_inventory.activePrincipalOhm(), 3e9, "Resumed healthy scan preserves principal");
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-P06.
    function test_givenOtherAssetHasProgress_whenBorrowerCursorSet_thenOtherProgressIsPreserved()
        public
    {
        _expectNoRiskReads();
        // A zero-sized Lens scan needs only B's population, not B positions or prices.
        vm.mockCall(
            address(_floan),
            abi.encodeCall(_floan.getActiveBorrowerCount, (_core.marketId(address(_otherAsset)))),
            abi.encode(uint256(2))
        );
        _task.setNextAssetBorrowerIndex(address(_otherAsset), 1);
        _task.setNextAssetIndex(1);
        _task.setNextAssetBorrowerIndex(address(_asset), 2);
        assertEq(_task.assetCursor(address(_asset)), 2, "Only A receives the new borrower offset");
        assertEq(
            _task.assetCursor(address(_otherAsset)),
            1,
            "B keeps its nonzero borrower progress"
        );
        assertEq(_task.nextAssetIndex(), 1, "Borrower recovery preserves pending B visit");
        assertEq(_inventory.activePrincipalOhm(), 3e9, "Recovery preserves real A principal");
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-I04.
    function test_givenLoans_whenCursorValidationFails_thenAccountingIsPreserved() public {
        _expectNoRiskReads();
        vm.mockCallRevert(
            address(_lens),
            _validation(1),
            abi.encodeWithSelector(CursorReadFailed.selector)
        );
        vm.expectRevert(CursorReadFailed.selector);
        _task.setNextAssetBorrowerIndex(address(_asset), 1);
        assertEq(_task.assetCursor(address(_asset)), 0, "Failed validation preserves cursor");
        _assertOtherStateUnchanged();
    }

    function _validation(uint256 index_) private view returns (bytes memory) {
        return
            abi.encodeCall(
                IBurnerLoansLens.getSeizableBorrowersBoundedFor,
                (address(_task), address(_asset), index_, uint256(0), uint256(0))
            );
    }

    function _assertOtherStateUnchanged() private view {
        assertEq(_task.assetCursor(address(_otherAsset)), 0, "Other borrower cursor unchanged");
        assertEq(_task.nextAssetIndex(), 0, "Borrower recovery preserves asset traversal");
        assertEq(
            _task.getAssets(),
            _two(address(_asset), address(_otherAsset)),
            "Managed assets unchanged"
        );
        assertEq(_task.maxBorrowersToCheck(), 500, "Scan limit unchanged");
        assertEq(_task.maxBorrowersToSeize(), 25, "Seizure limit unchanged");
        assertEq(_task.executionGasLimit(), 10_000_000, "Gas limit unchanged");
        // Three loans: 3 * 1e9 OHM-wei = 3e9 principal; 3 * 10e6 asset-wei = 30e6 collateral.
        uint32 market = _core.marketId(address(_asset));
        assertEq(_inventory.activePrincipalOhm(), 3e9, "Inventory principal unchanged");
        assertEq(_floan.getMarketPrincipalDue(market), 3e9, "Canonical principal unchanged");
        assertEq(_floan.getMarketCollateral(market), 30e6, "Canonical collateral unchanged");
        assertEq(_asset.balanceOf(address(_task)), 0, "Task custody remains empty");
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop)
