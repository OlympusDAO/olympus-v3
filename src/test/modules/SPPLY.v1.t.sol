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
// [ ] addCategory - adds a new category for supply tracking
//  [ ] reverts if caller is not permissioned
//  [ ] reverts if category already approved
//  [ ] reverts if category is empty
//  [ ] stores category in categories array, emits event
// [ ] removeCategory - removes a category from supply tracking
//  [ ] reverts if caller is not permissioned
//  [ ] reverts if category not approved
//  [ ] reverts if category has locations not yet removed
//  [ ] removes category from categories array, emits event
// [ ] categorize - categorizes an OHM location in a category for supply tracking
//  [ ] reverts if caller is not permissioned
//  [ ] reverts if category not approved
//  [ ] location not assigned to category - adds to locations array, adds to categorization mapping, emits event
//  [ ] reverts if location assigned to different category
//  [ ] empty category - removes from locations array, removes from categorization mapping, emits event
// [ ] getLocations - returns array of all locations where supply is tracked
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
