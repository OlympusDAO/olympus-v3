// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

contract DepositManagerDisableAssetPeriodTest is DepositManagerTest {
    // ========== EVENTS ========== //
    event AssetPeriodDisabled(
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
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD);
    }

    // when the caller is not the manager or admin
    //  [X] it reverts

    function test_givenCallerIsNotManagerOrAdmin_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN && caller_ != MANAGER);

        _expectRevertNotManagerOrAdmin();

        vm.prank(caller_);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD);
    }

    // given there is no asset period
    //  [X] it reverts

    function test_givenThereIsNoAssetPeriod_reverts() public givenIsEnabled {
        _expectRevertInvalidConfiguration(iAsset, DEPOSIT_PERIOD);

        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD);
    }

    // given the asset period is already disabled
    //  [X] it reverts

    function test_givenAssetPeriodIsAlreadyDisabled_reverts()
        public
        givenIsEnabled
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        // Disable the asset period
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD);

        _expectRevertAssetPeriodDisabled(iAsset, DEPOSIT_PERIOD);

        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD);
    }

    // [X] the asset period is disabled
    // [X] it emits an event

    function test_setsAssetPeriodToDisabled()
        public
        givenIsEnabled
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        vm.expectEmit(true, true, true, true);
        emit AssetPeriodDisabled(
            depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD),
            address(iAsset),
            DEPOSIT_PERIOD
        );

        // Disable the asset period
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD);

        // Assert the asset period is disabled
        IDepositManager.AssetPeriod memory configuration = depositManager.getAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD
        );
        assertEq(configuration.isEnabled, false, "AssetPeriod: isEnabled mismatch");

        IDepositManager.AssetPeriodStatus memory status = depositManager.isAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD
        );
        assertEq(status.isConfigured, true, "isAssetPeriod: isConfigured mismatch");
        assertEq(status.isEnabled, false, "isAssetPeriod: isEnabled mismatch");
    }
}
