// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
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
// [ ] increaseCrossChainSupply
//  [ ] reverts if caller is not permissioned
//  [ ] increments value, emits event
// [ ] decreaseCrossChainSupply
//  [ ] reverts if caller is not permissioned
//  [ ] decrements value, emits event
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
// [ ] getCategories - returns array of all categories used to track supply
// [ ] getLocationsByCategory - returns array of all locations categorized in a given category
//  [ ] category not approved
//  [ ] no locations in category
//  [ ] returns locations in category
// [ ] getSupplyByCategory - returns the supply of a given category (totaled from across all locations)
//  [ ] supply calculations
//    [ ] no locations in category
//    [X] zero supply
//    [X] OHM supply
//    [X] gOHM supply
//    [ ] cross-chain category supply
//    [ ] uses submodules if enabled
//    [ ] ignores submodules if disabled
//    [ ] reverts upon submodule failure
//  [ ] base function
//    [ ] uses cached value if in the same block
//    [ ] calculates new value
//  [ ] maxAge
//    [ ] within age threshold
//    [ ] after age threshold
//  [ ] variant
//    [ ] category not approved
//    [ ] current variant
//    [ ] last variant
//      [ ] no cached value
//      [ ] cached value
//    [ ] invalid variant
// [ ] storeCategorySupply
//  [ ] reverts if caller is not permissioned
//  [ ] stores supply for category
//  [ ] reverts with an invalid category
//
// Supply Metrics
// [ ] getMetric
//  [ ] metric calculations
//    [ ] totalSupply - returns the total supply of OHM, including cross-chain OHM
//    [ ] circulatingSupply
//    [ ] floatingSupply
//    [ ] collateralizedSupply
//    [ ] backedSupply
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
    address internal treasury;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals
    uint256 internal constant INITIAL_CROSS_CHAIN_SUPPLY = 100e9; // 100 OHM

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
            address[] memory users = userFactory.create(1);
            treasury = users[0];
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
            moduleSupply.categorize(address(treasury), toCategory("protocol-owned-treasury"));
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
        moduleSupply.categorize(address(treasury), toCategory("test"));
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
        moduleSupply.categorize(address(treasury), toCategory("protocol-owned-treasury"));
    }

    function test_categorize_notApproved_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory("junk")
        );
        vm.expectRevert(err);

        // Categorize
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasury), toCategory("junk"));
        vm.stopPrank();
    }

    function test_categorize_locationAssigned_reverts() public {
        // Add the category
        _addCategory("test");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasury), toCategory("test"));
        vm.stopPrank();

        bytes memory err = abi.encodeWithSignature(
            "SPPLY_LocationAlreadyCategorized(address,bytes32)",
            address(treasury),
            toCategory("test")
        );
        vm.expectRevert(err);

        // Categorize
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasury), toCategory("test"));
        vm.stopPrank();
    }

    function test_categorize_locationAssigned_differentCategory_reverts() public {
        // Add the category
        _addCategory("test");
        _addCategory("test2");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasury), toCategory("test"));
        vm.stopPrank();

        bytes memory err = abi.encodeWithSignature(
            "SPPLY_LocationAlreadyCategorized(address,bytes32)",
            address(treasury),
            toCategory("test")
        );
        vm.expectRevert(err);

        // Categorize to a different category
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasury), toCategory("test2"));
        vm.stopPrank();
    }

    function test_categorize() public {
        // Add the category
        _addCategory("test");

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit LocationCategorized(address(treasury), toCategory("test"));

        // Categorize
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasury), toCategory("test"));
        vm.stopPrank();

        // Get the category
        Category category = moduleSupply.getCategoryByLocation(address(treasury));
        assertEq(fromCategory(category), "test");

        // Get the locations and check that it is present
        address[] memory locations = moduleSupply.getLocationsByCategory(toCategory("test"));
        assertEq(locations.length, 1);
        assertEq(locations[0], address(treasury));
    }

    function test_categorize_remove_locationNotAssigned_reverts() public {
        // Add the category
        _addCategory("test");

        bytes memory err = abi.encodeWithSignature(
            "SPPLY_LocationNotCategorized(address)",
            address(treasury)
        );
        vm.expectRevert(err);

        // Remove the location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasury), toCategory(0));
        vm.stopPrank();
    }

    function test_categorize_remove_emptyCategoryString() public {
        // Add the category
        _addCategory("test");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasury), toCategory("test"));
        vm.stopPrank();

        // Remove the location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasury), toCategory(""));
        vm.stopPrank();

        // Check that the location is not contained in the locations array
        bool found = false;
        for (uint256 i = 0; i < moduleSupply.getLocations().length; i++) {
            if (moduleSupply.getLocations()[i] == address(treasury)) {
                found = true;
            }
        }
        assertEq(found, false);

        // Check that the location is not contained in the categorization mapping
        Category category = moduleSupply.getCategoryByLocation(address(treasury));
        assertEq(fromCategory(category), "");
    }

    function test_categorize_remove_emptyCategoryNumber() public {
        // Add the category
        _addCategory("test");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasury), toCategory("test"));
        vm.stopPrank();

        // Remove the location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasury), toCategory(0));
        vm.stopPrank();

        // Check that the location is not contained in the locations array
        bool found = false;
        for (uint256 i = 0; i < moduleSupply.getLocations().length; i++) {
            if (moduleSupply.getLocations()[i] == address(treasury)) {
                found = true;
            }
        }
        assertEq(found, false);

        // Check that the location is not contained in the categorization mapping
        Category category = moduleSupply.getCategoryByLocation(address(treasury));
        assertEq(fromCategory(category), "");
    }

    // =========  getLocations ========= //

    function test_getLocations_zeroLocations() public {
        // Remove the existing location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasury), toCategory(0));
        vm.stopPrank();

        // Get locations
        address[] memory locations = moduleSupply.getLocations();

        assertEq(locations.length, 0);
    }

    function test_getLocations_oneLocation() public {
        // Get locations
        address[] memory locations = moduleSupply.getLocations();

        assertEq(locations.length, 1);
        assertEq(locations[0], address(treasury));
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
        assertEq(locations[0], address(treasury));

        for (uint256 i = 0; i < locationCount; i++) {
            assertEq(locations[i + 1], users[i]);
        }
    }

    // =========  getSupplyByCategory ========= //

    function test_getSupplyByCategory_noLocations() public {
        // Add OHM in the treasury
        ohm.mint(address(treasury), 100e9);

        // Remove the existing location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasury), toCategory(0));
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
        ohm.mint(address(treasury), 100e9);

        // Check supply
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"));

        assertEq(supply, 100e9);
    }

    function test_getSupplyByCategory_gOhmSupply() public {
        // Add gOHM in the treasury
        gOhm.mint(address(treasury), 1e18); // 1 gOHM

        uint256 expectedOhmSupply = uint256(1e18).mulDiv(GOHM_INDEX, 1e18); // 9 decimals

        // Check supply
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"));

        assertEq(supply, expectedOhmSupply);
    }
}
