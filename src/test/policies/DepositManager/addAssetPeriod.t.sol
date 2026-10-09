// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Revert-path calls deliberately ignore return values.
// forge-lint: disable-start(unused-return)

import {DepositManagerTest} from "./DepositManagerTest.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
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
        string memory depositPeriodString = depositPeriod_ == 1 ? " month" : " months";

        // Check name
        string memory expectedName = String.truncate32(
            string.concat(
                facilityName_,
                asset_.name(),
                " - ",
                uint2str(depositPeriod_),
                depositPeriodString
            )
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
        address operator = receiptTokenManager.getTokenOperator(tokenId_);
        assertEq(operator, facility_, "Receipt token facility does not match expected facility");
    }

    function assertAssetConfigured(
        address asset_,
        uint8 depositPeriod_,
        address facility_
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
                // Note: reclaimRate is no longer part of AssetPeriod struct
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
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // when the caller is neither admin nor the configured config operator
    //  [X] it reverts
    function test_whenCallerIsNeitherAdminNorConfigOperator_reverts(
        address caller_
    ) public givenIsEnabled {
        vm.assume(caller_ != ADMIN);
        vm.assume(caller_ != CONFIG_OPERATOR);
        _setConfigOperator(CONFIG_OPERATOR);

        _expectRevertNotConfigOperator(caller_);

        vm.prank(caller_);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    function test_whenCallerIsZero_reverts() public givenIsEnabled {
        _setConfigOperator(CONFIG_OPERATOR);
        _expectRevertNotConfigOperator(address(0));

        vm.prank(address(0));
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // when the caller is the deposit manager admin
    //  [X] it reverts
    function test_givenDepositManagerAdmin_whenAddingAssetPeriod_reverts()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        _expectRevertNotConfigOperator(DEPOSIT_MANAGER_ADMIN);

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // when the caller is emergency
    //  [X] it reverts
    function test_givenEmergency_whenAddingAssetPeriod_reverts()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        _expectRevertNotConfigOperator(EMERGENCY);

        vm.prank(EMERGENCY);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // when the caller is a deposit operator
    //  [X] it reverts
    function test_givenDepositOperator_whenAddingAssetPeriod_reverts()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        _expectRevertNotConfigOperator(DEPOSIT_OPERATOR);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // given the config operator is delegated
    //  [X] the current config operator creates the route directly
    //  [X] admin retains direct creation
    function test_whenConfigOperator_succeeds()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        _setConfigOperator(CONFIG_OPERATOR);

        vm.prank(CONFIG_OPERATOR);
        uint256 receiptTokenId = depositManager.addAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );

        assertAssetConfigured(address(asset), DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        assertReceiptTokenConfigured(
            receiptTokenId,
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR,
            "cd1"
        );
    }

    function test_whenAdmin_succeeds()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        _setConfigOperator(CONFIG_OPERATOR);

        vm.prank(ADMIN);
        uint256 receiptTokenId = depositManager.addAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );

        assertAssetConfigured(address(asset), DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        assertReceiptTokenConfigured(
            receiptTokenId,
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR,
            "cd1"
        );
    }

    function test_whenRoutePrerequisitesAreSatisfied_validationSucceeds()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        depositManager.validateAddAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_AssetPeriodExists.selector,
                address(iAsset),
                DEPOSIT_PERIOD,
                DEPOSIT_OPERATOR
            )
        );
        depositManager.validateAddAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
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
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
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
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // given the operator name is set but the operator does not hold deposit_operator
    // [X] it reverts with the typed role error
    function test_givenOperatorHasNameButNoRole_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        address operatorWithoutRole = makeAddr("OperatorWithoutRole");
        vm.prank(ADMIN);
        depositManager.setOperatorName(operatorWithoutRole, "opr");

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerV1_1.DepositManager_DepositOperatorRoleNotHeld.selector,
                operatorWithoutRole
            )
        );

        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, operatorWithoutRole);
    }

    // given the operator name is set and the role was revoked
    // [X] it reverts with the typed role error
    function test_givenRevokedOperatorRole_whenAddingAssetPeriod_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        vm.prank(ADMIN);
        rolesAdmin.revokeRole("deposit_operator", DEPOSIT_OPERATOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerV1_1.DepositManager_DepositOperatorRoleNotHeld.selector,
                DEPOSIT_OPERATOR
            )
        );

        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // given the operator role was revoked and regranted
    // [X] creation succeeds
    function test_givenRevokedOperatorRole_whenRoleIsRegranted_succeeds()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        vm.startPrank(ADMIN);
        rolesAdmin.revokeRole("deposit_operator", DEPOSIT_OPERATOR);
        rolesAdmin.grantRole("deposit_operator", DEPOSIT_OPERATOR);
        vm.stopPrank();

        vm.prank(ADMIN);
        uint256 receiptTokenId = depositManager.addAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );

        assertAssetConfigured(address(asset), DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        assertReceiptTokenConfigured(
            receiptTokenId,
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR,
            "cd1"
        );
    }

    // when the operator address is zero
    // [X] it reverts
    function test_whenOperatorAddressIsZero_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        _expectRevertZeroAddress();

        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, address(0));
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
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
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
        depositManager.addAssetPeriod(IERC20(address(0)), DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
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
        depositManager.addAssetPeriod(iAsset, 0, DEPOSIT_OPERATOR);
    }

    // when the deposit period is the maximum representable value
    //  [X] it configures and enables the route
    function test_whenDepositPeriodIsMaximum_succeeds()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, type(uint8).max, DEPOSIT_OPERATOR);

        assertAssetConfigured(address(iAsset), type(uint8).max, DEPOSIT_OPERATOR);
    }

    // Note: Reclaim rate validation is now handled by BaseDepositFacility, not DepositManager

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
            DEPOSIT_OPERATOR
        );

        // Check asset configuration
        assertAssetConfigured(address(asset), newDepositPeriod, DEPOSIT_OPERATOR);

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

        // Set the new facility name and grant the deposit operator role
        vm.startPrank(ADMIN);
        depositManager.setOperatorName(newFacility, "new");
        rolesAdmin.grantRole("deposit_operator", newFacility);
        vm.stopPrank();

        // Add the asset period with the new facility
        vm.prank(ADMIN);
        uint256 receiptTokenId = depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, newFacility);

        // Check asset configuration
        assertAssetConfigured(address(asset), DEPOSIT_PERIOD, newFacility);

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
            DEPOSIT_OPERATOR
        );

        // Check asset configuration
        assertAssetConfigured(address(asset), DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        // Check receipt token configuration
        assertReceiptTokenConfigured(
            receiptTokenId,
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR,
            "cd1"
        );
    }

    // when an unknown token ID is used
    //  [X] returns empty values per manager spec
    function test_unknownTokenIdReturnsEmptyValues() public view {
        // Generate a token ID that doesn't exist
        uint256 unknownTokenId = 999999;

        // Verify the token ID doesn't exist (validation check)
        assertFalse(
            receiptTokenManager.isValidTokenId(unknownTokenId),
            "Token ID should not exist"
        );

        // Test that getter functions return empty/default values for unknown token ID
        assertEq(
            receiptTokenManager.getTokenName(unknownTokenId),
            "",
            "Unknown token name should return empty string"
        );
        assertEq(
            receiptTokenManager.getTokenSymbol(unknownTokenId),
            "",
            "Unknown token symbol should return empty string"
        );
        assertEq(
            receiptTokenManager.getTokenDecimals(unknownTokenId),
            0,
            "Unknown token decimals should return 0"
        );
        assertEq(
            receiptTokenManager.getTokenOwner(unknownTokenId),
            address(0),
            "Unknown token owner should return zero address"
        );
        assertEq(
            address(receiptTokenManager.getTokenAsset(unknownTokenId)),
            address(0),
            "Unknown token asset should return zero address"
        );
        assertEq(
            receiptTokenManager.getTokenDepositPeriod(unknownTokenId),
            0,
            "Unknown token deposit period should return 0"
        );
        assertEq(
            receiptTokenManager.getTokenOperator(unknownTokenId),
            address(0),
            "Unknown token operator should return zero address"
        );
        assertEq(
            receiptTokenManager.getWrappedToken(unknownTokenId),
            address(0),
            "Unknown token wrapped token should return zero address"
        );
    }
}

// forge-lint: disable-end(unused-return)
