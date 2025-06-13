// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/IDepositManager.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {uint2str} from "src/libraries/Uint2str.sol";
import {String} from "src/libraries/String.sol";

contract DepositManagerAddDepositConfigurationTest is DepositManagerTest {
    // ========== ASSERTIONS ========== //

    function assertReceiptTokenConfigured(
        uint256 tokenId_,
        IERC20 asset_,
        uint8 depositPeriod_
    ) internal view {
        // Check name
        string memory expectedName = String.truncate32(
            string.concat(asset_.name(), " Receipt - ", uint2str(depositPeriod_), " months")
        );
        assertEq(
            depositManager.getReceiptTokenName(tokenId_),
            expectedName,
            "Receipt token name does not match expected format"
        );

        // Check symbol
        string memory expectedSymbol = String.truncate32(
            string.concat("r", asset_.symbol(), "-", uint2str(depositPeriod_), "m")
        );
        assertEq(
            depositManager.getReceiptTokenSymbol(tokenId_),
            expectedSymbol,
            "Receipt token symbol does not match expected format"
        );

        // Check decimals
        assertEq(
            depositManager.getReceiptTokenDecimals(tokenId_),
            asset_.decimals(),
            "Receipt token decimals do not match asset decimals"
        );

        // Check owner
        assertEq(
            depositManager.getReceiptTokenOwner(tokenId_),
            address(depositManager),
            "Receipt token owner is not the deposit manager"
        );

        // Check asset
        IERC20 asset = depositManager.getReceiptTokenAsset(tokenId_);
        assertEq(
            address(asset),
            address(asset_),
            "Receipt token asset does not match expected asset"
        );

        // Check deposit period
        uint8 depositPeriod = depositManager.getReceiptTokenDepositPeriod(tokenId_);
        assertEq(
            depositPeriod,
            depositPeriod_,
            "Receipt token deposit period does not match expected period"
        );
    }

    function assertAssetConfigured(
        address asset_,
        uint8 depositPeriod_,
        uint256 reclaimRate_
    ) internal view {
        // Check if asset is configured
        assertTrue(
            depositManager.isConfiguredDeposit(IERC20(asset_), depositPeriod_),
            "isConfiguredDeposit: asset is not configured as a deposit asset"
        );

        // Check deposit configuration using the receipt token ID
        IDepositManager.DepositConfiguration
            memory depositConfigurationFromReceiptTokenId = depositManager.getDepositConfiguration(
                depositManager.getReceiptTokenId(IERC20(asset_), depositPeriod_)
            );
        assertEq(
            address(depositConfigurationFromReceiptTokenId.asset),
            asset_,
            "getDepositConfiguration from token id: asset mismatch"
        );
        assertEq(
            depositConfigurationFromReceiptTokenId.depositPeriod,
            depositPeriod_,
            "getDepositConfiguration from token id: deposit period mismatch"
        );

        // Check deposit configuration using the asset and deposit period
        IDepositManager.DepositConfiguration
            memory depositConfigurationFromAssetAndPeriod = depositManager.getDepositConfiguration(
                IERC20(asset_),
                depositPeriod_
            );
        assertEq(
            address(depositConfigurationFromAssetAndPeriod.asset),
            asset_,
            "getDepositConfiguration: asset mismatch"
        );
        assertEq(
            depositConfigurationFromAssetAndPeriod.depositPeriod,
            depositPeriod_,
            "getDepositConfiguration: deposit period mismatch"
        );

        // Check all deposit assets
        IDepositManager.DepositConfiguration[] memory depositAssets = depositManager
            .getDepositConfigurations();
        bool found = false;
        for (uint256 i; i < depositAssets.length; ++i) {
            if (
                address(depositAssets[i].asset) == asset_ &&
                depositAssets[i].depositPeriod == depositPeriod_
            ) {
                found = true;

                assertEq(
                    depositAssets[i].isEnabled,
                    true,
                    "getDepositConfigurations: isEnabled mismatch"
                );
                assertEq(
                    depositAssets[i].depositPeriod,
                    depositPeriod_,
                    "getDepositConfigurations: deposit period mismatch"
                );
                assertEq(
                    depositAssets[i].reclaimRate,
                    reclaimRate_,
                    "getDepositConfigurations: reclaim rate mismatch"
                );
                assertEq(
                    address(depositAssets[i].asset),
                    asset_,
                    "getDepositConfigurations: asset mismatch"
                );
                break;
            }
        }
        assertTrue(found, "getDepositConfigurations: asset not found in deposit assets");
    }

    // ========== TESTS ========== //

    // given the policy is disabled
    //  [X] it reverts
    function test_givenPolicyIsDisabled_reverts() public {
        _expectRevertNotEnabled();

        vm.prank(ADMIN);
        depositManager.addDepositConfiguration(iAsset, DEPOSIT_PERIOD, RECLAIM_RATE);
    }

    // when the caller is not the manager or admin
    //  [X] it reverts
    function test_whenCallerIsNotManagerOrAdmin_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_OPERATOR);

        _expectRevertNotManagerOrAdmin();

        vm.prank(caller_);
        depositManager.addDepositConfiguration(iAsset, DEPOSIT_PERIOD, RECLAIM_RATE);
    }

    // given the asset vault has not been configured
    //  [X] it reverts

    function test_givenAssetVaultHasNotBeenConfigured_reverts() public givenIsEnabled {
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_NotConfigured.selector));

        vm.prank(ADMIN);
        depositManager.addDepositConfiguration(iAsset, DEPOSIT_PERIOD, RECLAIM_RATE);
    }

    // given the asset is already configured with the same deposit period
    //  [X] it reverts
    function test_givenAssetIsAlreadyConfiguredWithSameDepositPeriod_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_ConfigurationExists.selector,
                address(iAsset),
                DEPOSIT_PERIOD
            )
        );

        vm.prank(ADMIN);
        depositManager.addDepositConfiguration(iAsset, DEPOSIT_PERIOD, RECLAIM_RATE);
    }

    // when the asset address is the zero address
    //  [X] it reverts
    function test_whenAssetAddressIsZero_reverts() public givenIsEnabled {
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_NotConfigured.selector));

        vm.prank(ADMIN);
        depositManager.addDepositConfiguration(IERC20(address(0)), DEPOSIT_PERIOD, RECLAIM_RATE);
    }

    // when the deposit period is 0
    //  [X] it reverts
    function test_whenDepositPeriodIsZero_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
    {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_OutOfBounds.selector)
        );

        vm.prank(ADMIN);
        depositManager.addDepositConfiguration(iAsset, 0, RECLAIM_RATE);
    }

    // when the reclaim rate is greater than 100%
    //  [X] it reverts
    function test_whenReclaimRateIsGreaterThan100Percent_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
    {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_OutOfBounds.selector)
        );

        vm.prank(ADMIN);
        depositManager.addDepositConfiguration(iAsset, DEPOSIT_PERIOD, 100e2 + 1);
    }

    // given the asset is already configured with a different deposit period
    //  [X] the deposit configuration is recorded with the derived receipt token ID
    //  [X] the deposit configuration has the reclaim rate set
    //  [X] the deposit reclaim rate is set
    //  [X] the receipt token has the name set
    //  [X] the receipt token has the symbol set
    //  [X] the receipt token has the decimals set
    //  [X] the receipt token has the owner set
    //  [X] the receipt token has the asset set
    //  [X] the receipt token has the deposit period set
    //  [X] the returned receipt token ID matches
    //  [X] the deposit configuration is returned for the receipt token ID
    //  [X] the asset and deposit period is recognised as a deposit asset
    function test_givenAssetIsAlreadyConfiguredWithDifferentDepositPeriod()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
    {
        uint8 newDepositPeriod = DEPOSIT_PERIOD + 1;

        vm.prank(ADMIN);
        uint256 receiptTokenId = depositManager.addDepositConfiguration(
            iAsset,
            newDepositPeriod,
            RECLAIM_RATE
        );

        // Check asset configuration
        assertAssetConfigured(address(asset), newDepositPeriod, RECLAIM_RATE);

        // Check receipt token configuration
        assertReceiptTokenConfigured(receiptTokenId, iAsset, newDepositPeriod);
    }

    // [X] the deposit configuration is recorded with the derived receipt token ID
    // [X] the deposit configuration has the reclaim rate set
    // [X] the deposit reclaim rate is set
    // [X] the receipt token has the name set
    // [X] the receipt token has the symbol set
    // [X] the receipt token has the decimals set
    // [X] the receipt token has the owner set
    // [X] the receipt token has the asset set
    // [X] the receipt token has the deposit period set
    // [X] the returned receipt token ID matches
    // [X] the deposit configuration is returned for the receipt token ID
    // [X] the asset and deposit period is recognised as a deposit asset
    function test_configuresAsset() public givenIsEnabled givenAssetVaultIsConfigured {
        vm.prank(ADMIN);
        uint256 receiptTokenId = depositManager.addDepositConfiguration(
            iAsset,
            DEPOSIT_PERIOD,
            RECLAIM_RATE
        );

        // Check asset configuration
        assertAssetConfigured(address(asset), DEPOSIT_PERIOD, RECLAIM_RATE);

        // Check receipt token configuration
        assertReceiptTokenConfigured(receiptTokenId, iAsset, DEPOSIT_PERIOD);
    }
}
