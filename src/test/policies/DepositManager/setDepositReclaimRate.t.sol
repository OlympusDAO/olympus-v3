// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";

import {IDepositManager} from "src/policies/interfaces/IDepositManager.sol";

contract DepositManagersetAssetPeriodReclaimRateTest is DepositManagerTest {
    // ========== EVENTS ========== //

    event AssetPeriodReclaimRateSet(address indexed asset, uint8 depositPeriod, uint16 reclaimRate);

    // ========== TESTS ========== //

    // given the policy is disabled
    //  [X] it reverts

    function test_givenPolicyIsDisabled_reverts() public {
        _expectRevertNotEnabled();

        vm.prank(ADMIN);
        depositManager.setAssetPeriodReclaimRate(iAsset, DEPOSIT_PERIOD, RECLAIM_RATE);
    }

    // when the caller is not the manager or admin
    //  [X] it reverts

    function test_whenCallerIsNotManagerOrAdmin_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN && caller_ != MANAGER);

        _expectRevertNotManagerOrAdmin();

        vm.prank(caller_);
        depositManager.setAssetPeriodReclaimRate(iAsset, DEPOSIT_PERIOD, RECLAIM_RATE);
    }

    // given the asset vault is not configured
    //  [X] it reverts

    function test_givenAssetVaultIsNotConfigured_reverts() public givenIsEnabled {
        _expectRevertInvalidConfiguration(iAsset, DEPOSIT_PERIOD);

        vm.prank(ADMIN);
        depositManager.setAssetPeriodReclaimRate(iAsset, DEPOSIT_PERIOD, RECLAIM_RATE);
    }

    // given the asset period does not exist
    //  [X] it reverts

    function test_givenAssetPeriodDoesNotExist_reverts() public givenIsEnabled givenAssetIsAdded {
        _expectRevertInvalidConfiguration(iAsset, DEPOSIT_PERIOD);

        vm.prank(ADMIN);
        depositManager.setAssetPeriodReclaimRate(iAsset, DEPOSIT_PERIOD, RECLAIM_RATE);
    }

    // when the reclaim rate is greater than 100%
    //  [X] it reverts

    function test_whenReclaimRateIsGreaterThan100_reverts(
        uint16 reclaimRate_
    ) public givenIsEnabled givenAssetIsAdded givenAssetPeriodIsAdded {
        reclaimRate_ = uint16(bound(reclaimRate_, 100e2 + 1, type(uint16).max));

        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_OutOfBounds.selector)
        );

        vm.prank(ADMIN);
        depositManager.setAssetPeriodReclaimRate(iAsset, DEPOSIT_PERIOD, reclaimRate_);
    }

    // [X] it sets the reclaim rate for the deposit asset
    // [X] an event is emitted

    function test_setsReclaimRate(
        uint16 reclaimRate_
    ) public givenIsEnabled givenAssetIsAdded givenAssetPeriodIsAdded {
        reclaimRate_ = uint16(bound(reclaimRate_, 0, 100e2));

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AssetPeriodReclaimRateSet(address(iAsset), DEPOSIT_PERIOD, reclaimRate_);

        vm.prank(ADMIN);
        depositManager.setAssetPeriodReclaimRate(iAsset, DEPOSIT_PERIOD, reclaimRate_);

        assertEq(
            depositManager.getAssetPeriodReclaimRate(iAsset, DEPOSIT_PERIOD),
            reclaimRate_,
            "Reclaim rate mismatch"
        );
    }
}
