// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// Calls whose effects are asserted directly intentionally ignore return values, and test cheatcode
// calls do not model production reentrancy.
// forge-lint: disable-start(literal-instead-of-constant, reentrancy-no-eth, unused-return)

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";

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

    // given an existing borrow and disabled asset period
    //  [X] repayment remains available for servicing the liability

    function test_givenAssetPeriodIsDisabled_repaysExistingBorrow()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenRecipientHasApprovedSpendingAsset(BORROW_AMOUNT)
        givenAssetPeriodIsDisabled
    {
        asset.mint(RECIPIENT, BORROW_AMOUNT);

        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: BORROW_AMOUNT,
                maxAmount: BORROW_AMOUNT
            })
        );

        // The vault credits the assets represented by deposited shares, so the received amount
        // can round down by one underlying unit. Debt must fall by that authoritative amount.
        assertGt(actualAmount, 0, "repayment should transfer a positive amount");
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            BORROW_AMOUNT - actualAmount,
            "disabled period should not prevent debt repayment"
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

    function test_givenAsyncDepositBecomesEnabled_revertsAndRollsBackTransfer() public {
        MockERC7540ExternalShareVault externalVault = new MockERC7540ExternalShareVault(
            asset,
            false,
            false,
            true
        );
        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(externalVault)), type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();
        externalVault.setCapabilities(true, false, true, true);
        asset.mint(RECIPIENT, 10e18);
        uint256 payerBalanceBefore = asset.balanceOf(RECIPIENT);
        vm.prank(RECIPIENT);
        asset.approve(address(depositManager), 10e18);

        vm.expectRevert(MockERC7540ExternalShareVault.AsyncDeposit.selector);
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: 10e18,
                maxAmount: 0
            })
        );

        assertEq(asset.balanceOf(RECIPIENT), payerBalanceBefore, "payer balance rollback");
        assertEq(asset.balanceOf(address(depositManager)), 0, "manager balance rollback");
        assertEq(asset.balanceOf(address(externalVault)), 0, "vault balance unchanged");
    }

    function test_givenExternalShareToken_whenRedeemModeIsFuzzed(bool asyncRedeem_) public {
        MockERC7540ExternalShareVault externalVault = new MockERC7540ExternalShareVault(
            asset,
            false,
            asyncRedeem_,
            true
        );
        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(externalVault)), type(uint256).max, 0);
        vm.stopPrank();
        asset.mint(RECIPIENT, 10e18);
        vm.prank(RECIPIENT);
        asset.approve(address(depositManager), 10e18);

        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: 10e18,
                maxAmount: 0
            })
        );

        (uint256 operatorShares, uint256 operatorAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        assertEq(actualAmount, 10e18, "repayment credit");
        assertEq(operatorShares, 10e6, "raw external shares");
        assertEq(operatorAssets, 10e18, "external shares in assets");
        assertEq(
            IERC20(externalVault.share()).balanceOf(address(depositManager)),
            10e6,
            "external share custody"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, reentrancy-no-eth, unused-return)
