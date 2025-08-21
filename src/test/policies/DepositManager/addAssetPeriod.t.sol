// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {uint2str} from "src/libraries/Uint2Str.sol";
import {String} from "src/libraries/String.sol";

contract DepositManagerAddAssetPeriodTest is DepositManagerTest {
    // ========== ASSERTIONS ========== //

    function assertReceiptTokenConfigured(
        uint256 tokenId_,
        IERC20 asset_,
        uint8 depositPeriod_,
        address facility_,
        string memory facilityName_
    ) internal view {
        // Check name
        string memory expectedName = String.truncate32(
            string.concat(facilityName_, asset_.name(), " - ", uint2str(depositPeriod_), " months")
        );
        assertEq(
            receiptTokenManager.getTokenName(tokenId_),
            expectedName,
            "Receipt token name does not match expected format"
        );

        // Check symbol
        string memory expectedSymbol = String.truncate32(
            string.concat(facilityName_, asset_.symbol(), "-", uint2str(depositPeriod_), "m")
        );
        assertEq(
            receiptTokenManager.getTokenSymbol(tokenId_),
            expectedSymbol,
            "Receipt token symbol does not match expected format"
        );

        // Check decimals
        assertEq(
            receiptTokenManager.getTokenDecimals(tokenId_),
            asset_.decimals(),
            "Receipt token decimals do not match asset decimals"
        );

        // Check owner
        assertEq(
            receiptTokenManager.getTokenOwner(tokenId_),
            address(depositManager),
            "Receipt token owner is not the deposit manager"
        );

        // Check asset
        IERC20 asset = receiptTokenManager.getTokenAsset(tokenId_);
        assertEq(
            address(asset),
            address(asset_),
            "Receipt token asset does not match expected asset"
        );

        // Check deposit period
        uint8 depositPeriod = receiptTokenManager.getTokenDepositPeriod(tokenId_);
        assertEq(
            depositPeriod,
            depositPeriod_,
            "Receipt token deposit period does not match expected period"
        );

        // Check facility
        address facility = receiptTokenManager.getTokenOperator(tokenId_);
        assertEq(facility, facility_, "Receipt token facility does not match expected facility");
    }

    function assertAssetConfigured(
        address asset_,
        uint8 depositPeriod_,
        address facility_,
        uint256 reclaimRate_
    ) internal view {
        // Check if asset is configured
        IDepositManager.AssetPeriodStatus memory status = depositManager.isAssetPeriod(
            IERC20(asset_),
            depositPeriod_,
            facility_
        );
        assertTrue(
            status.isConfigured,
            "isAssetPeriod: asset is not configured as a deposit asset"
        );
        assertTrue(status.isEnabled, "isAssetPeriod: asset is not enabled as a deposit asset");

        // Check asset period using the receipt token ID
        IDepositManager.AssetPeriod memory depositConfigurationFromReceiptTokenId = depositManager
            .getAssetPeriod(
                depositManager.getReceiptTokenId(IERC20(asset_), depositPeriod_, facility_)
            );
        assertEq(
            depositConfigurationFromReceiptTokenId.asset,
            asset_,
            "getAssetPeriod from token id: asset mismatch"
        );
        assertEq(
            depositConfigurationFromReceiptTokenId.depositPeriod,
            depositPeriod_,
            "getAssetPeriod from token id: deposit period mismatch"
        );
        assertEq(
            depositConfigurationFromReceiptTokenId.operator,
            facility_,
            "getAssetPeriod from token id: facility mismatch"
        );

        // Check asset period using the asset and deposit period
        IDepositManager.AssetPeriod memory depositConfigurationFromAssetAndPeriod = depositManager
            .getAssetPeriod(IERC20(asset_), depositPeriod_, facility_);
        assertEq(
            depositConfigurationFromAssetAndPeriod.asset,
            asset_,
            "getAssetPeriod: asset mismatch"
        );
        assertEq(
            depositConfigurationFromAssetAndPeriod.depositPeriod,
            depositPeriod_,
            "getAssetPeriod: deposit period mismatch"
        );
        assertEq(
            depositConfigurationFromAssetAndPeriod.operator,
            facility_,
            "getAssetPeriod: facility mismatch"
        );

        // Check all deposit assets
        IDepositManager.AssetPeriod[] memory depositAssets = depositManager.getAssetPeriods();
        bool found = false;
        for (uint256 i; i < depositAssets.length; ++i) {
            if (
                address(depositAssets[i].asset) == asset_ &&
                depositAssets[i].depositPeriod == depositPeriod_ &&
                depositAssets[i].operator == facility_
            ) {
                found = true;

                assertEq(depositAssets[i].isEnabled, true, "getAssetPeriods: isEnabled mismatch");
                assertEq(
                    depositAssets[i].depositPeriod,
                    depositPeriod_,
                    "getAssetPeriods: deposit period mismatch"
                );
                assertEq(
                    depositAssets[i].operator,
                    facility_,
                    "getAssetPeriods: facility mismatch"
                );
                assertEq(
                    depositAssets[i].reclaimRate,
                    reclaimRate_,
                    "getAssetPeriods: reclaim rate mismatch"
                );
                assertEq(depositAssets[i].asset, asset_, "getAssetPeriods: asset mismatch");
                break;
            }
        }
        assertTrue(found, "getAssetPeriods: asset not found in deposit assets");
    }

    // ========== TESTS ========== //

    // given the policy is disabled
    //  [X] it reverts
    function test_givenPolicyIsDisabled_reverts() public {
        _expectRevertNotEnabled();

        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR, RECLAIM_RATE);
    }

    // when the caller is not the manager or admin
    //  [X] it reverts
    function test_whenCallerIsNotManagerOrAdmin_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN && caller_ != MANAGER);

        _expectRevertNotManagerOrAdmin();

        vm.prank(caller_);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR, RECLAIM_RATE);
    }

    // given the asset vault has not been configured
    //  [X] it reverts

    function test_givenAssetVaultHasNotBeenConfigured_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
    {
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_NotConfigured.selector));

        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR, RECLAIM_RATE);
    }

    // given the facility name has not been set
    // [X] it reverts
    function test_givenFacilityNameIsNotSet_reverts() public givenIsEnabled givenAssetIsAdded {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_OperatorNameNotSet.selector,
                DEPOSIT_OPERATOR
            )
        );

        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR, RECLAIM_RATE);
    }

    // given the asset is already configured with the same deposit period
    //  [X] it reverts
    function test_givenAssetIsAlreadyConfiguredWithSameDepositPeriod_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_AssetPeriodExists.selector,
                address(iAsset),
                DEPOSIT_PERIOD,
                DEPOSIT_OPERATOR
            )
        );

        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR, RECLAIM_RATE);
    }

    // when the asset address is the zero address
    //  [X] it reverts
    function test_whenAssetAddressIsZero_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
    {
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_NotConfigured.selector));

        vm.prank(ADMIN);
        depositManager.addAssetPeriod(
            IERC20(address(0)),
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR,
            RECLAIM_RATE
        );
    }

    // when the deposit period is 0
    //  [X] it reverts
    function test_whenDepositPeriodIsZero_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_OutOfBounds.selector)
        );

        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, 0, DEPOSIT_OPERATOR, RECLAIM_RATE);
    }

    // when the reclaim rate is greater than 100%
    //  [X] it reverts
    function test_whenReclaimRateIsGreaterThan100Percent_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_OutOfBounds.selector)
        );

        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR, 100e2 + 1);
    }

    // given the asset is already configured with a different deposit period
    //  [X] the asset period is recorded with the derived receipt token ID
    //  [X] the asset period has the reclaim rate set
    //  [X] the deposit reclaim rate is set
    //  [X] the receipt token has the name set
    //  [X] the receipt token has the symbol set
    //  [X] the receipt token has the decimals set
    //  [X] the receipt token has the owner set
    //  [X] the receipt token has the asset set
    //  [X] the receipt token has the deposit period set
    //  [X] the receipt token has the facility set
    //  [X] the returned receipt token ID matches
    //  [X] the asset period is returned for the receipt token ID
    //  [X] the asset and deposit period is recognised as a deposit asset
    function test_givenAssetIsAlreadyConfiguredWithDifferentDepositPeriod()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        uint8 newDepositPeriod = DEPOSIT_PERIOD + 1;

        vm.prank(ADMIN);
        uint256 receiptTokenId = depositManager.addAssetPeriod(
            iAsset,
            newDepositPeriod,
            DEPOSIT_OPERATOR,
            RECLAIM_RATE
        );

        // Check asset configuration
        assertAssetConfigured(address(asset), newDepositPeriod, DEPOSIT_OPERATOR, RECLAIM_RATE);

        // Check receipt token configuration
        assertReceiptTokenConfigured(
            receiptTokenId,
            iAsset,
            newDepositPeriod,
            DEPOSIT_OPERATOR,
            "cd1"
        );
    }

    // given the asset is already configured with a different facility
    //  [X] the asset period is recorded with the derived receipt token ID
    //  [X] the asset period has the reclaim rate set
    //  [X] the deposit reclaim rate is set
    //  [X] the receipt token has the name set
    //  [X] the receipt token has the symbol set
    //  [X] the receipt token has the decimals set
    //  [X] the receipt token has the owner set
    //  [X] the receipt token has the asset set
    //  [X] the receipt token has the deposit period set
    //  [X] the receipt token has the facility set
    //  [X] the returned receipt token ID matches
    //  [X] the asset period is returned for the receipt token ID
    //  [X] the asset and deposit period is recognised as a deposit asset
    function test_givenAssetIsAlreadyConfiguredWithDifferentFacility()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        address newFacility = makeAddr("NewFacility");

        // Set the new facility name
        vm.prank(ADMIN);
        depositManager.setOperatorName(newFacility, "new");

        // Add the asset period with the new facility
        vm.prank(ADMIN);
        uint256 receiptTokenId = depositManager.addAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD,
            newFacility,
            RECLAIM_RATE
        );

        // Check asset configuration
        assertAssetConfigured(address(asset), DEPOSIT_PERIOD, newFacility, RECLAIM_RATE);

        // Check receipt token configuration
        assertReceiptTokenConfigured(receiptTokenId, iAsset, DEPOSIT_PERIOD, newFacility, "new");
    }

    // [X] the asset period is recorded with the derived receipt token ID
    // [X] the asset period has the reclaim rate set
    // [X] the deposit reclaim rate is set
    // [X] the receipt token has the name set
    // [X] the receipt token has the symbol set
    // [X] the receipt token has the decimals set
    // [X] the receipt token has the owner set
    // [X] the receipt token has the asset set
    // [X] the receipt token has the deposit period set
    // [X] the receipt token has the facility set
    // [X] the returned receipt token ID matches
    // [X] the asset period is returned for the receipt token ID
    // [X] the asset and deposit period is recognised as a deposit asset
    function test_configuresAsset()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        vm.prank(ADMIN);
        uint256 receiptTokenId = depositManager.addAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR,
            RECLAIM_RATE
        );

        // Check asset configuration
        assertAssetConfigured(address(asset), DEPOSIT_PERIOD, DEPOSIT_OPERATOR, RECLAIM_RATE);

        // Check receipt token configuration
        assertReceiptTokenConfigured(
            receiptTokenId,
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR,
            "cd1"
        );
    }
}
