// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

contract DepositManagerBorrowingDefaultTest is DepositManagerTest {
    event BorrowingDefault(
        address indexed asset,
        address indexed operator,
        address indexed payer,
        uint256 amount
    );

    uint256 public constant BORROW_AMOUNT = 1e18;

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
}
