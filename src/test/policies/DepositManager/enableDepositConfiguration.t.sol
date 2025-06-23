// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

import {IDepositManager} from "src/policies/interfaces/IDepositManager.sol";

contract DepositManagerEnableDepositConfigurationTest is DepositManagerTest {
    // ========== EVENTS ========== //
    event DepositConfigurationEnabled(
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
        depositManager.enableDepositConfiguration(iAsset, DEPOSIT_PERIOD);
    }

    // when the caller is not the manager or admin
    //  [X] it reverts

    function test_givenCallerIsNotManagerOrAdmin_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN && caller_ != MANAGER);

        _expectRevertNotManagerOrAdmin();

        vm.prank(caller_);
        depositManager.enableDepositConfiguration(iAsset, DEPOSIT_PERIOD);
    }

    // given there is no deposit configuration
    //  [X] it reverts

    function test_givenThereIsNoDepositConfiguration_reverts() public givenIsEnabled {
        _expectRevertInvalidConfiguration(iAsset, DEPOSIT_PERIOD);

        vm.prank(ADMIN);
        depositManager.enableDepositConfiguration(iAsset, DEPOSIT_PERIOD);
    }

    // given the deposit configuration is already enabled
    //  [X] it reverts

    function test_givenDepositConfigurationIsAlreadyEnabled_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
    {
        _expectRevertConfigurationEnabled(iAsset, DEPOSIT_PERIOD);

        vm.prank(ADMIN);
        depositManager.enableDepositConfiguration(iAsset, DEPOSIT_PERIOD);
    }

    // [X] the deposit configuration is enabled
    // [X] it emits an event

    function test_setsDepositConfigurationToEnabled()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
    {
        // Disable the deposit configuration
        vm.prank(ADMIN);
        depositManager.disableDepositConfiguration(iAsset, DEPOSIT_PERIOD);

        vm.expectEmit(true, true, true, true);
        emit DepositConfigurationEnabled(
            depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD),
            address(asset),
            DEPOSIT_PERIOD
        );

        vm.prank(ADMIN);
        depositManager.enableDepositConfiguration(iAsset, DEPOSIT_PERIOD);

        // Assert the deposit configuration is enabled
        IDepositManager.DepositConfiguration memory configuration = depositManager
            .getDepositConfiguration(iAsset, DEPOSIT_PERIOD);
        assertEq(configuration.isEnabled, true, "DepositConfiguration: isEnabled mismatch");

        (bool isConfigured, bool isEnabled) = depositManager.isConfiguredDeposit(
            iAsset,
            DEPOSIT_PERIOD
        );
        assertEq(isConfigured, true, "isConfiguredDeposit: isConfigured mismatch");
        assertEq(isEnabled, true, "isConfiguredDeposit: isEnabled mismatch");
    }
}
