// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test actions assert their effects directly; return values are intentionally unused.
// forge-lint: disable-start(unused-return)

import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

abstract contract BurnerLoansClaimYieldTestBase is BurnerLoansTest {
    uint128 internal constant _COLLATERAL_AMOUNT = 100e6;

    MockERC20 internal vaultAsset;
    MockERC4626 internal vault;

    function setUp() public virtual override {
        super.setUp();
        _setDefaultGlobalDebtCap();
        _configureClaimAsset();
    }

    /// @notice Adds a vault-backed asset used by claim tests.
    function _configureClaimAsset() internal {
        (vaultAsset, vault) = _addVaultAssetForTest();
    }

    /// @notice Deposits the fixture collateral amount for Alice.
    function _depositCollateral() internal {
        vaultAsset.mint(alice, _COLLATERAL_AMOUNT);
        vm.startPrank(alice);
        vaultAsset.approve(address(burnerLoans), _COLLATERAL_AMOUNT);
        burnerLoans.depositCollateral(address(vaultAsset), _COLLATERAL_AMOUNT, alice);
        vm.stopPrank();
    }

    /// @notice Mints vault assets to simulate earned yield.
    function _addYield(uint256 amount_) internal {
        vaultAsset.mint(address(vault), amount_);
    }

    /// @notice Creates claimable yield for a direct-custody asset through a debt-backed
    ///         over-repayment funded by the operator.
    function _addDirectCustodyYield(uint256 claimableYield_) internal {
        uint256 principal = 1;
        uint256 surplus = claimableYield_ + 1;
        uint256 repaymentAmount = principal + surplus;

        usds.mint(address(burnerLoans), principal + surplus);
        vm.startPrank(address(burnerLoans));
        usds.approve(address(depositManager), principal + repaymentAmount);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: IERC20(address(usds)),
                depositPeriod: BurnerLoansConstants.DEPOSIT_PERIOD,
                depositor: address(burnerLoans),
                amount: principal,
                shouldWrap: false
            })
        );
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: IERC20(address(usds)),
                recipient: address(burnerLoans),
                amount: principal
            })
        );

        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: IERC20(address(usds)),
                payer: address(burnerLoans),
                amount: repaymentAmount,
                maxAmount: principal
            })
        );
        vm.stopPrank();
    }

    /// @notice Burns vault assets to simulate a custody shortfall.
    function _causeShortfall(uint256 amount_) internal {
        vaultAsset.burn(address(vault), amount_);
    }

    /// @notice Asserts every borrower position field is unchanged.
    function _assertPositionEq(
        IBurnerLoans.Position memory actual_,
        IBurnerLoans.Position memory expected_
    ) internal pure {
        assertEq(actual_.depositedCollateral, expected_.depositedCollateral, "collateral");
        assertEq(actual_.debtOhm, expected_.debtOhm, "debt");
        assertEq(actual_.maturity, expected_.maturity, "maturity");
        assertEq(actual_.lastBorrowBlock, expected_.lastBorrowBlock, "last borrow block");
    }
}

// forge-lint: disable-end(unused-return)
