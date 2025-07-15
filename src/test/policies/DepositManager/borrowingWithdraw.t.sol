// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

contract DepositManagerBorrowingWithdrawTest is DepositManagerTest {
    event BorrowingWithdrawal(
        address indexed asset,
        address indexed operator,
        address indexed recipient,
        uint256 amount
    );

    uint256 public _expectedWithdrawnShares;
    uint256 public _depositManagerSharesBefore;
    uint256 public _operatorSharesBefore;
    uint256 public _operatorSharesInAssetsBefore;

    function _takeSnapshot(uint256 amount_) internal {
        _expectedWithdrawnShares = vault.previewWithdraw(amount_);

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
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 1e18
            })
        );
    }

    // given the caller is not a deposit operator
    //  [X] it reverts

    function test_givenNotDepositOperator_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != DEPOSIT_OPERATOR);

        // Expect revert
        _expectRevertNotDepositOperator();

        // Call function
        vm.prank(caller_);
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 1e18
            })
        );
    }

    // when the recipient is the zero address
    //  [X] it reverts

    function test_whenRecipientIsZeroAddress_reverts() public givenIsEnabled {
        // Expect revert
        _expectRevertZeroAddress();

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: address(0),
                amount: 1e18
            })
        );
    }

    // given the asset is not configured
    //  [X] it reverts

    function test_givenAssetNotConfigured_reverts() public givenIsEnabled {
        // Expect revert
        _expectRevertNotConfiguredAsset();

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 1e18
            })
        );
    }

    // given there are no deposits
    //  [X] it reverts

    function test_givenNoDeposits_reverts()
        public
        givenIsEnabled
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        // Expect revert
        _expectRevertBorrowingLimitExceeded(1e18, 0);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 1e18
            })
        );
    }

    // given there are no deposits borrowed
    //  when the borrow amount exceeds the deposits
    //   [X] it reverts

    function test_givenNoBorrow_whenAmountExceedsDeposits_reverts(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        amount_ = bound(amount_, previousDepositorDepositActualAmount + 1, type(uint256).max);

        // Expect revert
        _expectRevertBorrowingLimitExceeded(amount_, previousDepositorDepositActualAmount);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: amount_
            })
        );
    }

    //  [X] it transfers the assets to the recipient
    //  [X] it emits an event
    //  [X] it returns the actual amount of transferred assets
    //  [X] it increases the borrowed amount by the actual amount withdrawn
    //  [X] it reduces the borrowing capacity by the actual amount withdrawn
    //  [X] it reduces the operator shares by the actual amount (in terms of shares) withdrawn

    function test_givenNoBorrow(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        amount_ = bound(amount_, 1, previousDepositorDepositActualAmount);
        _takeSnapshot(amount_);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit BorrowingWithdrawal(address(iAsset), DEPOSIT_OPERATOR, RECIPIENT, amount_);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: amount_
            })
        );

        // Assert tokens
        assertEq(actualAmount, amount_, "actual amount");
        assertEq(iAsset.balanceOf(RECIPIENT), amount_, "withdrawn amount");

        // Borrowed amounts
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            amount_,
            "borrowed amount"
        );
        assertEq(
            depositManager.getBorrowingCapacity(iAsset, DEPOSIT_OPERATOR),
            previousDepositorDepositActualAmount - amount_,
            "borrowing capacity"
        );

        // Operator assets should be reduced
        (uint256 operatorShares, uint256 operatorSharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        assertEq(
            operatorShares,
            _operatorSharesBefore - _expectedWithdrawnShares,
            "operator shares"
        );

        assertApproxEqAbs(
            operatorSharesInAssets,
            _operatorSharesInAssetsBefore - amount_,
            1,
            "operator shares in assets"
        );

        assertEq(
            vault.balanceOf(address(depositManager)),
            _depositManagerSharesBefore - _expectedWithdrawnShares,
            "vault balance"
        );
    }

    // when the borrow amount exceeds the un-borrowed deposits
    //  [X] it reverts

    function test_whenAmountExceedsUnborrowed_reverts(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(1e18)
    {
        amount_ = bound(
            amount_,
            previousDepositorDepositActualAmount - previousRecipientBorrowActualAmount + 1,
            type(uint256).max
        );

        // Expect revert
        _expectRevertBorrowingLimitExceeded(
            amount_,
            previousDepositorDepositActualAmount - previousRecipientBorrowActualAmount
        );

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: amount_
            })
        );
    }

    // when the borrow amount is less than one vault share
    //  [X] it reverts

    function test_whenBorrowAmountIsLessThanOneShare_reverts(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(1e18)
    {
        // Determine an amount that would be less than one share
    }

    // [X] it transfers the assets to the recipient
    // [X] it emits an event
    // [X] it returns the actual amount of transferred assets
    // [X] it increases the borrowed amount by the actual amount withdrawn
    // [X] it reduces the borrowing capacity by the actual amount withdrawn
    // [X] it reduces the operator shares by the actual amount (in terms of shares) withdrawn

    function test_success(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(1e18)
    {
        amount_ = bound(
            amount_,
            1,
            previousDepositorDepositActualAmount - previousRecipientBorrowActualAmount
        );
        _takeSnapshot(amount_);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit BorrowingWithdrawal(address(iAsset), DEPOSIT_OPERATOR, RECIPIENT, amount_);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: amount_
            })
        );

        // Assert tokens
        assertEq(actualAmount, amount_, "actual amount");
        assertEq(
            iAsset.balanceOf(RECIPIENT),
            previousRecipientBorrowActualAmount + amount_,
            "recipient balance"
        );

        // Borrowed amounts
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            previousRecipientBorrowActualAmount + amount_,
            "borrowed amount"
        );
        assertEq(
            depositManager.getBorrowingCapacity(iAsset, DEPOSIT_OPERATOR),
            previousDepositorDepositActualAmount - previousRecipientBorrowActualAmount - amount_,
            "borrowing capacity"
        );

        // Operator assets should be reduced
        (uint256 operatorShares, uint256 operatorSharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        assertEq(
            operatorShares,
            _operatorSharesBefore - _expectedWithdrawnShares,
            "operator shares"
        );

        assertApproxEqAbs(
            operatorSharesInAssets,
            _operatorSharesInAssetsBefore - amount_,
            1,
            "operator shares in assets"
        );

        assertEq(
            vault.balanceOf(address(depositManager)),
            _depositManagerSharesBefore - _expectedWithdrawnShares,
            "vault balance"
        );
    }
}
