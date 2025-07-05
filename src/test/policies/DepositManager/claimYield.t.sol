// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";

contract DepositManagerClaimYieldTest is DepositManagerTest {
    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        _expectRevertNotEnabled();

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, ADMIN, 1);
    }

    // given the caller is not the deposit operator
    //  [X] it reverts

    function test_givenCallerIsNotDepositOperator_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != DEPOSIT_OPERATOR);

        _expectRevertNotDepositOperator();

        vm.prank(caller_);
        depositManager.claimYield(iAsset, ADMIN, 1);
    }

    // given the deposit asset is not configured
    //  [X] it reverts

    function test_givenDepositAssetIsNotConfigured_reverts() public givenIsEnabled {
        _expectRevertNotConfiguredAsset();

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, ADMIN, 1);
    }

    // when the claimed yield reduces the deposited assets below the liabilities
    //  [X] it reverts

    function test_insolvent_reverts(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        // Simulate yield being accrued to the vault
        asset.mint(address(vault), 10e18);
        (, uint256 operatorSharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        uint256 operatorLiabilities = depositManager.getOperatorLiabilities(
            iAsset,
            DEPOSIT_OPERATOR
        );

        // Determine an amount that will result in the shares being less than the liabilities
        amount_ = bound(
            amount_,
            operatorSharesInAssets - operatorLiabilities + 1,
            operatorSharesInAssets
        );

        _expectRevertInsolvent(operatorLiabilities);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, ADMIN, amount_);
    }

    // given the asset period is disabled
    //  [X] the asset is transferred to the recipient

    function test_claimYield_givenAssetPeriodIsDisabled(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenAssetPeriodIsDisabled
    {
        // Simulate yield being accrued to the vault
        asset.mint(address(vault), 10e18);
        (uint256 operatorShares, uint256 operatorSharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        uint256 operatorLiabilities = depositManager.getOperatorLiabilities(
            iAsset,
            DEPOSIT_OPERATOR
        );

        // Determine an amount that will result in the vault still being solvent
        amount_ = bound(amount_, 1000, operatorSharesInAssets - operatorLiabilities - 1);
        uint256 expectedShares = vault.previewWithdraw(amount_);

        address recipient = makeAddr("recipient");

        // Claim the yield
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, recipient, amount_);

        // Operator shares
        (uint256 operatorSharesAfter, ) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        assertApproxEqAbs(
            operatorSharesAfter,
            operatorShares - expectedShares,
            1,
            "Operator shares mismatch"
        );

        // Vault balance
        assertApproxEqAbs(
            vault.balanceOf(address(depositManager)),
            operatorShares - expectedShares,
            1,
            "Vault balance mismatch"
        );

        // Asset liabilities
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            operatorLiabilities,
            "Asset liabilities mismatch"
        );

        _assertReceiptToken(0, 0, false, false); // Unaffected
        _assertDepositAssetBalance(DEPOSITOR, 0);
        _assertDepositAssetBalance(recipient, amount_);
    }

    // given the vault address is the zero address
    //  [X] it reverts

    function test_claimYield_givenVaultAddressIsZeroAddress()
        public
        givenIsEnabled
        givenAssetIsAddedWithZeroAddress
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        _expectRevertInsolvent(MINT_AMOUNT);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, ADMIN, 1);
    }

    // [X] the asset is transferred to the recipient
    // [X] the operator shares are decreased by the claimed yield
    // [X] the asset liabilities are not decreased
    // [X] the receipt token supply is not decreased

    function test_claimYield(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        // Simulate yield being accrued to the vault
        asset.mint(address(vault), 10e18);
        (uint256 operatorShares, uint256 operatorSharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        uint256 operatorLiabilities = depositManager.getOperatorLiabilities(
            iAsset,
            DEPOSIT_OPERATOR
        );

        // Determine an amount that will result in the vault still being solvent
        amount_ = bound(amount_, 1000, operatorSharesInAssets - operatorLiabilities - 1);
        uint256 expectedShares = vault.previewWithdraw(amount_);

        address recipient = makeAddr("recipient");

        // Claim the yield
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, recipient, amount_);

        // Operator shares
        (uint256 operatorSharesAfter, ) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        assertApproxEqAbs(
            operatorSharesAfter,
            operatorShares - expectedShares,
            1,
            "Operator shares mismatch"
        );

        // Vault balance
        assertApproxEqAbs(
            vault.balanceOf(address(depositManager)),
            operatorShares - expectedShares,
            1,
            "Vault balance mismatch"
        );

        // Asset liabilities
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            operatorLiabilities,
            "Asset liabilities mismatch"
        );

        _assertReceiptToken(0, 0, false, false); // Unaffected
        _assertDepositAssetBalance(DEPOSITOR, 0);
        _assertDepositAssetBalance(recipient, amount_);
    }
}
