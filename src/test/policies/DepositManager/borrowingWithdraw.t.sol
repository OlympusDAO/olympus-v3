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

    function test_givenNotDepositOperator_reverts(
        address caller_
    ) public givenIsEnabled givenFacilityNameIsSetDefault {
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

    function test_whenRecipientIsZeroAddress_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
    {
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

    function test_givenAssetNotConfigured_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
    {
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
        givenFacilityNameIsSetDefault
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
        givenFacilityNameIsSetDefault
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
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        amount_ = bound(
            amount_,
            5, // 1 risks a ZERO_SHARES error
            previousDepositorDepositActualAmount
        );

        uint256 firstDepositActualAmount = previousDepositorDepositActualAmount;

        // Make another deposit
        // This reduces rounding issues with conversion between shares and assets
        {
            asset.mint(DEPOSITOR, MINT_AMOUNT);
            _approveSpendingAsset(DEPOSITOR, MINT_AMOUNT);
            _deposit(MINT_AMOUNT, false);
        }

        _takeSnapshot(amount_);

        // Expect event
        // The amount can be off by a few wei, so don't assert that
        vm.expectEmit(true, true, true, false);
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
        assertApproxEqAbs(actualAmount, amount_, 5, "actual amount");
        assertEq(iAsset.balanceOf(RECIPIENT), actualAmount, "withdrawn amount");

        // Borrowed amounts
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            amount_,
            "borrowed amount"
        );
        assertEq(
            depositManager.getBorrowingCapacity(iAsset, DEPOSIT_OPERATOR),
            firstDepositActualAmount + previousDepositorDepositActualAmount - amount_,
            "borrowing capacity"
        );

        // Operator assets should be reduced
        (uint256 operatorShares, uint256 operatorSharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        assertApproxEqAbs(
            operatorShares,
            _operatorSharesBefore - _expectedWithdrawnShares,
            5,
            "operator shares"
        );

        assertApproxEqAbs(
            operatorSharesInAssets,
            _operatorSharesInAssetsBefore - amount_,
            5,
            "operator shares in assets"
        );

        assertApproxEqAbs(
            vault.balanceOf(address(depositManager)),
            _depositManagerSharesBefore - _expectedWithdrawnShares,
            5,
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
        givenFacilityNameIsSetDefault
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
        givenFacilityNameIsSetDefault
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
        givenBorrow(1e18)
    {
        amount_ = bound(
            amount_,
            5, // 1 risks a ZERO_SHARES error
            previousDepositorDepositActualAmount - previousRecipientBorrowActualAmount
        );
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

        // Snapshot
        _takeSnapshot(amount_);

        // Expect event
        // The amount can be off by a few wei, so don't assert that
        vm.expectEmit(true, true, true, false);
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
        assertApproxEqAbs(actualAmount, amount_, 5, "actual amount");
        assertEq(
            iAsset.balanceOf(RECIPIENT),
            previousRecipientBorrowActualAmount + actualAmount,
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
            firstDepositActualAmount +
                previousDepositorDepositActualAmount -
                previousRecipientBorrowActualAmount -
                amount_,
            "borrowing capacity"
        );

        // Operator assets should be reduced
        (uint256 operatorShares, uint256 operatorSharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        assertApproxEqAbs(
            operatorShares,
            _operatorSharesBefore - _expectedWithdrawnShares,
            5,
            "operator shares"
        );

        assertApproxEqAbs(
            operatorSharesInAssets,
            _operatorSharesInAssetsBefore - amount_,
            5,
            "operator shares in assets"
        );

        assertApproxEqAbs(
            vault.balanceOf(address(depositManager)),
            _depositManagerSharesBefore - _expectedWithdrawnShares,
            5,
            "vault balance"
        );
    }
}
