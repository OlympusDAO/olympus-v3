// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";

import {FullMath} from "libraries/FullMath.sol";

import "src/modules/SPPLY/OlympusSupply.sol";
import {AuraBalancerSupply} from "src/modules/SPPLY/submodules/AuraBalancerSupply.sol";
import {BLVaultSupply} from "src/modules/SPPLY/submodules/BLVaultSupply.sol";
import {SiloSupply} from "src/modules/SPPLY/submodules/SiloSupply.sol";

// Tests for OlympusSupply v1.0
// Module Setup
// [X] KEYCODE - returns the module's identifier: SPPLY
// [X] VERSION - returns the module's version: 1.0
//
// Cross-chain Supply
// [X] increaseCrossChainSupply
//  [X] reverts if caller is not permissioned
//  [X] increments value, emits event
// [X] decreaseCrossChainSupply
//  [X] reverts if caller is not permissioned
//  [X] decrements value, emits event
//  [X] reverts if underflow
//
// TODO remove these?
// [ ] addChain - adds a new chain for cross-chain supply tracking
//      [ ] reverts if caller is not permissioned
//      [ ] reverts if chain already approved
//      [ ] stores chainId in chainIds array
//      [ ] stores ohm address on chain
// [ ] removeChain - removes a chain from cross-chain supply tracking
//      [ ] reverts if caller is not permissioned
//      [ ] reverts if chain not approved
//      [ ] removes chain supply from totalCrossChainSupply
//      [ ] deletes chain supply from mapping
//      [ ] removes chainId from chainIds array
//      [ ] deletes chain ohm address from mapping
// [ ] updateCrossChainSupplies - updates cross-chain supplies for the provided chains and the category supplies (across all other chains) from the provided categories
//      [ ] reverts if caller is not permissioned
//      [ ] reverts if number of chainIds doesn't match number of chain supplies provided
//      [ ] reverts if any of the chainIds are not approved
//      [ ] reverts if any of the categories are not approved
//      [ ] reverts if number of categories doesn't match number of category supplies provided
//      [ ] updates cross-chain supply for each chain provided
//      [ ] updates category supply for each category provided
//      [ ] updates totalCrossChainSupply with the sum of the chain supplies provided and reduces by the existing chain supply values
//      [ ] emits event for each chain supply update
//      [ ] emits event for each category supply update
// [ ] getCrossChainIds - returns array of all approved chainIds
//      [ ] zero chains
//      [ ] one chain
//      [ ] many chains
//
// Supply Categorization
// [X] addCategory - adds a new category for supply tracking
//  [X] reverts if caller is not permissioned
//  [X] reverts if category already approved
//  [X] reverts if category is empty
//  [X] reverts if an incorrect submodules selector is provided
//  [X] reverts if a submodules selector is provided when disabled
//  [X] stores category in categories array, emits event
//  [X] stores category with submodules enabled in categories array, emits event
// [X] removeCategory - removes a category from supply tracking
//  [X] reverts if caller is not permissioned
//  [X] reverts if category not approved
//  [X] reverts if category has locations not yet removed
//  [X] removes category from categories array, emits event
// [X] categorize - categorizes an OHM location in a category for supply tracking
//  [X] reverts if caller is not permissioned
//  [X] reverts if category not approved
//  [X] reverts if location assigned to the category already
//  [X] reverts if location assigned to another category already
//  [X] new location - adds to locations array, adds to categorization mapping, emits event
//  [X] empty category - reverts if location is not present
//  [X] empty category - removes from locations array, removes from categorization mapping, emits event
// [X] getLocations - returns array of all locations where supply is tracked
// [X] getCategories - returns array of all categories used to track supply
// [X] getCategoryData - returns the data for a given category
// [X] getLocationsByCategory - returns array of all locations categorized in a given category
//  [X] category not approved
//  [X] no locations in category
//  [X] returns locations in category
// [ ] getSupplyByCategory - returns the supply of a given category (totaled from across all locations)
//  [ ] supply calculations
//    [X] no locations in category
//    [X] zero supply
//    [X] OHM supply
//    [X] gOHM supply
//    [ ] uses submodules if enabled
//    [ ] ignores submodules if disabled
//    [ ] reverts upon submodule failure
//  [X] base function
//    [X] category not approved
//    [X] uses cached value if in the same block
//    [X] same block, no cached value
//    [X] calculates new value
//  [X] maxAge
//    [X] category not approved
//    [X] within age threshold
//    [X] within age threshold, no cache
//    [X] after age threshold
//  [X] variant
//    [X] current variant
//      [X] category not approved
//      [X] no cached value
//      [X] ignores cached value
//    [X] last variant
//      [X] category not approved
//      [X] no cached value
//      [X] cached value
//    [X] invalid variant
// [X] storeCategorySupply
//  [X] reverts if caller is not permissioned
//  [X] stores supply for category
//  [X] reverts with an invalid category
//
// Supply Metrics
// [ ] getMetric
//  [ ] metric calculations
//    [X] totalSupply - returns the total supply of OHM, including cross-chain OHM
//    [X] circulatingSupply
//    [X] floatingSupply
//    [X] collateralizedSupply
//    [ ] backedSupply
//     [X] no submodules
//     [ ] with submodules, no values
//     [ ] with submodules, with values
//  [ ] base function
//    [ ] uses cached value if in the same block
//    [ ] calculates new value
//  [ ] maxAge
//    [ ] within age threshold
//    [ ] after age threshold
//  [ ] variant
//    [ ] current variant
//    [ ] last variant
//      [ ] no cached value
//      [ ] cached value
//    [ ] invalid variant
// [ ] storeMetric
//  [ ] reverts if caller is not permissioned
//  [ ] stores metric
//  [ ] reverts with an invalid metric

contract SupplyTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusSupply;

    MockERC20 internal ohm;
    MockGohm internal gOhm;

    Kernel internal kernel;

    OlympusSupply internal moduleSupply;

    AuraBalancerSupply internal submoduleAuraBalancerSupply;
    BLVaultSupply internal submoduleBLVaultSupply;
    SiloSupply internal submoduleSiloSupply;

    address internal writer;

    UserFactory public userFactory;
    address internal treasuryAddress;
    address internal daoAddress;
    address internal polAddress;
    address internal borrowableOhmAddress;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals
    uint256 internal constant INITIAL_CROSS_CHAIN_SUPPLY = 100e9; // 100 OHM

    uint256 internal constant CATEGORIES_DEFAULT_COUNT = 4;

    // Events
    event CrossChainSupplyUpdated(uint256 supply_);
    event CategoryAdded(Category category_);
    event CategoryRemoved(Category category_);
    event LocationCategorized(address location_, Category category_);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Tokens
        {
            ohm = new MockERC20("OHM", "OHM", 9);
            gOhm = new MockGohm(GOHM_INDEX);
        }

        // Locations
        {
            userFactory = new UserFactory();
            address[] memory users = userFactory.create(4);
            treasuryAddress = users[0];
            daoAddress = users[1];
            polAddress = users[2];
            borrowableOhmAddress = users[3];
        }

        // Bophades
        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy SPPLY module
            address[2] memory tokens = [address(ohm), address(gOhm)];
            moduleSupply = new OlympusSupply(kernel, tokens, INITIAL_CROSS_CHAIN_SUPPLY);

            // Deploy mock module writer
            writer = moduleSupply.generateGodmodeFixture(type(OlympusSupply).name);

            // TODO Deploy submodules
        }

        // Initialize
        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(moduleSupply));
            kernel.executeAction(Actions.ActivatePolicy, address(writer));

            // Install submodules on supply module
            vm.startPrank(writer);
            // TODO install submodules on supply
            vm.stopPrank();
        }

        // Locations
        {
            vm.startPrank(writer);
            moduleSupply.categorize(address(treasuryAddress), toCategory("protocol-owned-treasury"));
            vm.stopPrank();
        }
    }

    // =========  TESTS ========= //

    // =========  Module Information ========= //

    function test_keycode() public {
        assertEq(fromKeycode(moduleSupply.KEYCODE()), "SPPLY");
    }

    function test_version() public {
        (uint8 major, uint8 minor) = moduleSupply.VERSION();

        assertEq(major, 1);
        assertEq(minor, 0);
    }

    // =========  increaseCrossChainSupply ========= //

    function test_increaseCrossChainSupply_notPermissioned_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);

        moduleSupply.increaseCrossChainSupply(100);
    }

    function test_increaseCrossChainSupply() public {
        uint256 expectedCrossChainSupply = INITIAL_CROSS_CHAIN_SUPPLY + 100;

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit CrossChainSupplyUpdated(expectedCrossChainSupply);

        // Increase cross-chain supply
        vm.startPrank(writer);
        moduleSupply.increaseCrossChainSupply(100);
        vm.stopPrank();

        // Check that the cross-chain supply is correct
        assertEq(moduleSupply.totalCrossChainSupply(), expectedCrossChainSupply);
    }

    // =========  decreaseCrossChainSupply ========= //

    function test_decreaseCrossChainSupply_notPermissioned_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);

        moduleSupply.decreaseCrossChainSupply(100);
    }

    function test_decreaseCrossChainSupply() public {
        uint256 expectedCrossChainSupply = INITIAL_CROSS_CHAIN_SUPPLY - 100;

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit CrossChainSupplyUpdated(expectedCrossChainSupply);

        // Decrease cross-chain supply
        vm.startPrank(writer);
        moduleSupply.decreaseCrossChainSupply(100);
        vm.stopPrank();

        // Check that the cross-chain supply is correct
        assertEq(moduleSupply.totalCrossChainSupply(), expectedCrossChainSupply);
    }

    function test_decreaseCrossChainSupply_underflow_reverts() public {
        vm.expectRevert(stdError.arithmeticError);

        // Decrease cross-chain supply
        vm.startPrank(writer);
        moduleSupply.decreaseCrossChainSupply(INITIAL_CROSS_CHAIN_SUPPLY + 100);
        vm.stopPrank();
    }

    // =========  addCategory ========= //

    function test_addCategory_notPermissioned_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);

        moduleSupply.addCategory(toCategory("test"), false, "");
    }

    function test_addCategory_alreadyApproved_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryAlreadyApproved(bytes32)",
            toCategory("protocol-owned-treasury")
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory("protocol-owned-treasury"), false, "");
        vm.stopPrank();
    }

    function test_addCategory_emptyStringName_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_InvalidParams()"
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory(""), false, "");
        vm.stopPrank();
    }

    function test_addCategory_emptyName_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_InvalidParams()"
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory(0), false, "");
        vm.stopPrank();
    }

    function test_addCategory_emptyStringSubmoduleSelector_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_InvalidParams()"
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory("test"), true, "");
        vm.stopPrank();
    }

    function test_addCategory_emptySubmoduleSelector_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_InvalidParams()"
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory("test"), true, bytes4(0));
        vm.stopPrank();
    }

    function test_addCategory_invalidSubmoduleSelector_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_InvalidParams()"
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory("test"), true, bytes4("junk"));
        vm.stopPrank();
    }

    function test_addCategory_submodulesDisabled_withSelector_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_InvalidParams()"
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory("test"), false, SupplySubmodule.getCollateralizedOhm.selector);
                vm.startPrank(writer);

    }

    function test_addCategory() public {
        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit CategoryAdded(toCategory("test"));

        // Add category
        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory("test"), false, "");
        vm.stopPrank();

        // Get categories
        Category[] memory categories = moduleSupply.getCategories();

        // Check that the category is contained in the categories array
        bool found = false;
        for (uint256 i = 0; i < categories.length; i++) {
            if (fromCategory(categories[i]) == "test") {
                found = true;
            }
        }
        assertEq(found, true);

        // Check that the category is contained in the categoryData mapping
        SPPLYv1.CategoryData memory categoryData = moduleSupply.getCategoryData(toCategory("test"));
        assertEq(categoryData.approved, true);
        assertEq(categoryData.useSubmodules, false);
        assertEq(categoryData.submoduleSelector, bytes4(0));
    }

    function test_addCategory_withSubmodules() public {
        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit CategoryAdded(toCategory("test"));

        // Add category
        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory("test"), true, SupplySubmodule.getCollateralizedOhm.selector);
        vm.stopPrank();

        // Get categories
        Category[] memory categories = moduleSupply.getCategories();

        // Check that the category is contained in the categories array
        bool found = false;
        for (uint256 i = 0; i < categories.length; i++) {
            if (fromCategory(categories[i]) == "test") {
                found = true;
            }
        }
        assertEq(found, true);

        // Check that the category is contained in the categoryData mapping
        SPPLYv1.CategoryData memory categoryData = moduleSupply.getCategoryData(toCategory("test"));
        assertEq(categoryData.approved, true);
        assertEq(categoryData.useSubmodules, true);
        assertEq(categoryData.submoduleSelector, SupplySubmodule.getCollateralizedOhm.selector);
    }

    // =========  removeCategory ========= //

    function _addCategory(bytes32 name_) internal {
        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory(name_), false, "");
        vm.stopPrank();
    }

    function test_removeCategory_notPermissioned_reverts() public {
        // Add the category
        _addCategory("test");

        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);

        // Remove the category
        moduleSupply.removeCategory(toCategory("test"));
    }

    function test_removeCategory_notApproved_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory("junk")
        );
        vm.expectRevert(err);

        // Remove the category
        vm.startPrank(writer);
        moduleSupply.removeCategory(toCategory("junk"));
        vm.stopPrank();
    }

    function test_removeCategory_existingLocations_reverts() public {
        // Add the category
        _addCategory("test");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory("test"));
        vm.stopPrank();

        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryInUse(bytes32)",
            toCategory("test")
        );
        vm.expectRevert(err);

        // Remove the category
        vm.startPrank(writer);
        moduleSupply.removeCategory(toCategory("test"));
        vm.stopPrank();
    }

    function test_removeCategory() public {
        // Add the category
        _addCategory("test");

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit CategoryRemoved(toCategory("test"));

        // Remove the category
        vm.startPrank(writer);
        moduleSupply.removeCategory(toCategory("test"));
        vm.stopPrank();

        // Get categories
        Category[] memory categories = moduleSupply.getCategories();

        // Check that the category is not contained in the categories array
        bool found = false;
        for (uint256 i = 0; i < categories.length; i++) {
            if (fromCategory(categories[i]) == "test") {
                found = true;
            }
        }
        assertEq(found, false);

        // Check that the category is not contained in the categoryData mapping
        SPPLYv1.CategoryData memory categoryData = moduleSupply.getCategoryData(toCategory("test"));
        assertEq(categoryData.approved, false);
        assertEq(categoryData.useSubmodules, false);
        assertEq(categoryData.submoduleSelector, bytes4(0));
    }

    // =========  categorize ========= //

    function test_categorize_notPermissioned_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);

        // Categorize
        moduleSupply.categorize(address(treasuryAddress), toCategory("protocol-owned-treasury"));
    }

    function test_categorize_notApproved_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory("junk")
        );
        vm.expectRevert(err);

        // Categorize
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory("junk"));
        vm.stopPrank();
    }

    function test_categorize_locationAssigned_reverts() public {
        // Add the category
        _addCategory("test");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory("test"));
        vm.stopPrank();

        bytes memory err = abi.encodeWithSignature(
            "SPPLY_LocationAlreadyCategorized(address,bytes32)",
            address(treasuryAddress),
            toCategory("test")
        );
        vm.expectRevert(err);

        // Categorize
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory("test"));
        vm.stopPrank();
    }

    function test_categorize_locationAssigned_differentCategory_reverts() public {
        // Add the category
        _addCategory("test");
        _addCategory("test2");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory("test"));
        vm.stopPrank();

        bytes memory err = abi.encodeWithSignature(
            "SPPLY_LocationAlreadyCategorized(address,bytes32)",
            address(treasuryAddress),
            toCategory("test")
        );
        vm.expectRevert(err);

        // Categorize to a different category
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory("test2"));
        vm.stopPrank();
    }

    function test_categorize() public {
        // Add the category
        _addCategory("test");

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit LocationCategorized(address(treasuryAddress), toCategory("test"));

        // Categorize
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory("test"));
        vm.stopPrank();

        // Get the category
        Category category = moduleSupply.getCategoryByLocation(address(treasuryAddress));
        assertEq(fromCategory(category), "test");

        // Get the locations and check that it is present
        address[] memory locations = moduleSupply.getLocationsByCategory(toCategory("test"));
        assertEq(locations.length, 1);
        assertEq(locations[0], address(treasuryAddress));
    }

    function test_categorize_remove_locationNotAssigned_reverts() public {
        // Add the category
        _addCategory("test");

        bytes memory err = abi.encodeWithSignature(
            "SPPLY_LocationNotCategorized(address)",
            address(treasuryAddress)
        );
        vm.expectRevert(err);

        // Remove the location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory(0));
        vm.stopPrank();
    }

    function test_categorize_remove_emptyCategoryString() public {
        // Add the category
        _addCategory("test");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory("test"));
        vm.stopPrank();

        // Remove the location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory(""));
        vm.stopPrank();

        // Check that the location is not contained in the locations array
        bool found = false;
        for (uint256 i = 0; i < moduleSupply.getLocations().length; i++) {
            if (moduleSupply.getLocations()[i] == address(treasuryAddress)) {
                found = true;
            }
        }
        assertEq(found, false);

        // Check that the location is not contained in the categorization mapping
        Category category = moduleSupply.getCategoryByLocation(address(treasuryAddress));
        assertEq(fromCategory(category), "");
    }

    function test_categorize_remove_emptyCategoryNumber() public {
        // Add the category
        _addCategory("test");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory("test"));
        vm.stopPrank();

        // Remove the location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory(0));
        vm.stopPrank();

        // Check that the location is not contained in the locations array
        bool found = false;
        for (uint256 i = 0; i < moduleSupply.getLocations().length; i++) {
            if (moduleSupply.getLocations()[i] == address(treasuryAddress)) {
                found = true;
            }
        }
        assertEq(found, false);

        // Check that the location is not contained in the categorization mapping
        Category category = moduleSupply.getCategoryByLocation(address(treasuryAddress));
        assertEq(fromCategory(category), "");
    }

    // =========  getLocations ========= //

    function test_getLocations_zeroLocations() public {
        // Remove the existing location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory(0));
        vm.stopPrank();

        // Get locations
        address[] memory locations = moduleSupply.getLocations();

        assertEq(locations.length, 0);
    }

    function test_getLocations_oneLocation() public {
        // Get locations
        address[] memory locations = moduleSupply.getLocations();

        assertEq(locations.length, 1);
        assertEq(locations[0], address(treasuryAddress));
    }

    function test_getLocations() public {
        uint8 locationCount = 5;
        string[5] memory categoryNames = ["test1", "test2", "test3", "test4", "test5"];

        // Create categories
        for (uint256 i = 0; i < locationCount; i++) {
            vm.startPrank(writer);
            moduleSupply.addCategory(toCategory(bytes32(bytes(categoryNames[i]))), false, "");
            vm.stopPrank();
        }

        // Create users
        address[] memory users = userFactory.create(locationCount);

        // Add a location
        for (uint256 i = 0; i < locationCount; i++) {
            vm.startPrank(writer);
            moduleSupply.categorize(users[i], toCategory(bytes32(bytes(categoryNames[i]))));
            vm.stopPrank();
        }

        // Get locations
        address[] memory locations = moduleSupply.getLocations();

        assertEq(locations.length, locationCount + 1);
        assertEq(locations[0], address(treasuryAddress));

        for (uint256 i = 0; i < locationCount; i++) {
            assertEq(locations[i + 1], users[i]);
        }
    }

    // =========  getCategories ========= //

    function test_getCategories_zeroCategories() public {
        // Remove the locations
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory(0));
        vm.stopPrank();

        // Remove the existing categories
        vm.startPrank(writer);
        moduleSupply.removeCategory(toCategory("protocol-owned-treasury"));
        moduleSupply.removeCategory(toCategory("dao"));
        moduleSupply.removeCategory(toCategory("protocol-owned-liquidity"));
        moduleSupply.removeCategory(toCategory("protocol-owned-borrowable"));
        vm.stopPrank();

        // Get categories
        Category[] memory categories = moduleSupply.getCategories();

        assertEq(categories.length, 0);
    }

    function test_getCategories_oneCategory() public {
        // Remove all but one existing category
        vm.startPrank(writer);
        moduleSupply.removeCategory(toCategory("dao"));
        moduleSupply.removeCategory(toCategory("protocol-owned-liquidity"));
        moduleSupply.removeCategory(toCategory("protocol-owned-borrowable"));
        vm.stopPrank();

        // Get categories
        Category[] memory categories = moduleSupply.getCategories();

        assertEq(categories.length, 1);
        assertEq(fromCategory(categories[0]), "protocol-owned-treasury");
    }

    function test_getCategories() public {
        uint8 categoryCount = 5;
        string[5] memory categoryNames = ["test1", "test2", "test3", "test4", "test5"];

        // Create categories
        for (uint256 i = 0; i < categoryCount; i++) {
            _addCategory(bytes32(bytes(categoryNames[i])));
        }

        // Get categories
        Category[] memory categories = moduleSupply.getCategories();

        assertEq(categories.length, categoryCount + CATEGORIES_DEFAULT_COUNT);
        assertEq(fromCategory(categories[0]), "protocol-owned-treasury");
        assertEq(fromCategory(categories[1]), "dao");
        assertEq(fromCategory(categories[2]), "protocol-owned-liquidity");
        assertEq(fromCategory(categories[3]), "protocol-owned-borrowable");

        for (uint256 i = 0; i < categoryCount; i++) {
            assertEq(fromCategory(categories[i + CATEGORIES_DEFAULT_COUNT]), bytes32(bytes(categoryNames[i])));
        }
    }

    // =========  getCategoryData ========= //

    function test_getCategoryData() public {
        // Add the category
        _addCategory("test");

        // Get the category data
        SPPLYv1.CategoryData memory categoryData = moduleSupply.getCategoryData(toCategory("test"));

        assertEq(categoryData.approved, true);
        assertEq(categoryData.useSubmodules, false);
        assertEq(categoryData.submoduleSelector, bytes4(0));
    }

    function test_getCategoryData_categoryNotApproved_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory("junk")
        );
        vm.expectRevert(err);

        // Get the category data
        moduleSupply.getCategoryData(toCategory("junk"));
    }

    // =========  getLocationsByCategory ========= //

    function test_getLocationsByCategory_categoryNotApproved_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory("junk")
        );
        vm.expectRevert(err);

        // Get locations
        moduleSupply.getLocationsByCategory(toCategory("junk"));
    }

    function test_getLocationsByCategory_noLocations() public {
        // Remove the existing location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory(0));
        vm.stopPrank();

        // Get locations
        address[] memory locations = moduleSupply.getLocationsByCategory(toCategory("protocol-owned-treasury"));

        assertEq(locations.length, 0);
    }

    function test_getLocationsByCategory_fuzz(uint8 locationCount_) public {
        // Create locations
        uint8 locationCount = uint8(bound(locationCount_, 1, 10));

        // Create users
        address[] memory users = userFactory.create(locationCount);

        // Add locations to the category
        for (uint256 i = 0; i < locationCount; i++) {
            vm.startPrank(writer);
            moduleSupply.categorize(users[i], toCategory("protocol-owned-treasury"));
            vm.stopPrank();
        }

        // Get locations
        address[] memory locations = moduleSupply.getLocationsByCategory(toCategory("protocol-owned-treasury"));

        assertEq(locations.length, locationCount + 1);

        // Ensure locations are not added to other categories
        address[] memory locationsTwo = moduleSupply.getLocationsByCategory(toCategory("dao"));

        assertEq(locationsTwo.length, 0);
    }

    // =========  getSupplyByCategory ========= //

    function test_getSupplyByCategory_noLocations() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Remove the existing location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory(0));
        vm.stopPrank();

        // Check supply
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"));

        assertEq(supply, 0);
    }

    function test_getSupplyByCategory_zeroSupply() public {
        // No OHM or gOHM

        // Check supply
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"));

        assertEq(supply, 0);
    }

    function test_getSupplyByCategory_ohmSupply() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Check supply
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"));

        assertEq(supply, 100e9);
    }

    function test_getSupplyByCategory_gOhmSupply() public {
        // Add gOHM in the treasury
        gOhm.mint(address(treasuryAddress), 1e18); // 1 gOHM

        uint256 expectedOhmSupply = uint256(1e18).mulDiv(GOHM_INDEX, 1e18); // 9 decimals

        // Check supply
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"));

        assertEq(supply, expectedOhmSupply);
    }

    function test_getSupplyByCategory_categoryNotApproved_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory("junk")
        );
        vm.expectRevert(err);

        // Get supply
        moduleSupply.getSupplyByCategory(toCategory("junk"));
    }

    function test_getSupplyByCategory_sameTimestamp_usesCache() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Cache the value
        vm.startPrank(writer);
        moduleSupply.storeCategorySupply(toCategory("protocol-owned-treasury"));
        vm.stopPrank();

        // Add more OHM in the treasury (so the cached value will not be correct)
        ohm.mint(address(treasuryAddress), 100e9);

        // Check supply - should use the cached value
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"));
        assertEq(supply, 100e9);
    }

    function test_getSupplyByCategory_sameTimestamp_withoutCache() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Check supply - should work without cached value
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"));
        assertEq(supply, 100e9);
    }

    function test_getSupplyByCategory_differentTimestamp_ignoresCache() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Cache the value
        vm.startPrank(writer);
        moduleSupply.storeCategorySupply(toCategory("protocol-owned-treasury"));
        vm.stopPrank();

        // Add more OHM in the treasury (so the cached value will not be correct)
        ohm.mint(address(treasuryAddress), 100e9);

        // Warp forward 1 second
        vm.warp(block.timestamp + 1);

        // Check supply - should NOT use the cached value
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"));
        assertEq(supply, 200e9);
    }

    function test_getSuppyByCategory_maxAge_categoryNotApproved_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory("junk")
        );
        vm.expectRevert(err);

        // Get supply
        moduleSupply.getSupplyByCategory(toCategory("junk"), 2);
    }

    function test_getSupplyByCategory_maxAge_withinThreshold() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Cache the value
        vm.startPrank(writer);
        moduleSupply.storeCategorySupply(toCategory("protocol-owned-treasury"));
        vm.stopPrank();

        // Add more OHM in the treasury (so the cached value will not be correct)
        ohm.mint(address(treasuryAddress), 100e9);

        // Warp forward 1 second
        vm.warp(block.timestamp + 1);

        // Check supply - should use the cached value
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"), 2);
        assertEq(supply, 100e9);
    }

    function test_getSupplyByCategory_maxAge_withinThreshold_withoutCache() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Warp forward 1 second
        vm.warp(block.timestamp + 1);

        // Check supply - should work without cached value
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"), 2);
        assertEq(supply, 100e9);
    }

    function test_getSupplyByCategory_maxAge_afterThreshold() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Cache the value
        vm.startPrank(writer);
        moduleSupply.storeCategorySupply(toCategory("protocol-owned-treasury"));
        vm.stopPrank();

        // Add more OHM in the treasury (so the cached value will not be correct)
        ohm.mint(address(treasuryAddress), 100e9);

        // Warp forward 3 seconds
        vm.warp(block.timestamp + 3);

        // Check supply - should NOT use the cached value
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"), 2);
        assertEq(supply, 200e9);
    }

    function test_getSupplyByCategory_variant_current_categoryNotApproved_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory("junk")
        );
        vm.expectRevert(err);

        // Get supply
        moduleSupply.getSupplyByCategory(toCategory("junk"), SPPLYv1.Variant.CURRENT);
    }

    function test_getSupplyByCategory_variant_current_withoutCache() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Check supply - should work without cached value
        (uint256 supply, uint48 timestamp) = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"), SPPLYv1.Variant.CURRENT);
        assertEq(supply, 100e9);
        assertEq(timestamp, uint48(block.timestamp));
    }

    function test_getSupplyByCategory_variant_current_withCache() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Cache the value
        vm.startPrank(writer);
        moduleSupply.storeCategorySupply(toCategory("protocol-owned-treasury"));
        vm.stopPrank();

        // Add more OHM in the treasury (so the cached value will not be correct)
        ohm.mint(address(treasuryAddress), 100e9);

        // Check supply - should NOT use the cached value
        (uint256 supply, uint48 timestamp) = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"), SPPLYv1.Variant.CURRENT);
        assertEq(supply, 200e9);
        assertEq(timestamp, uint48(block.timestamp));
    }

    function test_getSupplyByCategory_variant_last_categoryNotApproved_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory("junk")
        );
        vm.expectRevert(err);

        // Get supply
        moduleSupply.getSupplyByCategory(toCategory("junk"), SPPLYv1.Variant.LAST);
    }

    function test_getSupplyByCategory_variant_last_withoutCache() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Check supply - should work without cached value
        (uint256 supply, uint48 timestamp) = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"), SPPLYv1.Variant.LAST);
        assertEq(supply, 0);
        assertEq(timestamp, 0);
    }

    function test_getSupplyByCategory_variant_last_withCache() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Cache the value
        vm.startPrank(writer);
        moduleSupply.storeCategorySupply(toCategory("protocol-owned-treasury"));
        vm.stopPrank();

        // Add more OHM in the treasury (so the cached value will not be correct)
        ohm.mint(address(treasuryAddress), 100e9);

        // Check supply - should use the cached value
        (uint256 supply, uint48 timestamp) = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"), SPPLYv1.Variant.LAST);
        assertEq(supply, 100e9);
        assertEq(timestamp, uint48(block.timestamp));
    }

    function test_getSupplyByCategory_variant_last_laterBlock_withCache() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Cache the value
        vm.startPrank(writer);
        moduleSupply.storeCategorySupply(toCategory("protocol-owned-treasury"));
        vm.stopPrank();

        // Warp forward 1 second
        uint256 previousTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1);

        // Check supply - should use the cached value
        (uint256 supply, uint48 timestamp) = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"), SPPLYv1.Variant.LAST);
        assertEq(supply, 100e9);
        assertEq(timestamp, previousTimestamp);
    }

    function test_getSupplyByCategory_variant_invalid_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_InvalidParams()"
        );
        vm.expectRevert(err);

        // Get supply
        moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"), 2);
    }

    // =========  storeCategorySupply ========= //

    function test_storeCategorySupply_categoryNotApproved_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory("junk")
        );
        vm.expectRevert(err);

        // Store supply
        vm.startPrank(writer);
        moduleSupply.storeCategorySupply(toCategory("junk"));
        vm.stopPrank();
    }

    function test_storeCategorySupply() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Store supply
        vm.startPrank(writer);
        moduleSupply.storeCategorySupply(toCategory("protocol-owned-treasury"));
        vm.stopPrank();

        // Check supply
        (uint256 supply,) = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"), SPPLYv1.Variant.LAST);
        assertEq(supply, 100e9);
    }

    function test_storeCategorySupply_notPermissioned_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);

        // Store supply
        moduleSupply.storeCategorySupply(toCategory("protocol-owned-treasury"));
    }

    // =========  getMetric ========= //

    function _setupMetricLocations() private {
        // Categorise
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory("dao"));
        moduleSupply.categorize(address(polAddress), toCategory("protocol-owned-liquidity"));
        moduleSupply.categorize(address(borrowableOhmAddress), toCategory("protocol-owned-borrowable"));
        vm.stopPrank();

        // Mint OHM into the locations
        ohm.mint(address(treasuryAddress), 100e9);
        ohm.mint(address(daoAddress), 99e9);
        ohm.mint(address(polAddress), 98e9);
        ohm.mint(address(borrowableOhmAddress), 97e9);
    }

    uint256 internal constant TOTAL_OHM = 100e9 + 99e9 + 98e9 + 97e9 + INITIAL_CROSS_CHAIN_SUPPLY;

    function test_getMetric_totalSupply() public {
        _setupMetricLocations();

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.TOTAL_SUPPLY);

        // Total amount of OHM minted, including cross-chain supply
        assertEq(metric, TOTAL_OHM);
    }

    function test_getMetric_totalSupply_zeroSupply() public {
        // Don't populate locations

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.TOTAL_SUPPLY);

        // No OHM minted, just cross-chain supply
        assertEq(metric, INITIAL_CROSS_CHAIN_SUPPLY);
    }

    function test_getMetric_circulatingSupply() public {
        _setupMetricLocations();
        
        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);

        // OHM minted - POT - DAO
        assertEq(metric, TOTAL_OHM - 100e9 - 99e9);
    }

    function test_getMetric_floatingSupply() public {
        _setupMetricLocations();
        
        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);

        // OHM minted - POT - DAO - POL - borrowable
        assertEq(metric, TOTAL_OHM - 100e9 - 99e9 - 98e9 - 97e9);
    }

    function test_getMetric_backedSupply_noSubmodules() public {
        _setupMetricLocations();
        
        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.BACKED_SUPPLY);

        // OHM minted - POT - DAO - POL - borrowable
        assertEq(metric, TOTAL_OHM - 100e9 - 99e9 - 98e9 - 97e9);
    }
}
