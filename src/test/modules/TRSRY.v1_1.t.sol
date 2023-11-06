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
import {TRSRYv1_1, CategoryGroup, toCategoryGroup, fromCategoryGroup, toCategory, fromCategory} from "src/modules/TRSRY/TRSRY.v1.sol";

import "src/Kernel.sol";

// Tests for OlympusTreasury v1.1
// TODO
// Asset Information
// [X] getAssets - returns all assets configured in the treasury
//      [X] zero assets
//      [X] one asset
//      [X] many assets
// [X] getAssetsByCategory - returns all assets in a given category
//      [X] reverts if category does not exist
//      [X] zero assets
//      [X] one asset
//      [X] many assets
// [X] getAssetBalance - returns the balance of a given asset
//      [X] reverts if asset is not configured on treasury
//      [X] zero balance in treasury and externally
//      [X] zero balance in treasury and non-zero balance externally
//      [X] non-zero balance in treasury and zero balance externally
//      [X] non-zero balance in treasury and externally
//      [X] current variant returns real-time data
//      [X] last variant returns cached data
// [X] storeBalance - caches the balance of a given asset
//      [X] reverts if asset is not configured on treasury
//      [X] zero balance in treasury and externally
//      [X] zero balance in treasury and non-zero balance externally
//      [X] non-zero balance in treasury and zero balance externally
//      [X] non-zero balance in treasury and externally
// [X] getCategoryBalance - returns the balance of a given category
//      [X] reverts if category does not exist
//      [X] zero assets
//      [X] one asset
//            [X] zero balance in treasury and externally
//            [X] zero balance in treasury and non-zero balance externally
//            [X] non-zero balance in treasury and zero balance externally
//            [X] non-zero balance in treasury and externally
//      [X] many assets
//            [X] zero balance in treasury and externally for all assets
//            [X] zero balance in treasury and non-zero balance externally for some assets
//            [X] zero balance in treasury and non-zero balance externally for all assets
//            [X] non-zero balance in treasury and zero balance externally for some assets
//            [X] non-zero balance in treasury and zero balance externally for all assets
//            [X] non-zero balance in treasury and externally for some assets
//            [X] non-zero balance in treasury and externally for all assets
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
// [X] addCategory - adds an asset category to the treasury
//      [X] reverts if category group is not configured
//      [X] reverts if category is already configured
//      [X] category data stored correctly with zero categories in group prior
//      [X] category data stored correctly with one category in group prior
//      [X] category data stored correctly with many categories in group prior
// [X] categorize - categorize an asset into a category within a category group
//      [X] reverts if asset is not configured
//      [X] reverts if category is not configured
//      [X] category data stored correctly with zero assets in category prior
//      [X] category data stored correctly with one asset in category prior
//      [X] category data stored correctly with many assets in category prior

contract TRSRYv1_1Test is Test {
    using ModuleTestFixtureGenerator for OlympusTreasury;

    address public godmode;

    Kernel internal kernel;
    OlympusTreasury public TRSRY;

    MockERC20 public reserve;
    MockERC20 public weth;
    MockERC20 public tkn;

    function setUp() public {
        // Kernel and Module creation
        kernel = new Kernel();
        TRSRY = new OlympusTreasury(kernel);

        // Create token
        reserve = new MockERC20("Reserve", "RSRV", 18);
        weth = new MockERC20("WETH", "WETH", 18);
        tkn = new MockERC20("TKN", "TKN", 18);

        // Create godmode
        godmode = TRSRY.generateGodmodeFixture(type(OlympusTreasury).name);

        // Initialize module and godmode
        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.ActivatePolicy, godmode);

        // Mint tokens to TRSRY
        reserve.mint(address(TRSRY), 200_000_000e18);
    }

    // ========= getAssets ========= //

    function testCorrectness_getAssetsReturnsZeroAssets() public {
        // Assert that there are no assets
        assertEq(TRSRY.getAssets().length, 0);
    }

    function testCorrectness_getAssetsReturnsOneAsset() public {
        // Add asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), new address[](0));

        // Assert that there is one asset
        assertEq(TRSRY.getAssets().length, 1);
        assertEq(TRSRY.getAssets()[0], address(reserve));
    }

    function testCorrectness_getAssetsReturnsManyAssets() public {
        // Add assets
        vm.startPrank(godmode);
        TRSRY.addAsset(address(reserve), new address[](0));
        TRSRY.addAsset(address(weth), new address[](0));
        vm.stopPrank();

        // Assert that there are three assets
        assertEq(TRSRY.getAssets().length, 2);
        assertEq(TRSRY.getAssets()[0], address(reserve));
        assertEq(TRSRY.getAssets()[1], address(weth));
    }

    // ========= getAssetsByCategory ========= //

    function testCorrectness_getAssetsByCategoryRevertsIfCategoryDoesNotExist() public {
        // Try to get assets by category 'abcdef' which does not exist
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_InvalidParams(uint256,bytes)",
            0,
            abi.encode(toCategory("abcdef"))
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.getAssetsByCategory(toCategory("abcdef"));
    }

    function testCorrectness_getAssetsByCategoryReturnsZeroAssets() public {
        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));
        vm.stopPrank();

        // Assert that there are no assets in the category
        assertEq(TRSRY.getAssetsByCategory(toCategory("test")).length, 0);
    }

    function testCorrectness_getAssetsByCategoryReturnsOneAsset() public {
        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add asset
        TRSRY.addAsset(address(reserve), new address[](0));
        TRSRY.categorize(address(reserve), toCategory("test"));
        vm.stopPrank();

        // Assert that there is one asset in the category
        assertEq(TRSRY.getAssetsByCategory(toCategory("test")).length, 1);
        assertEq(TRSRY.getAssetsByCategory(toCategory("test"))[0], address(reserve));
    }

    function testCorrectness_getAssetsByCategoryReturnsManyAssets() public {
        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add assets
        TRSRY.addAsset(address(reserve), new address[](0));
        TRSRY.addAsset(address(weth), new address[](0));
        TRSRY.categorize(address(reserve), toCategory("test"));
        TRSRY.categorize(address(weth), toCategory("test"));
        vm.stopPrank();

        // Assert that there are two assets in the category
        assertEq(TRSRY.getAssetsByCategory(toCategory("test")).length, 2);
        assertEq(TRSRY.getAssetsByCategory(toCategory("test"))[0], address(reserve));
        assertEq(TRSRY.getAssetsByCategory(toCategory("test"))[1], address(weth));
    }

    // ========= getAssetBalance ========= //

    function testCorrectness_getAssetBalanceRevertsIfAssetDoesNotExist() public {
        // Try to get balance of zero address
        bytes memory err = abi.encodeWithSignature("TRSRY_AssetNotApproved(address)", address(0));
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.getAssetBalance(address(0), TRSRYv1_1.Variant.CURRENT);
    }

    function testCorrectness_getAssetBalanceZeroBalanceInTreasuryAndExternally() public {
        // Add asset
        vm.prank(godmode);
        TRSRY.addAsset(address(weth), new address[](0));

        // Assert that the balance is zero
        (uint256 balance, uint48 timestamp) = TRSRY.getAssetBalance(
            address(weth),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 0);
        assertEq(timestamp, block.timestamp);
    }

    function testCorrectness_getAssetBalanceZeroBalanceInTreasuryAndNonZeroBalanceExternally()
        public
    {
        address[] memory addr = new address[](1);
        addr[0] = address(this);

        weth.mint(address(this), 1_000e18);

        // Add asset
        vm.prank(godmode);
        TRSRY.addAsset(address(weth), addr);

        // Assert that the balance is zero
        (uint256 balance, uint48 timestamp) = TRSRY.getAssetBalance(
            address(weth),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 1_000e18);
        assertEq(timestamp, block.timestamp);
    }

    function testCorrectness_getAssetBalanceNonZeroBalanceInTreasuryAndZeroBalanceExternally()
        public
    {
        weth.mint(address(TRSRY), 1_000e18);

        // Add asset
        vm.prank(godmode);
        TRSRY.addAsset(address(weth), new address[](0));

        // Assert that the balance is zero
        (uint256 balance, uint48 timestamp) = TRSRY.getAssetBalance(
            address(weth),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 1_000e18);
        assertEq(timestamp, block.timestamp);
    }

    function testCorrectness_getAssetBalanceNonZeroBalanceInTreasuryAndExternally() public {
        weth.mint(address(TRSRY), 1_000e18);
        weth.mint(address(this), 1_000e18);

        address[] memory addr = new address[](1);
        addr[0] = address(this);

        // Add asset
        vm.prank(godmode);
        TRSRY.addAsset(address(weth), addr);

        // Assert that the balance is zero
        (uint256 balance, uint48 timestamp) = TRSRY.getAssetBalance(
            address(weth),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 2_000e18);
        assertEq(timestamp, block.timestamp);
    }

    function testCorrectness_getAssetBalanceCurrentIsCurrent() public {
        weth.mint(address(TRSRY), 1_000e18);
        weth.mint(address(this), 1_000e18);

        address[] memory addr = new address[](1);
        addr[0] = address(this);

        // Add asset
        vm.prank(godmode);
        TRSRY.addAsset(address(weth), addr);

        // Mint more
        weth.mint(address(TRSRY), 1_000e18);

        // Assert that the balance is zero
        (uint256 balance, uint48 timestamp) = TRSRY.getAssetBalance(
            address(weth),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 3_000e18);
        assertEq(timestamp, block.timestamp);
    }

    function testCorrectness_getAssetBalanceLastIsCached() public {
        weth.mint(address(TRSRY), 1_000e18);
        weth.mint(address(this), 1_000e18);

        address[] memory addr = new address[](1);
        addr[0] = address(this);

        // Add asset
        vm.prank(godmode);
        TRSRY.addAsset(address(weth), addr);

        // Mint more and warp
        vm.warp(block.timestamp + 100);
        weth.mint(address(TRSRY), 1_000e18);

        // Assert that the balance is zero
        (uint256 balance, uint48 timestamp) = TRSRY.getAssetBalance(
            address(weth),
            TRSRYv1_1.Variant.LAST
        );
        assertEq(balance, 2_000e18);
        assertEq(timestamp, block.timestamp - 100);
    }

    // ========= storeBalance ========= //

    function testCorrectness_storeBalanceRevertsIfAssetDoesNotExist() public {
        // Try to store balance of zero address
        bytes memory err = abi.encodeWithSignature("TRSRY_AssetNotApproved(address)", address(0));
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.storeBalance(address(0));
    }

    function testCorrectness_storeBalanceZeroBalanceInTreasuryAndExternally() public {
        // Add asset
        vm.startPrank(godmode);
        TRSRY.addAsset(address(weth), new address[](0));

        // Store balance
        TRSRY.storeBalance(address(weth));
        vm.stopPrank();

        // Get asset data
        OlympusTreasury.Asset memory assetData_ = TRSRY.getAssetData(address(weth));

        // Assert that the balance is zero and timestamp is current
        assertEq(assetData_.lastBalance, 0);
        assertEq(assetData_.updatedAt, block.timestamp);
    }

    function testCorrectness_storeBalanceZeroBalanceInTreasuryAndNonZeroBalanceExternally() public {
        address[] memory addr = new address[](1);
        addr[0] = address(this);

        weth.mint(address(this), 1_000e18);

        // Add asset
        vm.startPrank(godmode);
        TRSRY.addAsset(address(weth), addr);

        // Store balance
        TRSRY.storeBalance(address(weth));
        vm.stopPrank();

        // Get asset data
        OlympusTreasury.Asset memory assetData_ = TRSRY.getAssetData(address(weth));

        // Assert that the balance is correct and timestamp is current
        assertEq(assetData_.lastBalance, 1_000e18);
        assertEq(assetData_.updatedAt, block.timestamp);
    }

    function testCorrectness_storeBalanceNonZeroBalanceInTreasuryAndZeroBalanceExternally() public {
        weth.mint(address(TRSRY), 1_000e18);

        // Add asset
        vm.startPrank(godmode);
        TRSRY.addAsset(address(weth), new address[](0));

        // Store balance
        TRSRY.storeBalance(address(weth));
        vm.stopPrank();

        // Get asset data
        OlympusTreasury.Asset memory assetData_ = TRSRY.getAssetData(address(weth));

        // Assert that the balance is correct and timestamp is current
        assertEq(assetData_.lastBalance, 1_000e18);
        assertEq(assetData_.updatedAt, block.timestamp);
    }

    function testCorrectness_storeBalanceNonZeroBalanceInTreasuryAndExternally() public {
        weth.mint(address(TRSRY), 1_000e18);
        weth.mint(address(this), 1_000e18);

        address[] memory addr = new address[](1);
        addr[0] = address(this);

        // Add asset
        vm.startPrank(godmode);
        TRSRY.addAsset(address(weth), addr);

        // Store balance
        TRSRY.storeBalance(address(weth));
        vm.stopPrank();

        // Get asset data
        OlympusTreasury.Asset memory assetData_ = TRSRY.getAssetData(address(weth));

        // Assert that the balance is correct and timestamp is current
        assertEq(assetData_.lastBalance, 2_000e18);
        assertEq(assetData_.updatedAt, block.timestamp);
    }

    // ========= getCategoryBalance ========= //

    function testCorrectness_getCategoryBalanceRevertsIfCategoryDoesNotExist() public {
        // Try to get balance of zero address
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_InvalidParams(uint256,bytes)",
            0,
            abi.encode(toCategory("abcdef"))
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.getCategoryBalance(toCategory("abcdef"), TRSRYv1_1.Variant.CURRENT);
    }

    function testCorrectness_getCategoryBalanceZeroAssets() public {
        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));
        vm.stopPrank();

        // Assert that the balance is zero
        (uint256 balance, ) = TRSRY.getCategoryBalance(
            toCategory("test"),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 0);
    }

    function testCorrectness_getCategoryBalanceOneAssetZeroBalanceInTreasuryAndExternally() public {
        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add asset
        TRSRY.addAsset(address(weth), new address[](0));
        TRSRY.categorize(address(weth), toCategory("test"));
        vm.stopPrank();

        // Assert that the balance is zero
        (uint256 balance, ) = TRSRY.getCategoryBalance(
            toCategory("test"),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 0);
    }

    function testCorrectness_getCategoryBalanceOneAssetZeroBalanceInTreasuryAndNonZeroBalanceExternally()
        public
    {
        address[] memory addr = new address[](1);
        addr[0] = address(this);

        weth.mint(address(this), 1_000e18);

        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add asset
        TRSRY.addAsset(address(weth), addr);
        TRSRY.categorize(address(weth), toCategory("test"));
        vm.stopPrank();

        // Assert that the balance is correct
        (uint256 balance, ) = TRSRY.getCategoryBalance(
            toCategory("test"),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 1_000e18);
    }

    function testCorrectness_getCategoryBalanceOneAssetNonZeroBalanceInTreasuryAndZeroBalanceExternally()
        public
    {
        weth.mint(address(TRSRY), 1_000e18);

        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add asset
        TRSRY.addAsset(address(weth), new address[](0));
        TRSRY.categorize(address(weth), toCategory("test"));
        vm.stopPrank();

        // Assert that the balance is correct
        (uint256 balance, ) = TRSRY.getCategoryBalance(
            toCategory("test"),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 1_000e18);
    }

    function testCorrectness_getCategoryBalanceOneAssetNonZeroBalanceInTreasuryAndExternally()
        public
    {
        weth.mint(address(TRSRY), 1_000e18);
        weth.mint(address(this), 1_000e18);

        address[] memory addr = new address[](1);
        addr[0] = address(this);

        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add asset
        TRSRY.addAsset(address(weth), addr);
        TRSRY.categorize(address(weth), toCategory("test"));
        vm.stopPrank();

        // Assert that the balance is correct
        (uint256 balance, ) = TRSRY.getCategoryBalance(
            toCategory("test"),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 2_000e18);
    }

    function testCorrectness_getCategoryBalanceManyAssetsZeroBalanceInTreasuryAndExternally()
        public
    {
        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add assets
        TRSRY.addAsset(address(weth), new address[](0));
        TRSRY.addAsset(address(tkn), new address[](0));
        TRSRY.categorize(address(weth), toCategory("test"));
        TRSRY.categorize(address(tkn), toCategory("test"));
        vm.stopPrank();

        // Assert that the balance is zero
        (uint256 balance, ) = TRSRY.getCategoryBalance(
            toCategory("test"),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 0);
    }

    function testCorrectness_getCategoryBalanceManyAssetsZeroBalanceInTreasuryAndNonZeroBalanceExternallyForSomeAssets()
        public
    {
        address[] memory addr = new address[](1);
        addr[0] = address(this);

        weth.mint(address(this), 1_000e18);

        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add assets
        TRSRY.addAsset(address(weth), addr);
        TRSRY.addAsset(address(tkn), new address[](0));
        TRSRY.categorize(address(weth), toCategory("test"));
        TRSRY.categorize(address(tkn), toCategory("test"));
        vm.stopPrank();

        // Assert that the balance is correct
        (uint256 balance, ) = TRSRY.getCategoryBalance(
            toCategory("test"),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 1_000e18);
    }

    function testCorrectness_getCategoryBalanceManyAssetsZeroBalanceInTreasuryAndNonZeroBalanceExternallyForAllAssets()
        public
    {
        address[] memory addr = new address[](1);
        addr[0] = address(this);

        weth.mint(address(this), 1_000e18);
        tkn.mint(address(this), 1_000e18);

        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add assets
        TRSRY.addAsset(address(weth), addr);
        TRSRY.addAsset(address(tkn), addr);
        TRSRY.categorize(address(weth), toCategory("test"));
        TRSRY.categorize(address(tkn), toCategory("test"));
        vm.stopPrank();

        // Assert that the balance is correct
        (uint256 balance, ) = TRSRY.getCategoryBalance(
            toCategory("test"),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 2_000e18);
    }

    function testCorrectness_getCategoryBalanceManyAssetsNonZeroBalanceInTreasuryAndZeroBalanceExternallyForSomeAssets()
        public
    {
        weth.mint(address(TRSRY), 1_000e18);

        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add assets
        TRSRY.addAsset(address(weth), new address[](0));
        TRSRY.addAsset(address(tkn), new address[](0));
        TRSRY.categorize(address(weth), toCategory("test"));
        TRSRY.categorize(address(tkn), toCategory("test"));
        vm.stopPrank();

        // Assert that the balance is correct
        (uint256 balance, ) = TRSRY.getCategoryBalance(
            toCategory("test"),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 1_000e18);
    }

    function testCorrectness_getCategoryBalanceManyAssetsNonZeroBalanceInTreasuryAndZeroBalanceExternallyForAllAssets()
        public
    {
        weth.mint(address(TRSRY), 1_000e18);
        tkn.mint(address(TRSRY), 1_000e18);

        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add assets
        TRSRY.addAsset(address(weth), new address[](0));
        TRSRY.addAsset(address(tkn), new address[](0));
        TRSRY.categorize(address(weth), toCategory("test"));
        TRSRY.categorize(address(tkn), toCategory("test"));
        vm.stopPrank();

        // Assert that the balance is correct
        (uint256 balance, ) = TRSRY.getCategoryBalance(
            toCategory("test"),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 2_000e18);
    }

    function testCorrectness_getCategoryBalanceManyAssetsNonZeroBalanceInTreasuryAndExternallyForSomeAssets()
        public
    {
        weth.mint(address(TRSRY), 1_000e18);
        weth.mint(address(this), 1_000e18);

        tkn.mint(address(TRSRY), 1_000e18);

        address[] memory addr = new address[](1);
        addr[0] = address(this);

        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add assets
        TRSRY.addAsset(address(weth), addr);
        TRSRY.addAsset(address(tkn), new address[](0));
        TRSRY.categorize(address(weth), toCategory("test"));
        TRSRY.categorize(address(tkn), toCategory("test"));
        vm.stopPrank();

        // Assert that the balance is correct
        (uint256 balance, ) = TRSRY.getCategoryBalance(
            toCategory("test"),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 3_000e18);
    }

    function testCorrectness_getCategoryBalanceManyAssetsNonZeroBalanceInTreasuryAndExternallyForAllAssets()
        public
    {
        weth.mint(address(TRSRY), 1_000e18);
        weth.mint(address(this), 1_000e18);

        tkn.mint(address(TRSRY), 1_000e18);
        tkn.mint(address(this), 1_000e18);

        address[] memory addr = new address[](1);
        addr[0] = address(this);

        // Add category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add assets
        TRSRY.addAsset(address(weth), addr);
        TRSRY.addAsset(address(tkn), addr);
        TRSRY.categorize(address(weth), toCategory("test"));
        TRSRY.categorize(address(tkn), toCategory("test"));
        vm.stopPrank();

        // Assert that the balance is correct
        (uint256 balance, ) = TRSRY.getCategoryBalance(
            toCategory("test"),
            TRSRYv1_1.Variant.CURRENT
        );
        assertEq(balance, 4_000e18);
    }

    // ========= addCategoryGroup ========= //

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
        vm.assume(
            groupName_ != bytes32("liquidity-preference") &&
                groupName_ != bytes32("value-baskets") &&
                groupName_ != bytes32("market-sensitivity")
        );

        vm.prank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup(groupName_));

        // Check that the category group was added
        CategoryGroup addedGroup = TRSRY.categoryGroups(3);
        assertEq(fromCategoryGroup(addedGroup), groupName_);
    }

    // ========= addCategory ========= //

    function testCorrectness_addCategoryRevertsIfUnconfiguredGroup() public {
        // Try to push to 'abcdef' category group which does not exist
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_CategoryGroupDoesNotExist(bytes32)",
            toCategoryGroup("abcdef")
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("abcdef"));
    }

    function testCorrectness_addCategoryRevertsIfGroupExists() public {
        // Try to push 'liquid' category to 'liquidity-preference' group which already exists
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_CategoryExists(bytes32)",
            toCategory("liquid")
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.addCategory(toCategory("liquid"), toCategoryGroup("liquidity-preference"));
    }

    function testCorrectness_addCategoryStoresCorrectlyZeroPrior(bytes32 category_) public {
        vm.assume(
            category_ != bytes32("liquid") &&
                category_ != bytes32("illiquid") &&
                category_ != bytes32("reserves") &&
                category_ != bytes32("strategic") &&
                category_ != bytes32("protocol-owned-liquidity") &&
                category_ != bytes32("stable") &&
                category_ != bytes32("volatile")
        );

        // Create category group
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));

        // Assert that there are no categories in the group by expecting a generic revert when reading an array
        vm.expectRevert();
        TRSRY.groupToCategories(toCategoryGroup("test-group"), 0);

        // Add category to group
        TRSRY.addCategory(toCategory(category_), toCategoryGroup("test-group"));

        // Assert that the category was added to the group
        assertEq(
            fromCategory(TRSRY.groupToCategories(toCategoryGroup("test-group"), 0)),
            category_
        );
        vm.stopPrank();
    }

    function testCorrectness_addCategoryStoresCorrectlyOnePrior(bytes32 category_) public {
        vm.assume(
            category_ != bytes32("test") &&
                category_ != bytes32("liquid") &&
                category_ != bytes32("illiquid") &&
                category_ != bytes32("reserves") &&
                category_ != bytes32("strategic") &&
                category_ != bytes32("protocol-owned-liquidity") &&
                category_ != bytes32("stable") &&
                category_ != bytes32("volatile")
        );

        // Create category group
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));

        // Add category to group
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Assert that there is one category in the group
        assertEq(fromCategory(TRSRY.groupToCategories(toCategoryGroup("test-group"), 0)), "test");

        // Add category to group
        TRSRY.addCategory(toCategory(category_), toCategoryGroup("test-group"));

        // Assert that the category was added to the group
        assertEq(
            fromCategory(TRSRY.groupToCategories(toCategoryGroup("test-group"), 1)),
            category_
        );
        vm.stopPrank();
    }

    function testCorrectness_addCategoryStoresCorrectlyManyPrior(bytes32 category_) public {
        vm.assume(
            category_ != bytes32("test1") &&
                category_ != bytes32("test2") &&
                category_ != bytes32("test3") &&
                category_ != bytes32("liquid") &&
                category_ != bytes32("illiquid") &&
                category_ != bytes32("reserves") &&
                category_ != bytes32("strategic") &&
                category_ != bytes32("protocol-owned-liquidity") &&
                category_ != bytes32("stable") &&
                category_ != bytes32("volatile")
        );

        // Create category group
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));

        // Add category to group
        TRSRY.addCategory(toCategory("test1"), toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test2"), toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test3"), toCategoryGroup("test-group"));

        // Assert that there are three categories in the group
        assertEq(fromCategory(TRSRY.groupToCategories(toCategoryGroup("test-group"), 0)), "test1");
        assertEq(fromCategory(TRSRY.groupToCategories(toCategoryGroup("test-group"), 1)), "test2");
        assertEq(fromCategory(TRSRY.groupToCategories(toCategoryGroup("test-group"), 2)), "test3");

        // Add category to group
        TRSRY.addCategory(toCategory(category_), toCategoryGroup("test-group"));

        // Assert that the category was added to the group
        assertEq(
            fromCategory(TRSRY.groupToCategories(toCategoryGroup("test-group"), 3)),
            category_
        );
        vm.stopPrank();
    }

    // ========= categorize ========= //

    function testCorrectness_categorizeRevertsIfInvalidAsset() public {
        // Try to categorize zero address
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_InvalidParams(uint256,bytes)",
            0,
            abi.encode(address(0))
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.categorize(address(0), toCategory("liquid"));
    }

    function testCorrectness_categorizeRevertsIfInvalidCategory() public {
        // Add asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), new address[](0));

        // Try to categorize zero address
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_CategoryDoesNotExist(bytes32)",
            toCategory("abcdef")
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.categorize(address(reserve), toCategory("abcdef"));
    }

    function testCorrectness_categorizeStoresCorrectlyZeroPrior() public {
        // Create category group
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add asset
        TRSRY.addAsset(address(reserve), new address[](0));

        // Assert that categorization for the asset is null
        assertEq(
            fromCategory(TRSRY.categorization(address(reserve), toCategoryGroup("test-group"))),
            ""
        );

        // Categorize asset
        TRSRY.categorize(address(reserve), toCategory("test"));

        // Assert that the asset was categorized
        assertEq(
            fromCategory(TRSRY.categorization(address(reserve), toCategoryGroup("test-group"))),
            "test"
        );
    }

    function testCorrectness_categorizeStoresCorrectlyOnePrior() public {
        // Create category group
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add assets
        TRSRY.addAsset(address(weth), new address[](0));
        TRSRY.addAsset(address(reserve), new address[](0));

        // Categorize asset
        TRSRY.categorize(address(weth), toCategory("test"));

        // Assert that the asset was categorized
        assertEq(
            fromCategory(TRSRY.categorization(address(weth), toCategoryGroup("test-group"))),
            "test"
        );

        // Categorize asset
        TRSRY.categorize(address(reserve), toCategory("test"));

        // Assert that the asset was categorized
        assertEq(
            fromCategory(TRSRY.categorization(address(reserve), toCategoryGroup("test-group"))),
            "test"
        );
    }

    function testCorrectness_categorizeStoresCorrectlyManyPrior() public {
        // Create category group
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add assets
        TRSRY.addAsset(address(weth), new address[](0));
        TRSRY.addAsset(address(tkn), new address[](0));
        TRSRY.addAsset(address(reserve), new address[](0));

        // Categorize assets
        TRSRY.categorize(address(weth), toCategory("test"));
        TRSRY.categorize(address(tkn), toCategory("test"));

        // Assert that the asset was categorized
        assertEq(
            fromCategory(TRSRY.categorization(address(weth), toCategoryGroup("test-group"))),
            "test"
        );
        assertEq(
            fromCategory(TRSRY.categorization(address(tkn), toCategoryGroup("test-group"))),
            "test"
        );

        // Categorize asset
        TRSRY.categorize(address(reserve), toCategory("test"));

        // Assert that the asset was categorized
        assertEq(
            fromCategory(TRSRY.categorization(address(reserve), toCategoryGroup("test-group"))),
            "test"
        );
    }
}
