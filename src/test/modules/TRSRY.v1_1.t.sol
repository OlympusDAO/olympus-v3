// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";
//import {MockPolicy} from "test/mocks/KernelTestMocks.sol";

import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {TRSRYv1_1, CategoryGroup, toCategoryGroup, fromCategoryGroup} from "src/modules/TRSRY/TRSRY.v1.sol";

import "src/Kernel.sol";

// Tests for OlympusTreasury v1.1
// TODO
// Asset Information
// [ ] getAssets - returns all assets configured in the treasury
//      [ ] zero assets
//      [ ] one asset
//      [ ] many assets
// [ ] getAssetsByCategory - returns all assets in a given category
//      [ ] zero assets
//      [ ] one asset
//      [ ] many assets
//      [ ] reverts if category does not exist
// [ ] getAssetBalance - returns the balance of a given asset
//      [ ] zero balance in treasury and externally
//      [ ] zero balance in treasury and non-zero balance externally
//      [ ] non-zero balance in treasury and zero balance externally
//      [ ] non-zero balance in treasury and externally
//      [ ] current variant returns real-time data
//      [ ] last variant returns cached data
//      [ ] reverts if asset is not configured on treasury
// [ ] storeBalance - caches the balance of a given asset
//      [ ] zero balance in treasury and externally
//      [ ] zero balance in treasury and non-zero balance externally
//      [ ] non-zero balance in treasury and zero balance externally
//      [ ] non-zero balance in treasury and externally
//      [ ] reverts if asset is not configured on treasury
// [ ] getCategoryBalance - returns the balance of a given category
//      [ ] zero assets
//      [ ] one asset
//            [ ] zero balance in treasury and externally
//            [ ] zero balance in treasury and non-zero balance externally
//            [ ] non-zero balance in treasury and zero balance externally
//            [ ] non-zero balance in treasury and externally
//      [ ] many assets
//            [ ] zero balance in treasury and externally for some assets
//            [ ] zero balance in treasury and externally for all assets
//            [ ] zero balance in treasury and non-zero balance externally for some assets
//            [ ] zero balance in treasury and non-zero balance externally for all assets
//            [ ] non-zero balance in treasury and zero balance externally for some assets
//            [ ] non-zero balance in treasury and zero balance externally for all assets
//            [ ] non-zero balance in treasury and externally for some assets
//            [ ] non-zero balance in treasury and externally for all assets
//      [ ] reverts if category does not exist
//
// Data Management
// [ ] addAsset - adds an asset configuration to the treasury
//      [ ] reverts if asset is already configured
//      [ ] asset data stored correctly
//      [ ] zero locations
//      [ ] one location
//      [ ] many locations
// [ ] addAssetLocation - adds a location to an asset configuration
//      [ ] reverts if asset is not configured
//      [ ] reverts if location is already configured
//      [ ] location data stored correctly
//      [ ] zero locations prior
//      [ ] one location prior
//      [ ] many locations prior
// [ ] removeAssetLocation - removes a location from an asset configuration
//      [ ] reverts if asset is not configured
//      [ ] reverts if location is not configured
//      [ ] location data removed correctly
//      [ ] zero locations after
//      [ ] one location after
//      [ ] many locations after
// [X] addCategoryGroup - adds an asset category group to the treasury
//      [X] reverts if category group is already configured
//      [X] category group data stored correctly
// [ ] addCategory - adds an asset category to the treasury
//      [ ] reverts if category is already configured
//      [ ] category data stored correctly
//      [ ] zero categories in group prior
//      [ ] one category in group prior
//      [ ] many categories in group prior
// [ ] categorize - categorize an asset into a category within a category group
//      [ ] reverts if category is not configured
//      [ ] reverts if asset is not configured
//      [ ] category data stored correctly
//      [ ] zero assets in category prior
//      [ ] one asset in category prior
//      [ ] many assets in category prior

contract TRSRYv1_1Test is Test {
    using ModuleTestFixtureGenerator for OlympusTreasury;

    address public godmode;

    Kernel internal kernel;
    OlympusTreasury public TRSRY;

    MockERC20 public reserve;

    function setUp() public {
        // Kernel and Module creation
        kernel = new Kernel();
        TRSRY = new OlympusTreasury(kernel);

        // Create token
        reserve = new MockERC20("Reserve", "RSRV", 18);

        // Create godmode
        godmode = TRSRY.generateGodmodeFixture(type(OlympusTreasury).name);

        // Initialize module and godmode
        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.ActivatePolicy, godmode);

        // Mint tokens to TRSRY
        reserve.mint(address(TRSRY), 200_000_000e18);
    }

    function testCorrectness_addCategoryGroupRevertsIfAlreadyConfigured() public {
        // Try to push 'liquidity-preference' category group which already exists
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_CategoryGroupExists(bytes32)",
            toCategoryGroup("liquidity-preference")
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("liquidity-preference"));
    }

    function testCorrectness_addCategoryGroupAddsGroup(bytes32 groupName_) public {
        vm.prank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup(groupName_));

        // Check that the category group was added
        CategoryGroup addedGroup = TRSRY.categoryGroups(3);
        assertEq(fromCategoryGroup(addedGroup), groupName_);
    }
}
