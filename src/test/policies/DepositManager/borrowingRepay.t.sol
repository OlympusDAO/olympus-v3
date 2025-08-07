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
            IDepositManager.BorrowingRepayParams({asset: iAsset, payer: RECIPIENT, amount: 1e18})
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
            IDepositManager.BorrowingRepayParams({asset: iAsset, payer: RECIPIENT, amount: 1e18})
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
            IDepositManager.BorrowingRepayParams({asset: iAsset, payer: RECIPIENT, amount: 1e18})
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
        _expectRevertBorrowedAmountExceeded(1e18, 0);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({asset: iAsset, payer: RECIPIENT, amount: 1e18})
        );
    }

    // when the repayment amount exceeds the borrowed amount
    //  [X] it reverts

    function test_whenAmountExceedsBorrowed_reverts(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(1e18)
    {
        amount_ = bound(amount_, previousRecipientBorrowActualAmount + 1, type(uint256).max);

        // Expect revert
        _expectRevertBorrowedAmountExceeded(amount_, previousRecipientBorrowActualAmount);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({asset: iAsset, payer: RECIPIENT, amount: amount_})
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
        givenBorrow(1e18)
    {
        // Expect revert
        _expectRevertERC20InsufficientAllowance();

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: previousRecipientBorrowActualAmount
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
        givenBorrow(1e18)
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
            IDepositManager.BorrowingRepayParams({asset: iAsset, payer: RECIPIENT, amount: amount_})
        );
    }

    // [X] it transfers the assets from the payer to the deposit manager
    // [X] it emits an event
    // [X] it returns the actual amount of transferred assets
    // [X] it reduces the borrowed amount by the actual amount repaid
    // [X] it increases the borrowing capacity by the actual amount repaid
    // [X] it increases the operator shares by the actual amount (in terms of shares) repaid

    function test_success(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(1e18)
        givenRecipientHasApprovedSpendingAsset(previousRecipientBorrowActualAmount)
    {
        // Calculate amount
        uint256 oneShareInAssets = vault.previewMint(1);
        amount_ = bound(amount_, oneShareInAssets, previousRecipientBorrowActualAmount);
        _takeSnapshot(amount_);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit BorrowingRepayment(address(iAsset), DEPOSIT_OPERATOR, RECIPIENT, amount_);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({asset: iAsset, payer: RECIPIENT, amount: amount_})
        );

        // Assert tokens
        assertEq(actualAmount, amount_, "actual amount");
        assertEq(
            iAsset.balanceOf(RECIPIENT),
            previousRecipientBorrowActualAmount - amount_,
            "recipient balance"
        );

        // Borrowed amounts
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            previousRecipientBorrowActualAmount - amount_,
            "borrowed amount"
        );
        assertEq(
            depositManager.getBorrowingCapacity(iAsset, DEPOSIT_OPERATOR),
            previousDepositorDepositActualAmount - previousRecipientBorrowActualAmount + amount_,
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
}
