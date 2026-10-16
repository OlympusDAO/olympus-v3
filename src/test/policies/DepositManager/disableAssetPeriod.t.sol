// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

contract DepositManagerDisableAssetPeriodTest is DepositManagerTest {
    // ========== EVENTS ========== //
    event AssetPeriodDisabled(
        uint256 indexed receiptTokenId,
        address indexed asset,
        address indexed facility,
        uint8 depositPeriod
    );

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        _expectRevertNotEnabled();

        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // when the caller is neither admin, config operator, nor emergency
    //  [X] it reverts

    function test_whenCallerIsUnauthorized_reverts(
        address caller_
    ) public givenIsEnabled givenFacilityNameIsSetDefault {
        vm.assume(caller_ != ADMIN && caller_ != CONFIG_OPERATOR && caller_ != EMERGENCY);
        _setConfigOperator(CONFIG_OPERATOR);

        _expectRevertNotConfigOperator(caller_);

        vm.prank(caller_);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    function test_givenConfigOperator_disablesAssetPeriod()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        _setConfigOperator(CONFIG_OPERATOR);

        vm.prank(CONFIG_OPERATOR);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        assertFalse(
            depositManager.isAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR).isEnabled,
            "config operator should disable asset period"
        );
    }

    function test_givenEmergency_disablesAssetPeriod()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        vm.prank(EMERGENCY);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        assertFalse(
            depositManager.isAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR).isEnabled,
            "emergency should disable asset period"
        );
    }

    // given there is no asset period
    //  [X] it reverts

    function test_givenThereIsNoAssetPeriod_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
    {
        _expectRevertInvalidConfiguration(iAsset, DEPOSIT_PERIOD);

        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // given the asset period is already disabled
    //  [X] it reverts

    function test_givenAssetPeriodIsAlreadyDisabled_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        // Disable the asset period
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        _expectRevertAssetPeriodDisabled(iAsset, DEPOSIT_PERIOD);

        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // [X] the asset period is disabled
    // [X] it emits an event

    function test_setsAssetPeriodToDisabled()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        vm.expectEmit(true, true, true, true);
        emit AssetPeriodDisabled(
            depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR),
            address(iAsset),
            DEPOSIT_OPERATOR,
            DEPOSIT_PERIOD
        );

        // Disable the asset period
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        // Assert the asset period is disabled
        IDepositManager.AssetPeriod memory configuration = depositManager.getAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        assertEq(configuration.isEnabled, false, "AssetPeriod: isEnabled mismatch");

        IDepositManager.AssetPeriodStatus memory status = depositManager.isAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        assertEq(status.isConfigured, true, "isAssetPeriod: isConfigured mismatch");
        assertEq(status.isEnabled, false, "isAssetPeriod: isEnabled mismatch");
    }
}
