// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";

contract ConvertibleDepositFacilitySetAssetPeriodReclaimRateTest is ConvertibleDepositFacilityTest {
    // ========== EVENTS ========== //

    event AssetPeriodReclaimRateSet(address indexed asset, uint8 depositPeriod, uint16 reclaimRate);

    // ========== TESTS ========== //

    // given the policy is disabled
    //  [X] it reverts
    function test_givenPolicyIsDisabled_reverts() public {
        _expectRevertNotEnabled();

        vm.prank(admin);
        facility.setAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS, 90e2);
    }

    // when the caller is not the manager or admin
    //  [X] it reverts
    function test_whenCallerIsNotManagerOrAdmin_reverts(address caller_) public givenLocallyActive {
        vm.assume(caller_ != admin && caller_ != manager);

        _expectRevertNotAuthorized();

        vm.prank(caller_);
        facility.setAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS, 90e2);
    }

    // given the asset period does not exist
    //  [X] it reverts
    function test_givenAssetPeriodDoesNotExist_reverts() public givenLocallyActive {
        // Use an asset that doesn't exist in the facility
        IERC20 nonExistentAsset = IERC20(makeAddr("nonExistentAsset"));

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_InvalidAssetPeriod.selector,
                address(nonExistentAsset),
                PERIOD_MONTHS,
                address(facility)
            )
        );

        vm.prank(admin);
        facility.setAssetPeriodReclaimRate(nonExistentAsset, PERIOD_MONTHS, 90e2);
    }

    // when the reclaim rate is greater than 100%
    //  [X] it reverts
    function test_whenReclaimRateIsGreaterThan100_reverts(
        uint16 reclaimRate_
    ) public givenLocallyActive {
        reclaimRate_ = uint16(bound(reclaimRate_, 100e2 + 1, type(uint16).max));

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositFacility.DepositFacility_InvalidAddress.selector,
                address(0)
            )
        );

        vm.prank(admin);
        facility.setAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS, reclaimRate_);
    }

    // [X] it sets the reclaim rate for the deposit asset
    // [X] an event is emitted
    function test_setsReclaimRate(uint16 reclaimRate_) public givenLocallyActive {
        reclaimRate_ = uint16(bound(reclaimRate_, 0, 100e2));

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AssetPeriodReclaimRateSet(address(iReserveToken), PERIOD_MONTHS, reclaimRate_);

        vm.prank(admin);
        facility.setAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS, reclaimRate_);

        assertEq(
            facility.getAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS),
            reclaimRate_,
            "Reclaim rate mismatch"
        );
    }

    // Test with manager role
    function test_setsReclaimRate_manager(uint16 reclaimRate_) public givenLocallyActive {
        reclaimRate_ = uint16(bound(reclaimRate_, 0, 100e2));

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AssetPeriodReclaimRateSet(address(iReserveToken), PERIOD_MONTHS, reclaimRate_);

        vm.prank(manager);
        facility.setAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS, reclaimRate_);

        assertEq(
            facility.getAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS),
            reclaimRate_,
            "Reclaim rate mismatch"
        );
    }

    // Test setting to 0% and 100%
    function test_setsReclaimRate_boundary_zero() public givenLocallyActive {
        uint16 reclaimRate = 0;

        vm.expectEmit(true, true, true, true);
        emit AssetPeriodReclaimRateSet(address(iReserveToken), PERIOD_MONTHS, reclaimRate);

        vm.prank(admin);
        facility.setAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS, reclaimRate);

        assertEq(
            facility.getAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS),
            reclaimRate,
            "Reclaim rate mismatch"
        );
    }

    function test_setsReclaimRate_boundary_hundred() public givenLocallyActive {
        uint16 reclaimRate = 100e2;

        vm.expectEmit(true, true, true, true);
        emit AssetPeriodReclaimRateSet(address(iReserveToken), PERIOD_MONTHS, reclaimRate);

        vm.prank(admin);
        facility.setAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS, reclaimRate);

        assertEq(
            facility.getAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS),
            reclaimRate,
            "Reclaim rate mismatch"
        );
    }

    // Test updating an existing reclaim rate
    function test_updatesExistingReclaimRate() public givenLocallyActive {
        uint16 initialRate = 50e2;
        uint16 newRate = 80e2;

        // Set initial rate
        vm.prank(admin);
        facility.setAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS, initialRate);

        assertEq(
            facility.getAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS),
            initialRate,
            "Initial reclaim rate mismatch"
        );

        // Update rate
        vm.expectEmit(true, true, true, true);
        emit AssetPeriodReclaimRateSet(address(iReserveToken), PERIOD_MONTHS, newRate);

        vm.prank(admin);
        facility.setAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS, newRate);

        assertEq(
            facility.getAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS),
            newRate,
            "Updated reclaim rate mismatch"
        );
    }
}
