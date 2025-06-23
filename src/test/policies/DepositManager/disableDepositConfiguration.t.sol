// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

import {IDepositManager} from "src/policies/interfaces/IDepositManager.sol";

contract DepositManagerDisableDepositConfigurationTest is DepositManagerTest {
    // ========== EVENTS ========== //
    event DepositConfigurationDisabled(
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
        depositManager.disableDepositConfiguration(iAsset, DEPOSIT_PERIOD);
    }

    // when the caller is not the manager or admin
    //  [X] it reverts

    function test_givenCallerIsNotManagerOrAdmin_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN && caller_ != MANAGER);

        _expectRevertNotManagerOrAdmin();

        vm.prank(caller_);
        depositManager.disableDepositConfiguration(iAsset, DEPOSIT_PERIOD);
    }

    // given there is no deposit configuration
    //  [X] it reverts

    function test_givenThereIsNoDepositConfiguration_reverts() public givenIsEnabled {
        _expectRevertInvalidConfiguration(iAsset, DEPOSIT_PERIOD);

        vm.prank(ADMIN);
        depositManager.disableDepositConfiguration(iAsset, DEPOSIT_PERIOD);
    }

    // given the deposit configuration is already disabled
    //  [X] it reverts

    function test_givenDepositConfigurationIsAlreadyDisabled_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
    {
        // Disable the deposit configuration
        vm.prank(ADMIN);
        depositManager.disableDepositConfiguration(iAsset, DEPOSIT_PERIOD);

        _expectRevertConfigurationDisabled(iAsset, DEPOSIT_PERIOD);

        vm.prank(ADMIN);
        depositManager.disableDepositConfiguration(iAsset, DEPOSIT_PERIOD);
    }

    // [X] the deposit configuration is disabled
    // [X] it emits an event

    function test_setsDepositConfigurationToDisabled()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
    {
        vm.expectEmit(true, true, true, true);
        emit DepositConfigurationDisabled(
            depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD),
            address(iAsset),
            DEPOSIT_PERIOD
        );

        // Disable the deposit configuration
        vm.prank(ADMIN);
        depositManager.disableDepositConfiguration(iAsset, DEPOSIT_PERIOD);

        // Assert the deposit configuration is disabled
        IDepositManager.DepositConfiguration memory configuration = depositManager
            .getDepositConfiguration(iAsset, DEPOSIT_PERIOD);
        assertEq(configuration.isEnabled, false, "DepositConfiguration: isEnabled mismatch");

        (bool isConfigured, bool isEnabled) = depositManager.isConfiguredDeposit(
            iAsset,
            DEPOSIT_PERIOD
        );
        assertEq(isConfigured, true, "isConfiguredDeposit: isConfigured mismatch");
        assertEq(isEnabled, false, "isConfiguredDeposit: isEnabled mismatch");
    }
}
