// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

contract DepositManagerBorrowingRepayTest is DepositManagerTest {
    event BorrowingRepayment(
        address indexed asset,
        address indexed operator,
        address indexed payer,
        uint256 amount
    );

    uint256 public _expectedDepositedShares;
    uint256 public _depositManagerSharesBefore;
    uint256 public _operatorSharesBefore;
    uint256 public _operatorSharesInAssetsBefore;

    uint256 public constant BORROW_AMOUNT = 1e18;

    function _takeSnapshot(uint256 amount_) internal {
        _expectedDepositedShares = vault.previewDeposit(amount_);

        _depositManagerSharesBefore = vault.balanceOf(address(depositManager));

        (_operatorSharesBefore, _operatorSharesInAssetsBefore) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
    }

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: BORROW_AMOUNT,
                maxAmount: BORROW_AMOUNT
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
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: BORROW_AMOUNT,
                maxAmount: BORROW_AMOUNT
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
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: BORROW_AMOUNT,
                maxAmount: BORROW_AMOUNT
            })
        );
    }

    // given no funds have been borrowed
    //  [X] it transfers the assets from the payer to the deposit manager
    //  [X] it returns the actual amount of transferred assets
    //  [X] the borrowed amount is unaffected
    //  [X] the borrowing capacity is unaffected
    //  [X] it increases the operator shares by the actual amount (in terms of shares) repaid

    function test_givenNoBorrows()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenRecipientHasApprovedSpendingAsset(BORROW_AMOUNT)
    {
        // Mint the asset to the recipient
        asset.mint(RECIPIENT, BORROW_AMOUNT);

        _takeSnapshot(BORROW_AMOUNT);
        uint256 recipientAssetBalanceBefore = iAsset.balanceOf(address(RECIPIENT));

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: BORROW_AMOUNT,
                maxAmount: 0
            })
        );

        // Assert token balance
        assertEq(iAsset.balanceOf(address(RECIPIENT)), recipientAssetBalanceBefore - BORROW_AMOUNT);

        // Borrowed amounts
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            0,
            "borrowed amount" // No borrows, but it also doesn't underflow
        );
        assertEq(
            depositManager.getBorrowingCapacity(iAsset, DEPOSIT_OPERATOR),
            previousDepositorDepositActualAmount, // Full deposit
            "borrowing capacity"
        );

        // Operator assets should be increased
        (uint256 operatorShares, uint256 operatorSharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        assertEq(
            operatorShares,
            _operatorSharesBefore + _expectedDepositedShares,
            "operator shares"
        );

        assertApproxEqAbs(
            operatorSharesInAssets,
            _operatorSharesInAssetsBefore + BORROW_AMOUNT,
            1,
            "operator shares in assets"
        );

        assertEq(
            vault.balanceOf(address(depositManager)),
            _depositManagerSharesBefore + _expectedDepositedShares,
            "vault balance"
        );
    }

    // when the repayment amount exceeds the borrowed amount
    //  given there is second loan
    //   [X] _borrowedAmounts is reduced by the amount repaid, capped at the principal amount of the first loan

    function test_whenAmountExceedsBorrowed_givenSecondLoan(
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
        givenDepositorHasAsset(MINT_AMOUNT)
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenRecipientHasApprovedSpendingAsset(100e18)
    {
        amount_ = bound(amount_, BORROW_AMOUNT + 1, 100e18);

        // Mint the repayment amount to the recipient
        asset.mint(RECIPIENT, amount_);

        _takeSnapshot(amount_);
        uint256 recipientAssetBalanceBefore = iAsset.balanceOf(address(RECIPIENT));

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: amount_,
                maxAmount: BORROW_AMOUNT
            })
        );

        // Assert token balance
        assertEq(iAsset.balanceOf(address(RECIPIENT)), recipientAssetBalanceBefore - amount_);

        // Borrowed amounts
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            BORROW_AMOUNT,
            "borrowed amount" // Does not go below the principal amount of the second loan
        );
        assertEq(
            depositManager.getBorrowingCapacity(iAsset, DEPOSIT_OPERATOR),
            previousDepositorReceiptTokenBalance - BORROW_AMOUNT, // Repaid amount is available for borrowing
            "borrowing capacity"
        );

        // Operator assets should be increased
        (uint256 operatorShares, uint256 operatorSharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        assertEq(
            operatorShares,
            _operatorSharesBefore + _expectedDepositedShares,
            "operator shares"
        );

        assertApproxEqAbs(
            operatorSharesInAssets,
            _operatorSharesInAssetsBefore + amount_,
            1,
            "operator shares in assets"
        );

        assertEq(
            vault.balanceOf(address(depositManager)),
            _depositManagerSharesBefore + _expectedDepositedShares,
            "vault balance"
        );
    }

    //  [X] it transfers the assets from the payer to the deposit manager
    //  [X] it returns the actual amount of transferred assets
    //  [X] _borrowedAmounts is reduced by the actual amount repaid
    //  [X] the borrowing capacity is increased by the actual amount repaid
    //  [X] it increases the operator shares by the actual amount (in terms of shares) repaid

    function test_whenAmountExceedsBorrowed(
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
        givenRecipientHasApprovedSpendingAsset(100e18)
    {
        amount_ = bound(amount_, BORROW_AMOUNT + 1, 100e18);

        // Mint the repayment amount to the recipient
        asset.mint(RECIPIENT, amount_);

        _takeSnapshot(amount_);
        uint256 recipientAssetBalanceBefore = iAsset.balanceOf(address(RECIPIENT));

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: amount_,
                maxAmount: BORROW_AMOUNT
            })
        );

        // Assert token balance
        assertEq(iAsset.balanceOf(address(RECIPIENT)), recipientAssetBalanceBefore - amount_);

        // Borrowed amounts
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            0,
            "borrowed amount" // No underflow
        );
        assertEq(
            depositManager.getBorrowingCapacity(iAsset, DEPOSIT_OPERATOR),
            previousDepositorDepositActualAmount, // Full deposit
            "borrowing capacity"
        );

        // Operator assets should be increased
        (uint256 operatorShares, uint256 operatorSharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        assertEq(
            operatorShares,
            _operatorSharesBefore + _expectedDepositedShares,
            "operator shares"
        );

        assertApproxEqAbs(
            operatorSharesInAssets,
            _operatorSharesInAssetsBefore + amount_,
            1,
            "operator shares in assets"
        );

        assertEq(
            vault.balanceOf(address(depositManager)),
            _depositManagerSharesBefore + _expectedDepositedShares,
            "vault balance"
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
        _expectRevertERC20InsufficientAllowance();

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: previousRecipientBorrowActualAmount,
                maxAmount: BORROW_AMOUNT
            })
        );
    }

    // given the amount is less than one share
    //  [X] it reverts

    function test_whenAmountLessThanOneShare(
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
        givenRecipientHasApprovedSpendingAsset(previousRecipientBorrowActualAmount)
    {
        // Calculate amount
        uint256 oneShareInAssets = vault.previewMint(1);
        amount_ = bound(amount_, 1, oneShareInAssets - 1);

        // Expect revert
        vm.expectRevert("ZERO_SHARES");

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: amount_,
                maxAmount: BORROW_AMOUNT
            })
        );
    }

    // [X] it transfers the assets from the payer to the deposit manager
    // [X] it emits an event
    // [X] it returns the actual amount of transferred assets
    // [X] it reduces the borrowed amount by the actual amount repaid
    // [X] it increases the borrowing capacity by the actual amount repaid
    // [X] it increases the operator shares by the actual amount (in terms of shares) repaid

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
        givenRecipientHasApprovedSpendingAsset(previousRecipientBorrowActualAmount)
    {
        // Calculate amount
        uint256 oneShareInAssets = vault.previewMint(1);
        amount_ = bound(amount_, oneShareInAssets, previousRecipientBorrowActualAmount);
        yieldAmount_ = bound(yieldAmount_, 1e16, 50e18);

        uint256 firstDepositActualAmount = previousDepositorDepositActualAmount;

        // Make another deposit
        // This reduces rounding issues with conversion between shares and assets
        {
            asset.mint(DEPOSITOR, MINT_AMOUNT);
            _approveSpendingAsset(DEPOSITOR, MINT_AMOUNT);
            _deposit(MINT_AMOUNT, false);
        }

        // Accrue yield
        _accrueYield(yieldAmount_);

        _takeSnapshot(amount_);

        // Expect event
        // The amount can be off by a few wei, so don't assert that
        vm.expectEmit(true, true, true, false);
        emit BorrowingRepayment(address(iAsset), DEPOSIT_OPERATOR, RECIPIENT, amount_);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: amount_,
                maxAmount: BORROW_AMOUNT
            })
        );

        // Assert tokens
        assertApproxEqAbs(actualAmount, amount_, 5, "actual amount");
        assertEq(
            iAsset.balanceOf(RECIPIENT),
            previousRecipientBorrowActualAmount - amount_,
            "recipient balance"
        );

        // Borrowed amounts
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            BORROW_AMOUNT - actualAmount,
            "borrowed amount"
        );
        assertEq(
            depositManager.getBorrowingCapacity(iAsset, DEPOSIT_OPERATOR),
            firstDepositActualAmount +
                previousDepositorDepositActualAmount -
                BORROW_AMOUNT +
                actualAmount,
            "borrowing capacity"
        );

        // Operator assets should be increased
        (uint256 operatorShares, uint256 operatorSharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        assertEq(
            operatorShares,
            _operatorSharesBefore + _expectedDepositedShares,
            "operator shares"
        );

        assertApproxEqAbs(
            operatorSharesInAssets,
            _operatorSharesInAssetsBefore + actualAmount,
            5,
            "operator shares in assets"
        );

        assertEq(
            vault.balanceOf(address(depositManager)),
            _depositManagerSharesBefore + _expectedDepositedShares,
            "vault balance"
        );
    }
}
