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
import {TRSRYv1_1, Category, CategoryGroup} from "src/modules/TRSRY/TRSRY.v1.sol";

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
// [X] addAsset - adds an asset configuration to the treasury
//      [X] reverts if asset is already configured
//      [X] reverts if asset is not a contract
//      [X] asset data stored correctly
//      [X] zero locations prior
//      [X] one location prior
//      [X] many locations prior
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
// [ ] addCategoryGroup - adds an asset category group to the treasury
//      [ ] reverts if category group is already configured
//      [ ] category group data stored correctly
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

    Kernel internal kernel;
    OlympusTreasury public TRSRY;
    MockERC20 public reserve;
    address public godmode;

    UserFactory public userCreator;
    address internal alice;

    uint256 internal constant INITIAL_TOKEN_AMOUNT = 100e18;

    function setUp() public {
        kernel = new Kernel();
        TRSRY = new OlympusTreasury(kernel);
        reserve = new MockERC20("Reserve", "RSRV", 18);

        {
            userCreator = new UserFactory();
            address[] memory users = userCreator.create(1);
            alice = users[0];
        }

        kernel.executeAction(Actions.InstallModule, address(TRSRY));

        // Generate test fixture policy addresses with different authorizations
        godmode = TRSRY.generateGodmodeFixture(type(OlympusTreasury).name);
        kernel.executeAction(Actions.ActivatePolicy, godmode);

        // Give TRSRY some tokens
        reserve.mint(address(TRSRY), INITIAL_TOKEN_AMOUNT);
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
}
