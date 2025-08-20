// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";

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

    // given the caller is not the admin or manager
    //  [X] it reverts

    function test_givenCallerIsNotAdminOrManager_reverts(
        address caller_
    ) public givenIsEnabled givenFacilityNameIsSetDefault {
        vm.assume(caller_ != ADMIN && caller_ != MANAGER);

        // Expect revert
        _expectRevertNotManagerOrAdmin();

        // Set the deposit cap
        vm.prank(caller_);
        depositManager.setAssetDepositCap(iAsset, 100e18);
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
        IAssetManager.AssetConfiguration memory config = depositManager.getAssetConfiguration(iAsset);
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
        IAssetManager.AssetConfiguration memory config = depositManager.getAssetConfiguration(iAsset);
        assertEq(config.depositCap, 0, "Deposit cap should be 0");
        assertEq(config.minimumDeposit, 0, "Minimum deposit should be 0");
    }
}
