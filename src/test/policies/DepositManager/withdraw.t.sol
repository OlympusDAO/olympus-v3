// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";

contract DepositManagerWithdrawTest is DepositManagerTest {
    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        _expectRevertNotEnabled();

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.withdraw(iAsset, DEPOSIT_PERIOD, DEPOSITOR, DEPOSITOR, MINT_AMOUNT, false);
    }

    // given the caller does not have the deposit operator role
    //  [X] it reverts

    function test_givenCallerDoesNotHaveDepositOperatorRole_reverts(
        address caller_
    ) public givenIsEnabled {
        vm.assume(caller_ != DEPOSIT_OPERATOR);

        _expectRevertNotDepositOperator();

        vm.prank(caller_);
        depositManager.withdraw(iAsset, DEPOSIT_PERIOD, DEPOSITOR, DEPOSITOR, MINT_AMOUNT, false);
    }

    // given the deposit asset configuration does not exist
    //  [X] it reverts

    function test_givenDepositAssetConfigurationDoesNotExist_reverts() public givenIsEnabled {
        _expectRevertInvalidReceiptTokenId(iAsset, DEPOSIT_PERIOD);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.withdraw(iAsset, DEPOSIT_PERIOD, DEPOSITOR, DEPOSITOR, MINT_AMOUNT, false);
    }

    // given wrapped is true
    //  given the depositor has not approved the contract to spend the wrapped receipt token
    //   [X] it reverts

    function test_givenWrappedIsTrue_givenDepositorHasNotApprovedContractToSpendWrappedReceiptToken_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, true)
    {
        _expectRevertERC20CloneInsufficientAllowance();

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.withdraw(iAsset, DEPOSIT_PERIOD, DEPOSITOR, DEPOSITOR, MINT_AMOUNT, true);
    }

    //  given the depositor's wrapped receipt token balance is less than the amount to withdraw
    //   [X] it reverts

    function test_givenWrappedIsTrue_givenDepositorWrappedReceiptTokenBalanceIsInsufficient_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, true)
        givenDepositorHasApprovedSpendingWrappedReceiptToken(MINT_AMOUNT + 1)
    {
        _expectRevertERC20CloneInsufficientBalance();

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.withdraw(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSITOR,
            DEPOSITOR,
            MINT_AMOUNT + 1,
            true
        );
    }

    //  [X] the wrapped receipt token is burned
    //  [X] the receipt token is not burned

    function test_givenWrappedIsTrue()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, true)
        givenDepositorHasApprovedSpendingWrappedReceiptToken(MINT_AMOUNT)
    {
        uint256 expectedShares = vault.previewWithdraw(MINT_AMOUNT);

        uint256 shares = _withdraw(MINT_AMOUNT, true);

        _assertAssetBalance(expectedShares, MINT_AMOUNT, shares, false);
        _assertReceiptToken(0, MINT_AMOUNT, true, false);
        _assertDepositAssetBalance(DEPOSITOR, MINT_AMOUNT);
    }

    // given the depositor has not approved the contract to spend the receipt token
    //  [X] it reverts

    function test_givenDepositorHasNotApprovedContractToSpendReceiptToken_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        _expectRevertReceiptTokenInsufficientAllowance(0, MINT_AMOUNT);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.withdraw(iAsset, DEPOSIT_PERIOD, DEPOSITOR, DEPOSITOR, MINT_AMOUNT, false);
    }

    // given the depositor's receipt token balance is less than the amount to withdraw
    //  [X] it reverts

    function test_givenDepositorReceiptTokenBalanceIsInsufficient_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT + 1)
    {
        _expectRevertReceiptTokenInsufficientBalance(MINT_AMOUNT, MINT_AMOUNT + 1);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.withdraw(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSITOR,
            DEPOSITOR,
            MINT_AMOUNT + 1,
            false
        );
    }

    // given the asset configuration has the vault set to the zero address
    //  given there has been a deposit
    //   [X] the operator shares are correct
    //   [X] the asset liabilities are correct

    function test_givenAssetVaultIsConfiguredWithZeroAddress_givenRemainingDeposit(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenAssetVaultIsConfiguredWithZeroAddress
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        amount_ = bound(amount_, 1e18, MINT_AMOUNT / 2);

        vm.prank(DEPOSIT_OPERATOR);
        uint256 shares = depositManager.withdraw(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSITOR,
            DEPOSITOR,
            amount_,
            false
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

    function test_givenAssetVaultIsConfiguredWithZeroAddress()
        public
        givenIsEnabled
        givenAssetVaultIsConfiguredWithZeroAddress
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        vm.prank(DEPOSIT_OPERATOR);
        uint256 shares = depositManager.withdraw(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSITOR,
            DEPOSITOR,
            MINT_AMOUNT,
            false
        );

        _assertAssetBalance(MINT_AMOUNT, MINT_AMOUNT, shares, false);
        _assertReceiptToken(MINT_AMOUNT, 0, false, false);
        _assertDepositAssetBalance(DEPOSITOR, MINT_AMOUNT);
    }

    // given the deposit configuration is disabled
    //  [X] the asset is withdrawn from the vault and sent to the depositor

    function test_givenDepositConfigurationIsDisabled()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
        givenDepositConfigurationIsDisabled
    {
        uint256 expectedShares = vault.previewWithdraw(MINT_AMOUNT);

        uint256 shares = _withdraw(MINT_AMOUNT, false);

        _assertAssetBalance(expectedShares, MINT_AMOUNT, shares, false);
        _assertReceiptToken(MINT_AMOUNT, 0, false, false);
        _assertDepositAssetBalance(DEPOSITOR, MINT_AMOUNT);
    }

    // given there has been another deposit
    //  [X] the operator shares are correct
    //  [X] the asset liabilities are correct

    function test_givenRemainingDeposit(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        amount_ = bound(amount_, 1e18, MINT_AMOUNT / 2);
        uint256 expectedShares = vault.previewWithdraw(amount_);

        uint256 shares = _withdraw(amount_, false);

        _assertAssetBalance(expectedShares, amount_, shares, false);
        _assertReceiptToken(amount_, 0, false, false);
        _assertDepositAssetBalance(DEPOSITOR, amount_);
    }

    // when the recipient address is different to the depositor
    //  when the recipient address is the zero address
    //   [X] it reverts

    function test_givenRecipientAddressIsDifferentToDepositor_zeroAddress_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        _expectRevertZeroAddress();

        _withdraw(address(0), MINT_AMOUNT, false);
    }

    //  [X] the asset is transferred to the recipient

    function test_givenRecipientAddressIsDifferentToDepositor(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        amount_ = bound(amount_, 1e18, MINT_AMOUNT / 2);
        uint256 expectedShares = vault.previewWithdraw(amount_);

        address recipient = makeAddr("RECIPIENT");

        uint256 shares = _withdraw(recipient, amount_, false);

        _assertAssetBalance(expectedShares, amount_, shares, false);
        _assertReceiptToken(amount_, 0, false, false);
        _assertDepositAssetBalance(DEPOSITOR, 0);
        _assertDepositAssetBalance(recipient, amount_);
    }

    // [X] the wrapped receipt token is not burned
    // [X] the receipt token is burned
    // [X] the asset liabilities are decreased by the withdrawn amount
    // [X] the asset is withdrawn from the vault and sent to the depositor
    // [X] the operator shares are decreased by the withdrawn amount

    function test_withdraw()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        uint256 expectedShares = vault.previewWithdraw(MINT_AMOUNT);

        uint256 shares = _withdraw(MINT_AMOUNT, false);

        _assertAssetBalance(expectedShares, MINT_AMOUNT, shares, false);
        _assertReceiptToken(MINT_AMOUNT, 0, false, false);
        _assertDepositAssetBalance(DEPOSITOR, MINT_AMOUNT);
    }
}
