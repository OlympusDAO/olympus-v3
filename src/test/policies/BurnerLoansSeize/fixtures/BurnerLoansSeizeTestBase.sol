// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {BurnerLoansDebtTest} from "src/test/policies/BurnerLoansDebt/BurnerLoansDebtTest.sol";

// Literals are independent expected values and boundary seeds.
// Fixture casts are bounded; seed loops intentionally call external contracts.
// Fixture calls and ignored returns are checked through errors and ledger assertions.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, unused-return)

abstract contract BurnerLoansSeizeTestBase is BurnerLoansDebtTest {
    error DefaultFailed();

    function setUp() public virtual override {
        super.setUp();
        _depositCollateral(2000e6);
        _mockRisk(0);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 0);
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encode(uint256(1))
        );
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.keeperReward.selector),
            abi.encode(uint256(7))
        );
    }

    function _borrowers() internal view returns (address[] memory borrowers) {
        borrowers = new address[](1);
        borrowers[0] = _borrower;
    }

    function _seizeDigest(address keeper_) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _stateDigest(keeper_),
                    _floan.getMarketPrincipalDefaulted(_core.marketId(address(_asset))),
                    _asset.balanceOf(_payout.treasury()),
                    _payout.pendingPayout(address(_asset), keeper_)
                )
            );
    }

    function _expectRejected(
        bytes memory reason_,
        address[] memory borrowers_,
        address keeper_
    ) internal {
        bytes32 beforeState = _seizeDigest(keeper_);
        vm.expectRevert(reason_);
        vm.prank(keeper_);
        _liquidation.previewSeizeFor(keeper_, address(_asset), borrowers_);
        assertEq(
            _seizeDigest(keeper_),
            beforeState,
            "Rejected preview preserves all ledgers and custody"
        );
        vm.expectRevert(reason_);
        vm.prank(keeper_);
        _liquidation.seize(address(_asset), borrowers_);
        assertEq(
            _seizeDigest(keeper_),
            beforeState,
            "Rejected seizure restores balances, allowances, receipts and indexes"
        );
    }

    function _expectAdmissionRejected(bytes memory reason_, address caller_) internal {
        _expectRejected(reason_, _borrowers(), caller_);
        _expectRejected(reason_, new address[](0), caller_);
    }

    function _expectSettlementRevert(bytes memory reason_) internal {
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            _recipient,
            address(_asset),
            _borrowers()
        );
        assertEq(quote.keeperReward, 7, "Quote does not predict mandatory delivery failure");
        assertEq(quote.collateralToTreasury, 1_999_999_993, "Quote retains independent remainder");
        bytes32 beforeState = _seizeDigest(_recipient);
        vm.expectRevert(reason_);
        vm.prank(_recipient);
        _liquidation.seize(address(_asset), _borrowers());
        assertEq(
            _seizeDigest(_recipient),
            beforeState,
            "Late failure restores full accounting and custody"
        );
    }

    function _assertSingleSeizure() internal {
        bytes32 beforeState = _seizeDigest(_recipient);
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            _recipient,
            address(_asset),
            _borrowers()
        );
        assertEq(
            _seizeDigest(_recipient),
            beforeState,
            "Preview has no accounting or custody writes"
        );
        assertEq(quote.seizedDebtOhm, 100e9, "Quoted debt in OHM 9 decimals");
        assertEq(quote.seizedCollateral, 2000e6, "Quoted collateral in asset 6 decimals");
        assertEq(quote.tokenOut, address(_asset), "Quoted underlying output token");
        assertEq(quote.keeperReward, 7, "Mock Risk returns independent seven-unit reward");
        assertEq(
            quote.collateralToTreasury,
            1_999_999_993,
            "Integer remainder is output minus reward"
        );
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        uint256 keeperBefore = _asset.balanceOf(_recipient);
        vm.expectEmit(address(_core));
        emit IBurnerLoansCore.Seized(_recipient, address(_asset), _borrower, 100e9, 2000e6);
        vm.expectEmit(address(_core));
        emit IBurnerLoansCore.SeizureBatchSettled(
            _recipient,
            address(_asset),
            1,
            100e9,
            2000e6,
            address(_asset),
            7,
            1_999_999_993
        );
        vm.prank(_recipient);
        (address token, uint256 reward, uint256 treasury) = _liquidation.seize(
            address(_asset),
            _borrowers()
        );
        assertEq(token, quote.tokenOut, "Execution uses quoted token");
        assertEq(reward, quote.keeperReward, "Execution uses quoted reward");
        assertEq(treasury, quote.collateralToTreasury, "Execution uses quoted remainder");
        assertEq(_asset.balanceOf(_recipient), keeperBefore + 7, "Keeper paid exactly once");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + 1_999_999_993,
            "Treasury paid exact remainder"
        );
        assertEq(_position().principalDue, 0, "Debt cleared");
        assertEq(_position().collateral, 0, "Collateral cleared");
        uint32 market = _core.marketId(address(_asset));
        assertEq(_floan.getMarketPrincipalDue(market), 0, "Market debt cleared");
        assertEq(_floan.getMarketPrincipalDefaulted(market), 100e9, "Default recorded once");
        assertEq(_floan.getMarketCollateral(market), 0, "Market collateral cleared");
        assertEq(_floan.getActiveBorrowerCount(market), 0, "Borrower removed from active index");
        assertEq(_inventory.activePrincipalOhm(), 0, "Inventory debt reconciled");
        assertEq(_asset.balanceOf(address(_depositManager)), 0, "Custody redeemed exactly");
        assertEq(_asset.balanceOf(address(_core)), 0, "Core retains no collateral");
        assertEq(_asset.balanceOf(address(_payout)), 0, "Delivered payout retains no collateral");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            0,
            "DM liabilities released"
        );
        (, , uint256 reserve) = _payout.payoutReserves(address(_asset));
        assertEq(reserve, 0, "No paid obligation remains reserved");
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unused-return)
