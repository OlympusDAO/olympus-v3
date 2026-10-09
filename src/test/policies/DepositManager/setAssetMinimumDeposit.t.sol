// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";

contract DepositManagerSetAssetMinimumDepositTest is DepositManagerTest {
    // ========== EVENTS ========== //

    event AssetMinimumDepositSet(address indexed asset, uint256 minimumDeposit);

    // ========== TESTS ========== //

    // when the caller is neither admin nor config operator
    //  [X] it reverts

    function test_whenCallerIsNotAdminOrConfigOperator_reverts(
        address caller_
    ) public givenIsEnabled givenAssetIsAdded {
        vm.assume(caller_ != ADMIN && caller_ != CONFIG_OPERATOR);
        _setConfigOperator(CONFIG_OPERATOR);

        _expectRevertNotConfigOperator(caller_);

        vm.prank(caller_);
        depositManager.setAssetMinimumDeposit(iAsset, 1e18);
    }

    function test_givenConfigOperator_setsMinimumDeposit() public givenIsEnabled givenAssetIsAdded {
        _setConfigOperator(CONFIG_OPERATOR);

        vm.prank(CONFIG_OPERATOR);
        depositManager.setAssetMinimumDeposit(iAsset, 1e18);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).minimumDeposit,
            1e18,
            "config operator should set minimum deposit"
        );
    }

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        vm.prank(ADMIN);
        depositManager.setAssetMinimumDeposit(iAsset, 1e18);
    }

    // given the asset is not configured
    //  [X] it reverts

    function test_givenAssetIsNotConfigured_reverts() public givenIsEnabled {
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_NotConfigured.selector));

        vm.prank(ADMIN);
        depositManager.setAssetMinimumDeposit(iAsset, 1e18);
    }

    // when minimum deposit exceeds deposit cap
    //  [X] it reverts

    function test_whenMinimumDepositExceedsDepositCap_reverts(
        uint256 depositCap_,
        uint256 minimumDeposit_
    ) public givenIsEnabled {
        depositCap_ = bound(depositCap_, 0, type(uint128).max - 1);
        minimumDeposit_ = bound(minimumDeposit_, depositCap_ + 1, type(uint128).max);

        // Add asset first
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, depositCap_, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_MinimumDepositExceedsDepositCap.selector,
                address(iAsset),
                minimumDeposit_,
                depositCap_
            )
        );

        vm.prank(ADMIN);
        depositManager.setAssetMinimumDeposit(iAsset, minimumDeposit_);
    }

    // [X] it sets the minimum deposit for the asset
    // [X] it emits an event

    function test_setsAssetMinimumDeposit(
        uint256 minimumDeposit_
    ) public givenIsEnabled givenAssetIsAdded {
        // Bound to ensure it doesn't exceed the default deposit cap (type(uint256).max)
        minimumDeposit_ = bound(minimumDeposit_, 0, type(uint256).max - 1);

        vm.expectEmit(true, true, true, true);
        emit AssetMinimumDepositSet(address(iAsset), minimumDeposit_);

        vm.prank(ADMIN);
        depositManager.setAssetMinimumDeposit(iAsset, minimumDeposit_);

        IAssetManager.AssetConfiguration memory configuration = depositManager
            .getAssetConfiguration(iAsset);
        assertEq(configuration.minimumDeposit, minimumDeposit_, "minimumDeposit mismatch");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
