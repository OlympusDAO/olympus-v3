// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";

contract DepositManagerClaimYieldTest is DepositManagerTest {
    function _getExpectedMaxYield() internal view returns (uint256) {
        // This won't work for multiple operators, as the vault share balance would be for all of them. It's ok for this example, so as not to rely on the getOperatorAssets function.
        uint256 vaultShares = iVault.balanceOf(address(depositManager));
        uint256 vaultAssets = iVault.previewRedeem(vaultShares);
        uint256 vaultBorrowed = depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR);

        uint256 operatorLiabilities = depositManager.getOperatorLiabilities(
            iAsset,
            DEPOSIT_OPERATOR
        );
        return vaultAssets + vaultBorrowed - operatorLiabilities;
    }

    uint256 internal _operatorSharesBefore;
    uint256 internal _operatorSharesInAssetsBefore;
    uint256 internal _operatorLiabilitiesBefore;

    function _takeSnapshot() internal {
        _operatorSharesBefore = iVault.balanceOf(address(depositManager));
        _operatorSharesInAssetsBefore = iVault.previewRedeem(_operatorSharesBefore);
        _operatorLiabilitiesBefore = depositManager.getOperatorLiabilities(
            iAsset,
            DEPOSIT_OPERATOR
        );
    }

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

    function test_givenCallerIsNotDepositOperator_reverts(
        address caller_
    ) public givenIsEnabled givenFacilityNameIsSetDefault {
        vm.assume(caller_ != DEPOSIT_OPERATOR);

        _expectRevertNotDepositOperator();

        vm.prank(caller_);
        depositManager.claimYield(iAsset, ADMIN, 1);
    }

    // given the deposit asset is not configured
    //  [X] it reverts

    function test_givenDepositAssetIsNotConfigured_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
    {
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
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        // Simulate yield being accrued to the vault
        asset.mint(address(vault), 10e18);

        // Determine an amount that will result in the shares being less than the liabilities
        amount_ = bound(amount_, _getExpectedMaxYield() + 1, previousDepositorDepositActualAmount);
        _expectRevertInsolvent();

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
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenAssetPeriodIsDisabled
    {
        // Simulate yield being accrued to the vault
        asset.mint(address(vault), 10e18);

        // Determine an amount that will result in the vault still being solvent
        amount_ = bound(amount_, 1000, _getExpectedMaxYield());
        uint256 operatorShares = iVault.balanceOf(address(depositManager));
        uint256 operatorLiabilities = depositManager.getOperatorLiabilities(
            iAsset,
            DEPOSIT_OPERATOR
        );
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

        _assertReceiptToken(0, 0, true, false); // Unaffected
        _assertDepositAssetBalance(DEPOSITOR, 0);
        _assertDepositAssetBalance(recipient, amount_, 5);
    }

    // given the vault address is the zero address
    //  [X] it reverts

    function test_claimYield_givenVaultAddressIsZeroAddress()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAddedWithZeroAddress
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        _expectRevertInsolvent();

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, ADMIN, 1);
    }

    // given funds have been borrowed
    //  [X] the asset is transferred to the recipient
    //  [X] the operator shares are decreased by the claimed yield
    //  [X] the asset liabilities are not decreased
    //  [X] the receipt token supply is not decreased

    function test_givenBorrowed_claimYield(
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
        // Simulate yield being accrued to the vault
        asset.mint(address(vault), 10e18);

        _takeSnapshot();

        // Determine an amount that will result in the vault still being solvent
        amount_ = bound(amount_, 1000, _getExpectedMaxYield());
        uint256 expectedShares = vault.previewWithdraw(amount_);

        address recipient = makeAddr("recipient");

        // Claim the yield
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, recipient, amount_);

        // Operator shares
        (uint256 operatorSharesAfter, uint256 operatorSharesInAssetsAfter) = depositManager
            .getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        assertApproxEqAbs(
            operatorSharesAfter,
            _operatorSharesBefore - expectedShares,
            1,
            "Operator shares mismatch"
        );

        // Assert solvency
        // Assets + borrowed >= liabilities
        assertGe(
            operatorSharesInAssetsAfter +
                depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            _operatorLiabilitiesBefore,
            "insolvent"
        );

        // Vault balance
        assertApproxEqAbs(
            vault.balanceOf(address(depositManager)),
            _operatorSharesBefore - expectedShares,
            1,
            "Vault balance mismatch"
        );

        // Asset liabilities
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            _operatorLiabilitiesBefore,
            "Asset liabilities mismatch"
        );

        _assertReceiptToken(0, 0, true, false); // Unaffected
        _assertDepositAssetBalance(DEPOSITOR, 0);
        _assertDepositAssetBalance(recipient, amount_, 5);
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
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        // Simulate yield being accrued to the vault
        asset.mint(address(vault), 10e18);

        _takeSnapshot();

        // Determine an amount that will result in the vault still being solvent
        amount_ = bound(amount_, 1000, _getExpectedMaxYield());
        uint256 expectedShares = vault.previewWithdraw(amount_);

        address recipient = makeAddr("recipient");

        // Claim the yield
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, recipient, amount_);

        // Operator shares
        (uint256 operatorSharesAfter, uint256 operatorSharesInAssetsAfter) = depositManager
            .getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        assertApproxEqAbs(
            operatorSharesAfter,
            _operatorSharesBefore - expectedShares,
            1,
            "Operator shares mismatch"
        );

        // Assert solvency
        // Assets + borrowed >= liabilities
        assertGe(
            operatorSharesInAssetsAfter +
                depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            _operatorLiabilitiesBefore,
            "insolvent"
        );

        // Vault balance
        assertApproxEqAbs(
            vault.balanceOf(address(depositManager)),
            _operatorSharesBefore - expectedShares,
            1,
            "Vault balance mismatch"
        );

        // Asset liabilities
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            _operatorLiabilitiesBefore,
            "Asset liabilities mismatch"
        );

        _assertReceiptToken(0, 0, true, false); // Unaffected
        _assertDepositAssetBalance(DEPOSITOR, 0);
        _assertDepositAssetBalance(recipient, amount_, 5);
    }

    function test_claimYield_fuzz(
        uint256 depositAmount_,
        uint256 yieldAmount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(type(uint256).max)
    {
        depositAmount_ = bound(depositAmount_, 1e18, 100e18);
        yieldAmount_ = bound(yieldAmount_, 1e18, 200e18);

        uint256 balanceBefore = asset.balanceOf(DEPOSITOR);

        // Mint, deposit
        asset.mint(DEPOSITOR, depositAmount_);
        _deposit(depositAmount_, false);

        // Simulate yield being accrued to the vault
        asset.mint(address(vault), yieldAmount_);

        _takeSnapshot();

        // Determine the maximum yield that can be claimed
        address recipient = makeAddr("recipient");
        uint256 maxYield = _getExpectedMaxYield();
        uint256 expectedShares = vault.previewWithdraw(maxYield);

        // Claim the yield
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, recipient, maxYield);

        // Operator shares
        (uint256 operatorSharesAfter, uint256 operatorSharesInAssetsAfter) = depositManager
            .getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        assertApproxEqAbs(
            operatorSharesAfter,
            _operatorSharesBefore - expectedShares,
            10,
            "Operator shares mismatch"
        );

        // Assert solvency
        // Assets + borrowed >= liabilities
        assertGe(
            operatorSharesInAssetsAfter +
                depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            _operatorLiabilitiesBefore,
            "insolvent"
        );

        // Vault balance
        assertApproxEqAbs(
            vault.balanceOf(address(depositManager)),
            _operatorSharesBefore - expectedShares,
            3,
            "Vault balance mismatch"
        );

        // Asset liabilities
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            _operatorLiabilitiesBefore,
            "Asset liabilities mismatch"
        );

        _assertReceiptToken(0, 0, true, false); // Unaffected
        _assertDepositAssetBalance(DEPOSITOR, balanceBefore);
        _assertDepositAssetBalance(recipient, maxYield, 5);
    }
}
