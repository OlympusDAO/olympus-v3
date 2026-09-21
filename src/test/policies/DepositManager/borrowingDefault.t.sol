// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Tuple components not relevant to these scenarios are intentionally ignored.
// forge-lint: disable-start(unused-return)

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";

contract DepositManagerBorrowingDefaultTest is DepositManagerTest {
    event BorrowingDefault(
        address indexed asset,
        address indexed operator,
        address indexed payer,
        uint256 amount
    );

    uint256 public constant BORROW_AMOUNT = 1e18;
    uint256 internal constant _ASYNC_DEPOSIT_AMOUNT = 10e18;
    uint256 internal constant _ASYNC_BORROW_AMOUNT = 2e18;

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: DEPOSITOR,
                amount: BORROW_AMOUNT
            })
        );
    }

    // given the caller is not a deposit operator
    //  [X] it reverts

    function test_givenNotDepositOperator_reverts(
        address caller_
    ) public givenIsEnabled givenFacilityNameIsSetDefault {
        vm.assume(caller_ != DEPOSIT_OPERATOR);

        // Expect revert
        _expectRevertNotDepositOperator();

        // Call function
        vm.prank(caller_);
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: DEPOSITOR,
                amount: BORROW_AMOUNT
            })
        );
    }

    // given the asset is not configured
    //  [X] it reverts

    function test_givenAssetNotConfigured_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
    {
        // Expect revert
        _expectRevertNotConfiguredAsset();

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: DEPOSITOR,
                amount: BORROW_AMOUNT
            })
        );
    }

    // given no funds have been borrowed
    //  [X] it reverts

    function test_givenNoBorrows_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        // Expect revert
        _expectRevertBorrowedAmountExceeded(BORROW_AMOUNT, 0);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: DEPOSITOR,
                amount: BORROW_AMOUNT
            })
        );
    }

    // given the default amount exceeds the borrowed amount
    //  [X] it reverts

    function test_whenDefaultAmountExceedsBorrowed_reverts(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenDepositorHasApprovedSpendingReceiptToken(previousRecipientBorrowActualAmount)
    {
        amount_ = bound(amount_, BORROW_AMOUNT + 1, BORROW_AMOUNT * 100);

        // Expect revert
        _expectRevertBorrowedAmountExceeded(amount_, BORROW_AMOUNT);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: DEPOSITOR,
                amount: amount_
            })
        );
    }

    // given the payer has not approved spending of the asset
    //  [X] it reverts

    function test_givenAssetSpendingNotApproved_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
    {
        uint256 borrowedBefore = depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR);
        uint256 liabilitiesBefore = depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR);

        // Expect revert
        _expectRevertReceiptTokenInsufficientAllowance(0, previousRecipientBorrowActualAmount);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: DEPOSITOR,
                amount: previousRecipientBorrowActualAmount
            })
        );

        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            borrowedBefore,
            "failed burn should preserve borrowed amount"
        );
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            liabilitiesBefore,
            "failed burn should preserve liabilities"
        );
    }

    // given an existing borrow and disabled asset period
    //  [X] default remains available for servicing the liability

    function test_givenAssetPeriodIsDisabled_defaultsExistingBorrow()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenDepositorHasApprovedSpendingReceiptToken(BORROW_AMOUNT)
        givenAssetPeriodIsDisabled
    {
        uint256 liabilitiesBefore = depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: DEPOSITOR,
                amount: BORROW_AMOUNT
            })
        );

        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            0,
            "disabled period should not prevent default"
        );
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            liabilitiesBefore - BORROW_AMOUNT,
            "default should reduce liabilities"
        );
    }

    // [X] it burns the receipt tokens
    // [X] it reduces the borrowed amount by the default amount
    // [X] it does not change the borrowing capacity
    // [X] it emits a BorrowingDefault event
    // [X] it reduces the operator shares by the default amount (in terms of shares)
    // [X] it reduces the asset liabilities by the default amount

    function test_success(
        uint256 amount_,
        uint256 yieldAmount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenDepositorHasApprovedSpendingReceiptToken(previousRecipientBorrowActualAmount)
    {
        // Calculate amount
        amount_ = bound(amount_, vault.previewMint(1), previousRecipientBorrowActualAmount);
        yieldAmount_ = bound(yieldAmount_, 1e16, 50e18);

        // Accrue yield
        _accrueYield(yieldAmount_);

        // Determine the amount of shares that are expected
        (, uint256 expectedAssets) = depositManager.getOperatorAssets(iAsset, DEPOSIT_OPERATOR);

        uint256 expectedBorrowingCapacity = depositManager.getBorrowingCapacity(
            iAsset,
            DEPOSIT_OPERATOR
        );

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit BorrowingDefault(address(iAsset), DEPOSIT_OPERATOR, DEPOSITOR, amount_);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: DEPOSITOR,
                amount: amount_
            })
        );

        // Assertions
        // Assert receipt token balances
        assertEq(
            receiptTokenManager.balanceOf(
                DEPOSITOR,
                depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
            ),
            previousDepositorDepositActualAmount - amount_,
            "receipt token balance"
        );

        // Assert borrowed amounts
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            BORROW_AMOUNT - amount_,
            "borrowed amount"
        );

        // Assert borrowing capacity
        assertEq(
            depositManager.getBorrowingCapacity(iAsset, DEPOSIT_OPERATOR),
            expectedBorrowingCapacity,
            "borrowing capacity"
        );

        // Assert asset liabilities
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            previousDepositorDepositActualAmount - amount_,
            "asset liabilities"
        );

        // Assert operator assets
        (, uint256 sharesInAssets) = depositManager.getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        assertEq(sharesInAssets, expectedAssets, "operator assets");
    }

    function test_givenAsyncDepositBecomesEnabled_whenDefaultingExistingBorrow() public {
        MockERC7540ExternalShareVault externalVault = new MockERC7540ExternalShareVault(
            asset,
            false,
            true,
            true
        );
        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(externalVault)), type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        uint256 receiptTokenId = depositManager.addAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        vm.stopPrank();

        _approveSpendingAsset(DEPOSITOR, _ASYNC_DEPOSIT_AMOUNT);
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: _ASYNC_DEPOSIT_AMOUNT,
                shouldWrap: false
            })
        );
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: _ASYNC_BORROW_AMOUNT
            }),
            true
        );
        externalVault.setCapabilities(true, true, true, true);
        vm.prank(DEPOSITOR);
        receiptTokenManager.approve(address(depositManager), receiptTokenId, _ASYNC_BORROW_AMOUNT);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: DEPOSITOR,
                amount: _ASYNC_BORROW_AMOUNT
            })
        );

        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            0,
            "existing borrow should be defaulted"
        );
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            _ASYNC_DEPOSIT_AMOUNT - _ASYNC_BORROW_AMOUNT,
            "default should reduce liabilities"
        );
        assertEq(
            IERC20(externalVault.share()).balanceOf(address(depositManager)),
            (_ASYNC_DEPOSIT_AMOUNT - _ASYNC_BORROW_AMOUNT) / 1e12,
            "default should not move external shares"
        );
    }
}

// forge-lint: disable-end(unused-return)
