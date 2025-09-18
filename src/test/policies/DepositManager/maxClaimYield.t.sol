// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";

contract DepositManagerMaxClaimYieldTest is DepositManagerTest {
    function _getExpectedMaxYield() internal view returns (uint256) {
        // This won't work for multiple operators, as the vault share balance would be for all of them. It's ok for this example, so as not to rely on the getOperatorAssets function.
        uint256 vaultShares = iVault.balanceOf(address(depositManager));
        uint256 vaultAssets = iVault.previewRedeem(vaultShares);
        uint256 vaultBorrowed = depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR);

        uint256 operatorLiabilities = depositManager.getOperatorLiabilities(
            iAsset,
            DEPOSIT_OPERATOR
        );
        return vaultAssets + vaultBorrowed - operatorLiabilities - 1;
    }

    uint256 internal _operatorLiabilitiesBefore;

    function _takeSnapshot() internal {
        _operatorLiabilitiesBefore = depositManager.getOperatorLiabilities(
            iAsset,
            DEPOSIT_OPERATOR
        );
    }

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it returns the maximum yield that can be claimed

    function test_givenContractIsDisabled()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenIsDisabled
    {
        // Simulate yield being accrued to the vault
        asset.mint(address(vault), 10e18);

        // Calculate the expected max yield
        uint256 expectedMaxYield = _getExpectedMaxYield();

        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);
        assertEq(maxYield, expectedMaxYield, "Max yield mismatch");
    }

    // given the asset vault is not configured
    //  [X] it returns zero

    function test_givenAssetVaultIsNotConfigured()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
    {
        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);
        assertEq(maxYield, 0, "Max yield mismatch");
    }

    // given the asset period is disabled
    //  [X] it returns the maximum yield that can be claimed

    function test_givenAssetPeriodIsDisabled()
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

        // Calculate the expected max yield
        uint256 expectedMaxYield = _getExpectedMaxYield();

        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);
        assertEq(maxYield, expectedMaxYield, "Max yield mismatch");
    }

    // given the asset vault is configured with the zero address
    //  [X] it returns zero

    function test_givenAssetIsAddedWithZeroAddress()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAddedWithZeroAddress
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);
        assertEq(maxYield, 0, "Max yield mismatch");
    }

    // given funds have been borrowed
    //  given the full amount has been borrowed
    //   [X] it returns no yield

    function test_givenBorrowedFullAmount()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(previousDepositorDepositActualAmount)
    {
        // Simulate yield being accrued to the vault
        asset.mint(address(vault), 10e18);

        _takeSnapshot();

        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);
        assertEq(maxYield, 0, "Max yield mismatch");

        (, uint256 operatorSharesInAssetsAfter) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        // Assert solvency
        // Assets + borrowed >= liabilities
        assertGe(
            operatorSharesInAssetsAfter +
                depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            _operatorLiabilitiesBefore,
            "insolvent"
        );
    }

    //  [X] it returns the yield that can be claimed for the remaining deposits
    //  [X] the maximum yield amount can be claimed

    function test_givenBorrowedPartialAmount()
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

        // Calculate the expected max yield
        uint256 expectedMaxYield = _getExpectedMaxYield();

        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);
        assertEq(maxYield, expectedMaxYield, "Max yield mismatch");

        // Claim the yield
        // This will revert if insolvent
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, ADMIN, maxYield);

        (, uint256 operatorSharesInAssetsAfter) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        // Assert solvency
        // Assets + borrowed >= liabilities
        assertGe(
            operatorSharesInAssetsAfter +
                depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            _operatorLiabilitiesBefore,
            "insolvent"
        );
    }

    // given there is no yield to claim
    //  [X] it returns zero

    function test_givenNoYieldToClaim()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);
        assertEq(maxYield, 0, "Max yield mismatch");
    }

    // [X] it returns the maximum yield that can be claimed
    // [X] the maximum yield amount can be claimed

    function test_maxClaimYield()
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

        // Calculate the expected max yield
        uint256 expectedMaxYield = _getExpectedMaxYield();

        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);
        assertEq(maxYield, expectedMaxYield, "Max yield mismatch");

        // Claim the yield
        // This will revert if insolvent
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, ADMIN, maxYield);

        (, uint256 operatorSharesInAssetsAfter) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        // Assert solvency
        // Assets + borrowed >= liabilities
        assertGe(
            operatorSharesInAssetsAfter +
                depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            _operatorLiabilitiesBefore,
            "insolvent"
        );
    }
}
