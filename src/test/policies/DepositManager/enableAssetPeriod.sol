// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

contract DepositManagerEnableAssetPeriodTest is DepositManagerTest {
    // ========== EVENTS ========== //
    event AssetPeriodEnabled(
        uint256 indexed receiptTokenId,
        address indexed asset,
        uint8 depositPeriod
    );

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        _expectRevertNotEnabled();

        vm.prank(ADMIN);
        depositManager.enableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // when the caller is not the manager or admin
    //  [X] it reverts

    function test_givenCallerIsNotManagerOrAdmin_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN && caller_ != MANAGER);

        _expectRevertNotManagerOrAdmin();

        vm.prank(caller_);
        depositManager.enableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // given there is no asset period
    //  [X] it reverts

    function test_givenThereIsNoAssetPeriod_reverts() public givenIsEnabled {
        _expectRevertInvalidConfiguration(iAsset, DEPOSIT_PERIOD);

        vm.prank(ADMIN);
        depositManager.enableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // given the asset period is already enabled
    //  [X] it reverts

    function test_givenAssetPeriodIsAlreadyEnabled_reverts()
        public
        givenIsEnabled
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        _expectRevertConfigurationEnabled(iAsset, DEPOSIT_PERIOD);

        vm.prank(ADMIN);
        depositManager.enableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    // [X] the asset period is enabled
    // [X] it emits an event

    function test_setsAssetPeriodToEnabled()
        public
        givenIsEnabled
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        // Disable the asset period
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        vm.expectEmit(true, true, true, true);
        emit AssetPeriodEnabled(
            depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR),
            address(asset),
            DEPOSIT_PERIOD
        );

        vm.prank(ADMIN);
        depositManager.enableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        // Assert the asset period is enabled
        IDepositManager.AssetPeriod memory configuration = depositManager.getAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        assertEq(configuration.isEnabled, true, "AssetPeriod: isEnabled mismatch");

        IDepositManager.AssetPeriodStatus memory status = depositManager.isAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        assertEq(status.isConfigured, true, "isAssetPeriod: isConfigured mismatch");
        assertEq(status.isEnabled, true, "isAssetPeriod: isEnabled mismatch");
    }
}
