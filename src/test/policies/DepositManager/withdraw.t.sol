// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";

// Interfaces
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

contract DepositManagerWithdrawTest is DepositManagerTest {
    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        _expectRevertNotEnabled();

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: DEPOSITOR,
                amount: MINT_AMOUNT,
                isWrapped: false
            })
        );
    }

    // given the caller does not have the deposit operator role
    //  [X] it reverts

    function test_givenCallerDoesNotHaveDepositOperatorRole_reverts(
        address caller_
    ) public givenIsEnabled givenFacilityNameIsSetDefault {
        vm.assume(caller_ != DEPOSIT_OPERATOR);

        _expectRevertNotDepositOperator();

        vm.prank(caller_);
        depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: DEPOSITOR,
                amount: MINT_AMOUNT,
                isWrapped: false
            })
        );
    }

    // given the deposit asset configuration does not exist
    //  [X] it reverts

    function test_givenDepositAssetConfigurationDoesNotExist_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
    {
        _expectRevertInvalidReceiptTokenId(iAsset, DEPOSIT_PERIOD);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: DEPOSITOR,
                amount: MINT_AMOUNT,
                isWrapped: false
            })
        );
    }

    // given wrapped is true
    //  given the depositor has not approved the contract to spend the wrapped receipt token
    //   [X] it reverts

    function test_givenWrappedIsTrue_givenDepositorHasNotApprovedContractToSpendWrappedReceiptToken_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, true)
    {
        _expectRevertERC20CloneInsufficientAllowance();

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: DEPOSITOR,
                amount: previousDepositorDepositActualAmount,
                isWrapped: true
            })
        );
    }

    //  given the depositor's wrapped receipt token balance is less than the amount to withdraw
    //   [X] it reverts

    function test_givenWrappedIsTrue_givenDepositorWrappedReceiptTokenBalanceIsInsufficient_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, true)
        givenDepositorHasApprovedSpendingWrappedReceiptToken(MINT_AMOUNT + 1)
    {
        _expectRevertERC20CloneInsufficientBalance();

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: DEPOSITOR,
                amount: previousDepositorDepositActualAmount + 1,
                isWrapped: true
            })
        );
    }

    //  [X] the wrapped receipt token is burned
    //  [X] the receipt token is not burned

    function test_givenWrappedIsTrue()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, true)
        givenDepositorHasApprovedSpendingWrappedReceiptToken(MINT_AMOUNT)
    {
        uint256 expectedShares = vault.previewWithdraw(previousDepositorDepositActualAmount);

        uint256 actualAmount = _withdraw(previousDepositorDepositActualAmount, true);

        _assertAssetBalance(
            expectedShares,
            previousDepositorDepositActualAmount,
            actualAmount,
            false,
            1
        );
        _assertReceiptToken(0, previousDepositorDepositActualAmount, true, false);
        _assertDepositAssetBalance(DEPOSITOR, previousDepositorDepositActualAmount, 1);

        // As the full amount is being withdrawn, double-check that liabilities are 0
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            0,
            "Liabilities should be 0"
        );
    }

    // given the depositor has not approved the contract to spend the receipt token
    //  [X] it reverts

    function test_givenDepositorHasNotApprovedContractToSpendReceiptToken_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        _expectRevertReceiptTokenInsufficientAllowance(0, previousDepositorDepositActualAmount);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: DEPOSITOR,
                amount: previousDepositorDepositActualAmount,
                isWrapped: false
            })
        );
    }

    // given the depositor's receipt token balance is less than the amount to withdraw
    //  [X] it reverts

    function test_givenDepositorReceiptTokenBalanceIsInsufficient_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT + 1)
    {
        _expectRevertReceiptTokenInsufficientBalance(
            previousDepositorDepositActualAmount,
            MINT_AMOUNT + 1
        );

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: DEPOSITOR,
                amount: MINT_AMOUNT + 1,
                isWrapped: false
            })
        );
    }

    // given the asset configuration has the vault set to the zero address
    //  given there has been a deposit
    //   [X] the operator shares are correct
    //   [X] the asset liabilities are correct

    function test_givenAssetIsAddedWithZeroAddress_givenRemainingDeposit(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAddedWithZeroAddress
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        amount_ = bound(amount_, 1e18, MINT_AMOUNT / 2);

        vm.prank(DEPOSIT_OPERATOR);
        uint256 shares = depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: DEPOSITOR,
                amount: amount_,
                isWrapped: false
            })
        );

        _assertAssetBalance(amount_, amount_, shares, false);
        _assertReceiptToken(amount_, 0, false, false);
        _assertDepositAssetBalance(DEPOSITOR, amount_);
    }

    //  [X] the wrapped receipt token is not burned
    //  [X] the receipt token is burned
    //  [X] the asset liabilities are decreased by the withdrawn amount
    //  [X] the asset is sent to the depositor
    //  [X] the operator shares are decreased by the withdrawn amount

    function test_givenAssetIsAddedWithZeroAddress()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAddedWithZeroAddress
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        vm.prank(DEPOSIT_OPERATOR);
        uint256 shares = depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: DEPOSITOR,
                amount: MINT_AMOUNT,
                isWrapped: false
            })
        );

        _assertAssetBalance(MINT_AMOUNT, MINT_AMOUNT, shares, false);
        _assertReceiptToken(MINT_AMOUNT, 0, false, false);
        _assertDepositAssetBalance(DEPOSITOR, MINT_AMOUNT);
    }

    // given the asset period is disabled
    //  [X] the asset is withdrawn from the vault and sent to the depositor

    function test_givenAssetPeriodIsDisabled()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
        givenAssetPeriodIsDisabled
    {
        uint256 expectedShares = vault.previewWithdraw(previousDepositorDepositActualAmount);

        uint256 actualAmount = _withdraw(previousDepositorDepositActualAmount, false);

        _assertAssetBalance(
            expectedShares,
            previousDepositorDepositActualAmount,
            actualAmount,
            false,
            1
        );
        _assertReceiptToken(previousDepositorDepositActualAmount, 0, false, false);
        _assertDepositAssetBalance(DEPOSITOR, previousDepositorDepositActualAmount, 1);

        // As the full amount is being withdrawn, double-check that liabilities are 0
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            0,
            "Liabilities should be 0"
        );
    }

    // given there has been another deposit
    //  [X] the operator shares are correct
    //  [X] the asset liabilities are correct

    function test_givenRemainingDeposit(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        amount_ = bound(amount_, 1e18, MINT_AMOUNT / 2);
        uint256 expectedShares = vault.previewWithdraw(amount_);

        uint256 actualAmount = _withdraw(amount_, false);

        _assertAssetBalance(expectedShares, amount_, actualAmount, false, 5);
        _assertReceiptToken(amount_, 0, false, false);
        _assertDepositAssetBalance(DEPOSITOR, amount_, 5);
    }

    // when the recipient address is different to the depositor
    //  when the recipient address is the zero address
    //   [X] it reverts

    function test_givenRecipientAddressIsDifferentToDepositor_zeroAddress_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        _expectRevertZeroAddress();

        _withdraw(address(0), previousDepositorDepositActualAmount, false);
    }

    //  [X] the asset is transferred to the recipient

    function test_givenRecipientAddressIsDifferentToDepositor(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        amount_ = bound(amount_, 1e18, MINT_AMOUNT / 2);
        uint256 expectedShares = vault.previewWithdraw(amount_);

        address recipient = makeAddr("RECIPIENT");

        uint256 actualAmount = _withdraw(recipient, amount_, false);

        _assertAssetBalance(expectedShares, amount_, actualAmount, false, 5);
        _assertReceiptToken(amount_, 0, false, false);
        _assertDepositAssetBalance(DEPOSITOR, 0);
        _assertDepositAssetBalance(recipient, amount_, 5);
    }

    // given the maximum yield has been claimed
    //  [X] a depositor can withdraw the full deposit

    function test_givenMaxYieldClaimed()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        // Simulate yield being accrued to the vault
        asset.mint(address(vault), 10e18);

        // Determine the maximum yield that can be claimed
        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);

        // Claim the yield
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, ADMIN, maxYield);

        // Withdraw the full deposit
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: DEPOSITOR,
                amount: previousDepositorDepositActualAmount,
                isWrapped: false
            })
        );

        // Operator shares
        (uint256 operatorSharesAfter, ) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        assertApproxEqAbs(operatorSharesAfter, 0, 2, "Operator shares mismatch");

        // Vault balance
        assertApproxEqAbs(vault.balanceOf(address(depositManager)), 0, 2, "Vault balance mismatch");

        // Asset liabilities
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            0,
            "Asset liabilities mismatch"
        );

        _assertReceiptToken(previousDepositorDepositActualAmount, 0, false, false);
        _assertDepositAssetBalance(DEPOSITOR, previousDepositorDepositActualAmount);
    }

    function test_givenMaxYieldClaimed_fuzz(
        uint256 depositAmount_,
        uint256 yieldAmount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(type(uint256).max)
        givenDepositorHasApprovedSpendingReceiptToken(type(uint256).max)
    {
        depositAmount_ = bound(depositAmount_, 1e18, 100e18);
        yieldAmount_ = bound(yieldAmount_, 1e18, 200e18);

        uint256 balanceBefore = asset.balanceOf(DEPOSITOR);

        // Mint, deposit
        asset.mint(DEPOSITOR, depositAmount_);
        _deposit(depositAmount_, false);

        // Simulate yield being accrued to the vault
        asset.mint(address(vault), yieldAmount_);

        // Determine the maximum yield that can be claimed
        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);

        // Claim the yield
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, ADMIN, maxYield);

        // Withdraw the full deposit
        _withdraw(DEPOSITOR, previousDepositorDepositActualAmount, false);

        // Operator shares
        (uint256 operatorSharesAfter, ) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        assertApproxEqAbs(operatorSharesAfter, 0, 5, "Operator shares mismatch");

        // Vault balance
        assertApproxEqAbs(vault.balanceOf(address(depositManager)), 0, 5, "Vault balance mismatch");

        // Asset liabilities
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            0,
            "Asset liabilities mismatch"
        );

        _assertReceiptToken(previousDepositorDepositActualAmount, 0, false, false);
        _assertDepositAssetBalance(
            DEPOSITOR,
            balanceBefore + previousDepositorDepositActualAmount,
            5
        );
    }

    // [X] the wrapped receipt token is not burned
    // [X] the receipt token is burned
    // [X] the asset liabilities are decreased by the withdrawn amount
    // [X] the asset is withdrawn from the vault and sent to the depositor
    // [X] the operator shares are decreased by the withdrawn amount

    function test_withdraw()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        uint256 expectedShares = vault.previewWithdraw(previousDepositorDepositActualAmount);

        uint256 actualAmount = _withdraw(previousDepositorDepositActualAmount, false);

        _assertAssetBalance(
            expectedShares,
            previousDepositorDepositActualAmount,
            actualAmount,
            false,
            1
        );
        _assertReceiptToken(previousDepositorDepositActualAmount, 0, false, false);
        _assertDepositAssetBalance(DEPOSITOR, previousDepositorDepositActualAmount, 1);

        // As the full amount is being withdrawn, double-check that liabilities are 0
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            0,
            "Liabilities should be 0"
        );
    }

    // given the asset deposit cap has been exceeded
    //  [X] it allows for withdrawals to be made

    function test_givenAssetDepositCapIsExceeded()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
        givenAssetDepositCapIsSet(0)
    {
        uint256 expectedShares = vault.previewWithdraw(previousDepositorDepositActualAmount);

        uint256 actualAmount = _withdraw(previousDepositorDepositActualAmount, false);

        _assertAssetBalance(
            expectedShares,
            previousDepositorDepositActualAmount,
            actualAmount,
            false,
            1
        );
        _assertReceiptToken(previousDepositorDepositActualAmount, 0, false, false);
        _assertDepositAssetBalance(DEPOSITOR, previousDepositorDepositActualAmount, 1);

        // As the full amount is being withdrawn, double-check that liabilities are 0
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            0,
            "Liabilities should be 0"
        );
    }
}
