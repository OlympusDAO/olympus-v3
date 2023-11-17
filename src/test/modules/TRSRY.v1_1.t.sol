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
// [X] addAsset - adds an asset configuration to the treasury
//      [X] reverts if asset is already configured
//      [X] reverts if asset is not a contract
//      [X] asset data stored correctly
//      [X] zero locations prior
//      [X] one location prior
//      [X] many locations prior
// [X] removeAsset - removes an asset configuration from the treasury
//      [X] reverts if asset is not configured
//      [X] asset data removed correctly
// [X] addAssetLocation - adds a location to an asset configuration
//      [X] reverts if asset is not configured
//      [X] reverts if location is already configured
//      [X] location data stored correctly
//      [X] zero locations prior
//      [X] one location prior
//      [X] many locations prior
// [X] removeAssetLocation - removes a location from an asset configuration
//      [X] reverts if asset is not configured
//      [X] location data removed correctly
//      [X] zero locations after
//      [X] one location after
//      [X] many locations after
// [X] addCategoryGroup - adds an asset category group to the treasury
//      [X] reverts if category group is already configured
//      [X] category group data stored correctly
// [X] removeCategoryGroup - removes an asset category group from the treasury
//      [X] reverts if category group is not configured
//      [X] category group data removed correctly
// [X] addCategory - adds an asset category to the treasury
//      [X] reverts if category group is not configured
//      [X] reverts if category is already configured
//      [X] category data stored correctly with zero categories in group prior
//      [X] category data stored correctly with one category in group prior
//      [X] category data stored correctly with many categories in group prior
// [X] removeCategory - removes an asset category from the treasury
//      [X] reverts if category is not configured
//      [X] category data removed correctly
// [X] categorize - categorize an asset into a category within a category group
//      [X] reverts if asset is not configured
//      [X] reverts if category is not configured
//      [X] category data stored correctly with zero assets in category prior
//      [X] category data stored correctly with one asset in category prior
//      [X] category data stored correctly with many assets in category prior
// [X] uncategorize - uncategorize an asset from a category within a category group
//      [X] reverts if asset is not configured
//      [X] reverts if asset is not in category
//      [X] category data removed correctly with zero assets in category after

contract TRSRYv1_1Test is Test {
    using ModuleTestFixtureGenerator for OlympusTreasury;

    address public godmode;

    Kernel internal kernel;
    OlympusTreasury public TRSRY;

    MockERC20 public reserve;
    MockERC20 public weth;
    MockERC20 public tkn;

    UserFactory public userCreator;
    address internal alice;

    uint256 internal constant INITIAL_TOKEN_AMOUNT = 200_000_000e18;

    function setUp() public {
        // Kernel and Module creation
        kernel = new Kernel();
        TRSRY = new OlympusTreasury(kernel);

        // Create token
        reserve = new MockERC20("Reserve", "RSRV", 18);
        weth = new MockERC20("WETH", "WETH", 18);
        tkn = new MockERC20("TKN", "TKN", 18);

        {
            userCreator = new UserFactory();
            address[] memory users = userCreator.create(1);
            alice = users[0];
        }

        // Generate test fixture policy addresses with different authorizations
        godmode = TRSRY.generateGodmodeFixture(type(OlympusTreasury).name);

        // Initialize module and godmode
        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.ActivatePolicy, godmode);

        // Mint tokens to TRSRY
        reserve.mint(address(TRSRY), INITIAL_TOKEN_AMOUNT);
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

    // =================== ASSET DATA MANAGEMENT ===================== //

    // -- Test: addAsset -------------------------------

    function test_addAsset() public {
        // Add an asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), new address[](0));

        // Verify asset data
        TRSRYv1_1.Asset memory asset = TRSRY.getAssetData(address(reserve));
        assertEq(asset.approved, true);
        assertEq(asset.updatedAt, block.timestamp);
        assertEq(asset.lastBalance, INITIAL_TOKEN_AMOUNT);
        assertEq(asset.locations.length, 0);

        // Verify asset list
        address[] memory assets = TRSRY.getAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(reserve));
    }

    function test_addAsset_onePreviousLocation() public {
        reserve.mint(address(1), INITIAL_TOKEN_AMOUNT);

        address[] memory locations = new address[](1);
        locations[0] = address(1);
        // Add an asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), locations);

        // Verify asset data
        TRSRYv1_1.Asset memory asset = TRSRY.getAssetData(address(reserve));
        assertEq(asset.approved, true);
        assertEq(asset.updatedAt, block.timestamp);
        assertEq(asset.lastBalance, 2 * INITIAL_TOKEN_AMOUNT);
        assertEq(asset.locations.length, 1);

        // Verify asset list
        address[] memory assets = TRSRY.getAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(reserve));
    }

    function test_addAsset_manyPreviousLocations() public {
        reserve.mint(address(1), INITIAL_TOKEN_AMOUNT);
        reserve.mint(address(2), INITIAL_TOKEN_AMOUNT);

        address[] memory locations = new address[](2);
        locations[0] = address(1);
        locations[1] = address(2);
        // Add an asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), locations);

        // Verify asset data
        TRSRYv1_1.Asset memory asset = TRSRY.getAssetData(address(reserve));
        assertEq(asset.approved, true);
        assertEq(asset.updatedAt, block.timestamp);
        assertEq(asset.lastBalance, 3 * INITIAL_TOKEN_AMOUNT);
        assertEq(asset.locations.length, 2);

        // Verify asset list
        address[] memory assets = TRSRY.getAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(reserve));
    }

    function testRevert_addAsset_AssetAlreadyApproved() public {
        // Add an asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), new address[](0));

        /// Try to add an already approved asset
        bytes memory err = abi.encodeWithSignature("TRSRY_AssetAlreadyApproved(address)", reserve);
        vm.expectRevert(err);
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), new address[](0));
    }

    function testRevert_addAsset_AssetNotContract() public {
        /// Try to add an address which is not a contract
        bytes memory err = abi.encodeWithSignature("TRSRY_AssetNotContract(address)", alice);
        vm.expectRevert(err);
        vm.prank(godmode);
        TRSRY.addAsset(alice, new address[](0));
    }

    // -- Test: removeAsset

    function testCorrectness_removeAsset_AssetNotConfigured() public {
        // Try to remove an asset which is not configured
        bytes memory err = abi.encodeWithSignature("TRSRY_AssetNotApproved(address)", reserve);
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.removeAsset(address(reserve));
    }

    function testCorrectness_removeAsset_AssetConfigured() public {
        address[] memory locations = new address[](1);
        locations[0] = address(1);

        // Add an asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), locations);

        // Remove the asset
        vm.prank(godmode);
        TRSRY.removeAsset(address(reserve));

        // Verify asset data
        TRSRYv1_1.Asset memory asset = TRSRY.getAssetData(address(reserve));
        assertEq(asset.approved, false);
        assertEq(asset.lastBalance, 0);
        assertEq(asset.locations.length, 0);

        // Verify asset list
        address[] memory assets = TRSRY.getAssets();
        assertEq(assets.length, 0);
    }

    // -- Test: addAssetLocation -------------------------------

    function testFuzz_addAssetLocation(address allocator_) public {
        vm.assume(allocator_ != address(0));

        // Add an asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), new address[](0));

        // Add a location
        vm.prank(godmode);
        TRSRY.addAssetLocation(address(reserve), allocator_);

        // Verify asset data
        TRSRYv1_1.Asset memory asset = TRSRY.getAssetData(address(reserve));
        assertEq(asset.approved, true);
        assertEq(asset.updatedAt, block.timestamp);
        assertEq(asset.lastBalance, INITIAL_TOKEN_AMOUNT);
        assertEq(asset.locations.length, 1);
        assertEq(asset.locations[0], allocator_);
    }

    function testFuzz_addAssetLocation_onePreviousLocation(address allocator_) public {
        vm.assume(allocator_ != address(0));
        vm.assume(allocator_ != address(1));

        address[] memory locations = new address[](1);
        locations[0] = address(1);
        // Add an asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), locations);

        // Add a location
        vm.prank(godmode);
        TRSRY.addAssetLocation(address(reserve), allocator_);

        // Verify asset list
        TRSRYv1_1.Asset memory asset = TRSRY.getAssetData(address(reserve));
        assertEq(asset.locations.length, 2);
        assertEq(asset.locations[1], allocator_);
    }

    function testFuzz_addAssetLocation_manyPreviousLocations(address allocator_) public {
        vm.assume(allocator_ != address(0));
        vm.assume(allocator_ != address(1));
        vm.assume(allocator_ != address(2));

        address[] memory locations = new address[](2);
        locations[0] = address(1);
        locations[1] = address(2);
        // Add an asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), locations);

        // Add a location
        vm.prank(godmode);
        TRSRY.addAssetLocation(address(reserve), allocator_);

        // Verify asset list
        TRSRYv1_1.Asset memory asset = TRSRY.getAssetData(address(reserve));
        assertEq(asset.locations.length, 3);
        assertEq(asset.locations[2], allocator_);
    }

    function testRevert_addAssetLocation_AssetNotApproved() public {
        /// Try to add the location of an asset which is not approved
        bytes memory err = abi.encodeWithSignature("TRSRY_AssetNotApproved(address)", reserve);
        vm.expectRevert(err);
        vm.prank(godmode);
        TRSRY.addAssetLocation(address(reserve), address(1));
    }

    function testRevert_addAssetLocation_AddresZero() public {
        // Add an asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), new address[](0));

        /// Try to add address(0) as the location
        vm.expectRevert();
        vm.prank(godmode);
        TRSRY.addAssetLocation(address(reserve), address(0));
    }

    // -- Test: removeAssetLocation -------------------------------

    function testFuzz_removeAssetLocation(address allocator_) public {
        vm.assume(allocator_ != address(0));

        // Add an asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), new address[](0));

        // Add a location
        vm.prank(godmode);
        TRSRY.addAssetLocation(address(reserve), allocator_);

        // Remove a location
        vm.prank(godmode);
        TRSRY.removeAssetLocation(address(reserve), allocator_);

        // Verify asset data
        TRSRYv1_1.Asset memory asset = TRSRY.getAssetData(address(reserve));
        assertEq(asset.locations.length, 0);
    }

    function testFuzz_removeAssetLocation_onePreviousLocation(address allocator_) public {
        vm.assume(allocator_ != address(0));
        vm.assume(allocator_ != address(1));

        address[] memory locations = new address[](1);
        locations[0] = address(1);
        // Add an asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), locations);

        // Add a location
        vm.prank(godmode);
        TRSRY.addAssetLocation(address(reserve), allocator_);

        // Remove a location
        vm.prank(godmode);
        TRSRY.removeAssetLocation(address(reserve), allocator_);

        // Verify asset data
        TRSRYv1_1.Asset memory asset = TRSRY.getAssetData(address(reserve));
        assertEq(asset.locations.length, 1);
        assertEq(asset.locations[0], address(1));
    }

    function testFuzz_removeAssetLocation_manyPreviousLocations(address allocator_) public {
        vm.assume(allocator_ != address(0));
        vm.assume(allocator_ != address(1));
        vm.assume(allocator_ != address(2));

        address[] memory locations = new address[](2);
        locations[0] = address(1);
        locations[1] = address(2);
        // Add an asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), locations);

        // Add a location
        vm.prank(godmode);
        TRSRY.addAssetLocation(address(reserve), allocator_);

        // Remove a location
        vm.prank(godmode);
        TRSRY.removeAssetLocation(address(reserve), allocator_);

        // Verify asset data
        TRSRYv1_1.Asset memory asset = TRSRY.getAssetData(address(reserve));
        assertEq(asset.locations.length, 2);
        assertEq(asset.locations[0], address(1));
        assertEq(asset.locations[1], address(2));
    }

    function testRevert_removeAssetLocation_AssetNotApproved() public {
        /// Try to remove the location of an asset which is not approved
        bytes memory err = abi.encodeWithSignature("TRSRY_AssetNotApproved(address)", reserve);
        vm.expectRevert(err);
        vm.prank(godmode);
        TRSRY.removeAssetLocation(address(reserve), address(1));
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

    function testCorrectness_addCategoryGroupRevertsIfEmptyString() public {
        // Try to push '' category group
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_InvalidParams(uint256,bytes)",
            0,
            abi.encode(toCategoryGroup(""))
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup(""));
    }

    function testCorrectness_addCategoryGroupRevertsIfZero() public {
        // Try to push a 0 category group
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_InvalidParams(uint256,bytes)",
            0,
            abi.encode(toCategoryGroup(0))
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup(0));
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

    // ========= removeCategoryGroup ========= //

    function testCorrectness_removeCategoryGroupRevertsIfNotConfigured() public {
        // Try to remove 'abcdef' category group which does not exist
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_CategoryGroupDoesNotExist(bytes32)",
            toCategoryGroup("abcdef")
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.removeCategoryGroup(toCategoryGroup("abcdef"));
    }

    function testCorrectness_removeCategoryGroupRemovesGroup(bytes32 groupName_) public {
        vm.assume(
            groupName_ != bytes32("liquidity-preference") &&
                groupName_ != bytes32("value-baskets") &&
                groupName_ != bytes32("market-sensitivity")
        );

        // Add category group
        vm.prank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup(groupName_));

        // Remove category group
        vm.prank(godmode);
        TRSRY.removeCategoryGroup(toCategoryGroup(groupName_));

        // Check that the category group was removed
        vm.expectRevert();
        CategoryGroup removedGroup = TRSRY.categoryGroups(3);
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

    function testCorrectness_addCategoryRevertsIfEmptyStringGroup() public {
        // Try to push to '' category group which does not exist
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_CategoryGroupDoesNotExist(bytes32)",
            toCategoryGroup("")
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.addCategory(toCategory("test"), toCategoryGroup(""));
    }

    function testCorrectness_addCategoryRevertsIfZeroGroup() public {
        // Try to push to empty category group which does not exist
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_CategoryGroupDoesNotExist(bytes32)",
            toCategoryGroup(0)
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.addCategory(toCategory("test"), toCategoryGroup(0));
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

    function testCorrectness_addCategoryRevertsIfCategoryEmptyString() public {
        // Try to push an empty category to 'liquidity-preference' group
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_InvalidParams(uint256,bytes)",
            0,
            abi.encode(toCategory(""))
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.addCategory(toCategory(""), toCategoryGroup("liquidity-preference"));
    }

    function testCorrectness_addCategoryRevertsIfCategoryZero() public {
        // Try to push an empty category to 'liquidity-preference' group
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_InvalidParams(uint256,bytes)",
            0,
            abi.encode(toCategory(0))
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.addCategory(toCategory(0), toCategoryGroup("liquidity-preference"));
    }

    // ========= removeCategory ========= //

    function testCorrectness_removeCategoryRevertsIfUnconfiguredGroup() public {
        // Try to remove 'test' category which does not exist
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_CategoryDoesNotExist(bytes32)",
            toCategory("test")
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.removeCategory(toCategory("test"));
    }

    function testCorrectness_removeCategoryRevertsIfEmptyStringCategory() public {
        // Try to remove '' category which does not exist
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_CategoryDoesNotExist(bytes32)",
            toCategory("")
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.removeCategory(toCategory(""));
    }

    function testCorrectness_removeCategoryRevertsIfZeroCategory() public {
        // Try to remove 0 category which does not exist
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_CategoryDoesNotExist(bytes32)",
            toCategory(0)
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.removeCategory(toCategory(0));
    }

    function testCorrectness_removeCategoryRemovesCategoryInfo() public {
        // Add category group and category
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Remove category
        TRSRY.removeCategory(toCategory("test"));

        // Assert that the category was removed
        // categoryToGroup should be bytes32(0)
        assertEq(fromCategoryGroup(TRSRY.categoryToGroup(toCategory("test"))), bytes32(0));

        // groupToCategories should be empty
        vm.expectRevert();
        TRSRY.groupToCategories(toCategoryGroup("test-group"), 0);
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

    function testCorrectness_categorizeRevertsIfEmptyStringCategory() public {
        // Add asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), new address[](0));

        // Try to add to empty string category
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_CategoryDoesNotExist(bytes32)",
            toCategory("")
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.categorize(address(reserve), toCategory(""));
    }

    function testCorrectness_categorizeRevertsIfZeroCategory() public {
        // Add asset
        vm.prank(godmode);
        TRSRY.addAsset(address(reserve), new address[](0));

        // Try to add to zero category
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_CategoryDoesNotExist(bytes32)",
            toCategory(0)
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.categorize(address(reserve), toCategory(0));
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

    // ========= uncategorize ========= //

    function testCorrectness_uncategorizeRevertsIfInvalidAsset() public {
        // Try to uncategorize zero address
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_InvalidParams(uint256,bytes)",
            0,
            abi.encode(address(0))
        );
        vm.expectRevert(err);

        vm.prank(godmode);
        TRSRY.uncategorize(address(0), toCategory("liquid"));
    }

    function testCorrectness_uncategorizeRevertsIfAssetNotInCategory() public {
        // Create category groups and categories
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));
        TRSRY.addCategoryGroup(toCategoryGroup("test-group2"));
        TRSRY.addCategory(toCategory("test2"), toCategoryGroup("test-group2"));

        // Add asset
        TRSRY.addAsset(address(reserve), new address[](0));

        // Categorize asset
        TRSRY.categorize(address(reserve), toCategory("test"));

        // Try to uncategorize from test2
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_AssetNotInCategory(address,bytes32)",
            address(reserve),
            toCategory("test2")
        );
        vm.expectRevert(err);

        TRSRY.uncategorize(address(reserve), toCategory("test2"));
        vm.stopPrank();
    }

    function testCorrectness_uncategorizeRemovesCategorization() public {
        // Create category groups and categories
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add asset
        TRSRY.addAsset(address(reserve), new address[](0));

        // Categorize asset
        TRSRY.categorize(address(reserve), toCategory("test"));

        // Assert that the asset was categorized
        assertEq(
            fromCategory(TRSRY.categorization(address(reserve), toCategoryGroup("test-group"))),
            "test"
        );

        // Uncategorize asset
        TRSRY.uncategorize(address(reserve), toCategory("test"));

        // Assert that the asset was uncategorized
        assertEq(
            fromCategory(TRSRY.categorization(address(reserve), toCategoryGroup("test-group"))),
            bytes32(0)
        );
    }

    function testCorrectness_uncategorizeRevertsIfCategoryDoesNotExist() public {
        // Create category groups and categories
        vm.startPrank(godmode);
        TRSRY.addCategoryGroup(toCategoryGroup("test-group"));
        TRSRY.addCategory(toCategory("test"), toCategoryGroup("test-group"));

        // Add asset
        TRSRY.addAsset(address(reserve), new address[](0));

        // Categorize asset
        TRSRY.categorize(address(reserve), toCategory("test"));

        // Try to uncategorize from test2
        bytes memory err = abi.encodeWithSignature(
            "TRSRY_AssetNotInCategory(address,bytes32)",
            address(reserve),
            toCategory("test2") // Doesn't exist
        );
        vm.expectRevert(err);

        TRSRY.uncategorize(address(reserve), toCategory("test2"));
        vm.stopPrank();
    }
}
