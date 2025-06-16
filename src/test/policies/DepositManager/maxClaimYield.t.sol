// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";

contract DepositManagerMaxClaimYieldTest is DepositManagerTest {
    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it returns the maximum yield that can be claimed

    function test_givenContractIsDisabled()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenIsDisabled
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
        uint256 expectedMaxYield = operatorSharesInAssets - operatorLiabilities;

        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);
        assertEq(maxYield, expectedMaxYield, "Max yield mismatch");
    }

    // given the asset vault is not configured
    //  [X] it returns zero

    function test_givenAssetVaultIsNotConfigured() public givenIsEnabled {
        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);
        assertEq(maxYield, 0, "Max yield mismatch");
    }

    // given the deposit configuration is disabled
    //  [X] it returns the maximum yield that can be claimed

    function test_givenDepositConfigurationIsDisabled()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositConfigurationIsDisabled
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
        uint256 expectedMaxYield = operatorSharesInAssets - operatorLiabilities;

        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);
        assertEq(maxYield, expectedMaxYield, "Max yield mismatch");
    }

    // given the asset vault is configured with the zero address
    //  [X] it returns zero

    function test_givenAssetVaultIsConfiguredWithZeroAddress()
        public
        givenIsEnabled
        givenAssetVaultIsConfiguredWithZeroAddress
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);
        assertEq(maxYield, 0, "Max yield mismatch");
    }

    // given there is no yield to claim
    //  [ ] it returns zero

    function test_givenNoYieldToClaim() public givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
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
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
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
        uint256 expectedMaxYield = operatorSharesInAssets - operatorLiabilities;

        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);
        assertEq(maxYield, expectedMaxYield, "Max yield mismatch");

        // Claim the yield
        // This will revert if insolvent
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.claimYield(iAsset, ADMIN, expectedMaxYield);
    }
}
