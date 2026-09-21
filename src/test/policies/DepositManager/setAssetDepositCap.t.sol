// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

contract DepositManagerSetAssetDepositCapTest is DepositManagerTest {
    event AssetDepositCapSet(address indexed asset, uint256 depositCap);

    // given the contract is not enabled
    //  [X] it reverts

    function test_givenContractIsNotEnabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Set the deposit cap
        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, 100e18);
    }

    // given the caller is neither admin nor config operator
    //  [X] it reverts

    function test_givenCallerIsNotAdminOrConfigOperator_reverts(
        address caller_
    ) public givenIsEnabled givenFacilityNameIsSetDefault {
        vm.assume(caller_ != ADMIN && caller_ != CONFIG_OPERATOR);
        _setConfigOperator(CONFIG_OPERATOR);

        _expectRevertNotConfigOperator(caller_);

        // Set the deposit cap
        vm.prank(caller_);
        depositManager.setAssetDepositCap(iAsset, 100e18);
    }

    function test_givenConfigOperator_setsDepositCap()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        _setConfigOperator(CONFIG_OPERATOR);

        vm.prank(CONFIG_OPERATOR);
        depositManager.setAssetDepositCap(iAsset, 100e18);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            100e18,
            "config operator should set deposit cap"
        );
    }

    // given the asset is not configured
    //  [X] it reverts

    function test_givenAssetIsNotConfigured_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
    {
        // Expect revert
        _expectRevertNotConfiguredAsset();

        // Set the deposit cap
        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, 100e18);
    }

    // when deposit cap is less than minimum deposit
    //  [X] it reverts

    function test_whenDepositCapIsLessThanMinimumDeposit_reverts(
        uint256 minimumDeposit_,
        uint256 depositCap_
    ) public givenIsEnabled givenFacilityNameIsSetDefault {
        minimumDeposit_ = bound(minimumDeposit_, 1, type(uint128).max);
        depositCap_ = bound(depositCap_, 0, minimumDeposit_ - 1);

        // Add asset with minimum deposit
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, type(uint256).max, minimumDeposit_);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_MinimumDepositExceedsDepositCap.selector,
                address(iAsset),
                minimumDeposit_,
                depositCap_
            )
        );

        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, depositCap_);
    }

    // [X] it sets the deposit cap
    // [X] it emits an event

    function test_setDepositCap(
        uint256 depositCap_
    ) public givenIsEnabled givenFacilityNameIsSetDefault givenAssetIsAdded {
        // Expect emit
        vm.expectEmit(true, true, true, true);
        emit AssetDepositCapSet(address(iAsset), depositCap_);

        // Set the deposit cap
        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, depositCap_);

        // Assert
        IAssetManager.AssetConfiguration memory assetConfiguration = depositManager
            .getAssetConfiguration(iAsset);
        assertEq(assetConfiguration.depositCap, depositCap_, "Deposit cap mismatch");
    }

    // when the deposit cap equals the minimum deposit
    //  [X] it succeeds
    function test_depositCapEqualsMinimumDeposit()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        uint256 minimumDeposit = 100e18;

        // First set a minimum deposit
        vm.prank(ADMIN);
        depositManager.setAssetMinimumDeposit(iAsset, minimumDeposit);

        // Setting deposit cap equal to minimum deposit should succeed
        vm.expectEmit(true, true, true, true);
        emit AssetDepositCapSet(address(iAsset), minimumDeposit);

        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, minimumDeposit);

        // Assert both values are equal
        IAssetManager.AssetConfiguration memory config = depositManager.getAssetConfiguration(
            iAsset
        );
        assertEq(config.depositCap, minimumDeposit, "Deposit cap should equal minimum deposit");
        assertEq(config.minimumDeposit, minimumDeposit, "Minimum deposit unchanged");
    }

    // when minimum deposit is 0 and deposit cap is 0
    //  [X] it succeeds (both disabled)
    function test_bothZeroValues()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        // Set minimum deposit to 0
        vm.prank(ADMIN);
        depositManager.setAssetMinimumDeposit(iAsset, 0);

        // Set deposit cap to 0 (disables deposits)
        vm.expectEmit(true, true, true, true);
        emit AssetDepositCapSet(address(iAsset), 0);

        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, 0);

        // Assert both are zero
        IAssetManager.AssetConfiguration memory config = depositManager.getAssetConfiguration(
            iAsset
        );
        assertEq(config.depositCap, 0, "Deposit cap should be 0");
        assertEq(config.minimumDeposit, 0, "Minimum deposit should be 0");
    }

    function test_givenOutstandingPrincipal_whenCapIsLoweredBelowUtilization()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
    {
        vm.prank(DEPOSIT_OPERATOR);
        (, uint256 creditedAmount) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: MINT_AMOUNT,
                shouldWrap: false
            })
        );

        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, 0);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            0,
            "cap should be lowered below utilization"
        );
        assertEq(
            _assetDepositCapUtilization(iAsset),
            creditedAmount,
            "cap change should preserve utilization"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
