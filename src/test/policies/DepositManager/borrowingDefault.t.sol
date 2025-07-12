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
                payer: RECIPIENT,
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
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: RECIPIENT,
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
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: RECIPIENT,
                amount: 1e18
            })
        );
    }

    // given no funds have been borrowed
    //  [X] it reverts

    function test_givenNoBorrows_reverts()
        public
        givenIsEnabled
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        // Expect revert
        _expectRevertBorrowedAmountExceeded(1e18, 0);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: RECIPIENT,
                amount: 1e18
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
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(1e18)
    {
        amount_ = bound(amount_, 1e18, 1e18 * 100);

        // Expect revert
        _expectRevertBorrowedAmountExceeded(1e18, 0);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: RECIPIENT,
                amount: 1e18
            })
        );
    }

    // given the payer has not approved spending of the asset
    //  [X] it reverts

    function test_givenAssetSpendingNotApproved_reverts()
        public
        givenIsEnabled
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
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: RECIPIENT,
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
        uint256 amount_
    )
        public
        givenIsEnabled
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

        // Determine the amount of shares that are expected
        uint256 expectedShares;
        {
            (uint256 beforeShares, uint256 beforeSharesInAssets) = depositManager.getOperatorAssets(
                iAsset,
                DEPOSIT_OPERATOR
            );

            // Calculate the amount of shares that will be burned
            // TODO is this going to be accurate, given the amount has already been withdrawn?
            uint256 sharesToBurn = iVault.previewWithdraw(amount_);

            // Calculate the amount of shares that will be retained
            expectedShares = beforeShares - sharesToBurn;
        }

        uint256 expectedBorrowingCapacity = depositManager.getBorrowingCapacity(
            iAsset,
            DEPOSIT_OPERATOR
        );

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit BorrowingDefault(address(iAsset), DEPOSIT_OPERATOR, RECIPIENT, amount_);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: RECIPIENT,
                amount: amount_
            })
        );

        // Assertions
        // Assert receipt token balances
        assertEq(
            depositManager.balanceOf(
                RECIPIENT,
                depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD)
            ),
            MINT_AMOUNT - amount_,
            "receipt token balance"
        );

        // Assert borrowed amounts
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            previousRecipientBorrowActualAmount - amount_,
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
            MINT_AMOUNT - amount_,
            "asset liabilities"
        );

        // Assert operator shares
        (uint256 shares, ) = depositManager.getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        assertEq(shares, expectedShares, "operator shares");
    }
}
