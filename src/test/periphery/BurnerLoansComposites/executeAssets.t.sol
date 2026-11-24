// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Contracts
import {BurnerLoansCompositesGrantModesTest} from "./fixtures/BurnerLoansCompositesGrantModesTest.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract BurnerLoansCompositesExecuteAssetsTest is BurnerLoansCompositesGrantModesTest {
    MockERC20 internal _other;

    function setUp() public override {
        super.setUp();
        _other = new MockERC20("Other admitted collateral", "OTHER", 18);
        _price.setPrice(address(_other), 1e18);
        _admit(address(_other));
        _other.mint(_borrower, 4000e18);
        vm.startPrank(_borrower);
        assertTrue(_other.approve(address(_core), type(uint256).max), "Approve second market");
        _collateral.depositCollateral(address(_other), 2000e18, _borrower);
        _debt.borrow(address(_other), 100e9, _borrower, _borrower, 1e18, address(0));
        vm.stopPrank();
        vm.roll(vm.getBlockNumber() + 1);
    }

    // Scenarios: BLREX-P04, BLREX-P34.
    function test_givenCollateralPosition_whenBorrowedOhmRepaysAnotherMarket(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        IExecutor.Operation[] memory operations = _borrowAndService(address(_executor));
        uint256 otherWalletBefore = _other.balanceOf(_borrower);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            operations,
            new IExecutor.Output[](0)
        );
        assertEq(_position().debtOhm, 100e9, "Granted market records the new borrow");
        IBurnerLoansCore.Position memory second = _lens.getPosition(address(_other), _borrower);
        assertEq(second.debtOhm, 0, "Older debt paid from proceeds");
        // 2000 collateral units are 2000e6 in the source market and 2000e18 in the other market.
        assertEq(
            _position().depositedCollateral,
            2000e6,
            "Source market retains six-decimal credit"
        );
        assertEq(
            second.depositedCollateral,
            2000e18,
            "Other market retains eighteen-decimal credit"
        );
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            2000e6,
            "Six-decimal collateral stays in custody"
        );
        assertEq(
            _other.balanceOf(address(_depositManager)),
            2000e18,
            "Eighteen-decimal collateral stays in custody"
        );
        // The source market charges 125e6 * 25 / 10_000 = 312500 raw collateral units.
        assertEq(_asset.balanceOf(_borrower), 8000e6 - 312500, "Only the six-decimal fee is paid");
        assertEq(
            _other.balanceOf(_borrower),
            otherWalletBefore,
            "Repayment spends no other collateral"
        );
        assertEq(_core.totalActiveDebtOhm(), 100e9, "Core reconciles both markets");
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Inventory reconciles both markets");
        assertEq(_ohm.balanceOf(_borrower), 100e9, "Starting wallet OHM remains available");
        assertEq(_ohm.balanceOf(address(_executor)), 0, "All received OHM serviced older debt");
    }

    // Scenarios: BLREX-P03.
    function test_givenCollateralPosition_whenBorrowIsPaidDirectly_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        IExecutor.Operation[] memory operations = _borrowAndService(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientFunds.selector,
                address(_ohm),
                100e9,
                0
            )
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            operations,
            new IExecutor.Output[](0)
        );
        assertEq(_position().debtOhm, 0, "Failed sequence rolls back the new borrow");
        assertEq(
            _lens.getPosition(address(_other), _borrower).debtOhm,
            100e9,
            "Older debt remains"
        );
        assertEq(_asset.balanceOf(_borrower), 8000e6, "Fee funding restored");
        assertEq(_ohm.balanceOf(_borrower), 100e9, "Direct payout rolled back");
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    function _borrowAndService(
        address recipient_
    ) private view returns (IExecutor.Operation[] memory operations) {
        operations = new IExecutor.Operation[](2);
        operations[0] = _borrow(100e9, 1e6, recipient_);
        operations[1] = IExecutor.Operation(
            IExecutor.OperationKind.Repay,
            abi.encode(IExecutor.Repay(address(_other), 100e9))
        );
    }

    // Scenarios: BLREX-A23.
    function test_whenWrongAssetBoundarySeeds_reverts() public {
        for (uint8 action; action < 4; ++action) {
            for (uint8 mode; mode < 4; ++mode) {
                uint256 snapshot = vm.snapshotState();
                _assertWrongAsset(mode < 2, mode % 2 == 0, action);
                assertTrue(vm.revertToState(snapshot), "Restore market and grant mode");
            }
        }
    }

    function _assertWrongAsset(bool inlineGrant_, bool multiple_, uint8 selection_) private {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        uint256 walletBefore = _other.balanceOf(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansAuth.BurnerLoansAuth_AssetMismatch.selector,
                address(_asset),
                address(_other)
            )
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_other), 1e18),
            _single(_operation(selection_)),
            new IExecutor.Output[](0)
        );
        IBurnerLoansCore.Position memory second = _lens.getPosition(address(_other), _borrower);
        assertEq(second.depositedCollateral, 2000e18, "Second market collateral untouched");
        assertEq(second.debtOhm, 100e9, "Second market principal untouched");
        assertEq(_other.balanceOf(_borrower), walletBefore, "Funding restored");
        assertEq(_position().depositedCollateral, 0, "Granted market untouched");
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    function _operation(uint8 selection_) private view returns (IExecutor.Operation memory) {
        address asset = address(_other);
        if (selection_ == 0) {
            return
                IExecutor.Operation(
                    IExecutor.OperationKind.Deposit,
                    abi.encode(IExecutor.Deposit(asset, 1))
                );
        }
        if (selection_ == 1) {
            return
                IExecutor.Operation(
                    IExecutor.OperationKind.Borrow,
                    abi.encode(IExecutor.Borrow(asset, 1e9, _borrower, 1e18, address(0)))
                );
        }
        if (selection_ == 2) {
            return
                IExecutor.Operation(
                    IExecutor.OperationKind.Withdraw,
                    abi.encode(IExecutor.Withdraw(asset, 1, _borrower, asset, 1))
                );
        }
        return
            IExecutor.Operation(
                IExecutor.OperationKind.Extend,
                abi.encode(IExecutor.Extend(asset, 1, 1e18, address(0)))
            );
    }
}
