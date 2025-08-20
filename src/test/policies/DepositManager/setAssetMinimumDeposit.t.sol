// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract DepositManagerSetAssetMinimumDepositTest is DepositManagerTest {
    // ========== EVENTS ========== //

    event AssetMinimumDepositSet(address indexed asset, uint256 minimumDeposit);

    // ========== TESTS ========== //

    // when the caller is not the manager or admin
    //  [X] it reverts

    function test_givenCallerIsNotManagerOrAdmin_reverts(
        address caller_
    ) public givenIsEnabled givenAssetIsAdded {
        vm.assume(caller_ != ADMIN && caller_ != MANAGER);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));

        vm.prank(caller_);
        depositManager.setAssetMinimumDeposit(iAsset, 1e18);
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
