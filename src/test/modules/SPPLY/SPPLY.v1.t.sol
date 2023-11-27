// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {MockMultiplePoolBalancerVault} from "test/mocks/MockBalancerVault.sol";
import {MockBalancerPool} from "test/modules/SPPLY/submodules/AuraBalancerSupply.t.sol";
import {MockVaultManager} from "test/modules/SPPLY/submodules/BLVaultSupply.t.sol";
import {MockSiloLens, MockBaseSilo} from "test/mocks/MockSilo.sol";

import {OlympusERC20Token} from "src/external/OlympusERC20.sol";

import {FullMath} from "libraries/FullMath.sol";

import "src/modules/SPPLY/OlympusSupply.sol";
import {AuraBalancerSupply} from "src/modules/SPPLY/submodules/AuraBalancerSupply.sol";
import {IBalancerPool} from "src/external/balancer/interfaces/IBalancerPool.sol";
import {IAuraRewardPool} from "src/external/aura/interfaces/IAuraRewardPool.sol";
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
// Supply Categorization
// [X] addCategory - adds a new category for supply tracking
//  [X] reverts if caller is not permissioned
//  [X] reverts if category already approved
//  [X] reverts if category is empty
//  [X] reverts if an incorrect submodules selector is provided
//  [X] reverts if an incorrect submodules reserves selector is provided
//  [X] reverts if a submodules selector is provided when disabled
//  [X] reverts if a submodules reserves selector is provided when disabled
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
// [X] getSupplyByCategory - returns the supply of a given category (totaled from across all locations)
//  [X] supply calculations
//    [X] no locations in category
//    [X] zero supply
//    [X] OHM supply
//    [X] gOHM supply
//    [X] uses submodules if enabled
//    [X] ignores submodules if disabled
//    [X] reverts upon submodule failure
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
// [X] getMetric
//  [X] metric calculations
//    [X] totalSupply - returns the total supply of OHM, including cross-chain OHM
//    [X] circulatingSupply
//     [X] no submodules
//     [X] with submodules, with values
//    [X] floatingSupply
//     [X] no submodules
//     [X] with submodules, no values
//     [X] with submodules, with values
//     [X] with submodules, reverts upon failure
//    [X] collateralizedSupply
//     [X] no submodules
//     [X] with submodules, no values
//     [X] with submodules, with values
//     [X] with submodules, reverts upon failure
//    [X] backedSupply
//     [X] no submodules
//     [X] with submodules, no values
//     [X] with submodules, with values
//     [X] with submodules, reverts upon failure
//  [X] base function
//    [X] uses cached value if in the same block
//    [X] calculates new value
//    [X] invalid metric
//  [X] maxAge
//    [X] within age threshold
//    [X] within age threshold, no cache
//    [X] after age threshold
//    [X] invalid metric
//  [X] variant
//    [X] invalid metric
//    [X] current variant
//      [X] no cached value
//      [X] ignores cached value
//    [X] last variant
//      [X] no cached value
//      [X] cached value
//    [X] invalid variant
// [X] storeMetric
//  [X] reverts if caller is not permissioned
//  [X] stores metric
//  [X] reverts with an invalid metric

contract SupplyTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusSupply;

    MockERC20 internal ohm;
    MockGohm internal gohm;

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
    uint256 internal constant CATEGORIES_RESERVES_DEFAULT_COUNT = 1;

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
            gohm = new MockGohm(GOHM_INDEX);
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
            address[2] memory tokens = [address(ohm), address(gohm)];
            moduleSupply = new OlympusSupply(kernel, tokens, INITIAL_CROSS_CHAIN_SUPPLY);

            // Deploy mock module writer
            writer = moduleSupply.generateGodmodeFixture(type(OlympusSupply).name);
        }

        // Initialize
        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(moduleSupply));
            kernel.executeAction(Actions.ActivatePolicy, address(writer));
        }

        // Locations
        {
            vm.startPrank(writer);
            moduleSupply.categorize(
                address(treasuryAddress),
                toCategory("protocol-owned-treasury")
            );
            vm.stopPrank();
        }
    }

    uint256 internal constant BALANCER_POOL_DAI_BALANCE = 100e18; // 100 DAI
    uint256 internal constant BALANCER_POOL_OHM_BALANCE = 100e9; // 100 OHM
    uint256 internal constant BALANCER_POOL_TOTAL_SUPPLY = 100e18; // 100 LP
    uint256 internal constant BPT_BALANCE = 1e18;

    uint256 internal constant BLV_POOL_SHARE = 1000e9;

    uint256 internal constant LENS_TOTAL_DEPOSITS = 10e9;
    uint256 internal constant LENS_BORROW_AMOUNT = 2e9;
    uint256 internal constant LENS_SUPPLIED_AMOUNT = 5e9;

    function _setUpSubmodules() public {
        // AuraBalancerSupply setup
        {
            MockERC20 dai = new MockERC20("DAI", "DAI", 18);
            MockMultiplePoolBalancerVault balancerVault = new MockMultiplePoolBalancerVault();
            bytes32 poolId = "hello";

            address[] memory balancerPoolTokens = new address[](2);
            balancerPoolTokens[0] = address(dai);
            balancerPoolTokens[1] = address(ohm);
            balancerVault.setTokens(poolId, balancerPoolTokens);

            uint256[] memory balancerPoolBalances = new uint256[](2);
            balancerPoolBalances[0] = BALANCER_POOL_DAI_BALANCE;
            balancerPoolBalances[1] = BALANCER_POOL_OHM_BALANCE;
            balancerVault.setBalances(poolId, balancerPoolBalances);

            // Mint the OHM in the pool
            ohm.mint(address(balancerVault), BALANCER_POOL_OHM_BALANCE);

            MockBalancerPool balancerPool = new MockBalancerPool(poolId);
            balancerPool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);
            balancerPool.setBalance(BPT_BALANCE); // balance for polAddress

            AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](1);
            pools[0] = AuraBalancerSupply.Pool(
                IBalancerPool(balancerPool),
                IAuraRewardPool(address(0))
            );

            submoduleAuraBalancerSupply = new AuraBalancerSupply(
                moduleSupply,
                polAddress,
                address(balancerVault),
                pools
            );
        }

        // BLVaultSupply setup
        {
            MockVaultManager vaultManager = new MockVaultManager(BLV_POOL_SHARE);
            address[] memory vaultManagers = new address[](1);
            vaultManagers[0] = address(vaultManager);

            // Mint the OHM in the BLV
            ohm.mint(address(vaultManager), BLV_POOL_SHARE);

            submoduleBLVaultSupply = new BLVaultSupply(moduleSupply, vaultManagers);
        }

        // Deploy submodules
        {
            MockSiloLens siloLens = new MockSiloLens();
            siloLens.setTotalDepositsWithInterest(LENS_TOTAL_DEPOSITS);
            siloLens.setTotalBorrowAmountWithInterest(LENS_BORROW_AMOUNT);
            siloLens.setBalanceOfUnderlying(LENS_SUPPLIED_AMOUNT);

            // Mint the OHM in the Silo
            ohm.mint(address(siloLens), LENS_SUPPLIED_AMOUNT);

            MockBaseSilo siloBase = new MockBaseSilo();
            siloBase.setCollateralToken(0x907136B74abA7D5978341eBA903544134A66B065);

            address[] memory users = userFactory.create(1);
            address siloAmo = users[0];

            submoduleSiloSupply = new SiloSupply(
                moduleSupply,
                siloAmo,
                address(siloLens),
                address(siloBase)
            );
        }

        // Install submodules
        {
            vm.startPrank(writer);
            moduleSupply.installSubmodule(submoduleAuraBalancerSupply);
            moduleSupply.installSubmodule(submoduleBLVaultSupply);
            moduleSupply.installSubmodule(submoduleSiloSupply);
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

        moduleSupply.addCategory(toCategory("test"), false, bytes4(0), bytes4(0));
    }

    function test_addCategory_alreadyApproved_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryAlreadyApproved(bytes32)",
            toCategory("protocol-owned-treasury")
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(
            toCategory("protocol-owned-treasury"),
            false,
            bytes4(0),
            bytes4(0)
        );
        vm.stopPrank();
    }

    function test_addCategory_emptyStringName_reverts() public {
        bytes memory err = abi.encodeWithSignature("SPPLY_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory(""), false, bytes4(0), bytes4(0));
        vm.stopPrank();
    }

    function test_addCategory_emptyName_reverts() public {
        bytes memory err = abi.encodeWithSignature("SPPLY_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory(0), false, bytes4(0), bytes4(0));
        vm.stopPrank();
    }

    function test_addCategory_emptyStringSubmoduleMetricSelector_reverts() public {
        bytes memory err = abi.encodeWithSignature("SPPLY_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(
            toCategory("test"),
            true,
            bytes4(""),
            SupplySubmodule.getProtocolOwnedLiquidityReserves.selector
        );
        vm.stopPrank();
    }

    function test_addCategory_emptySubmoduleMetricSelector_reverts() public {
        bytes memory err = abi.encodeWithSignature("SPPLY_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(
            toCategory("test"),
            true,
            bytes4(0),
            SupplySubmodule.getProtocolOwnedLiquidityReserves.selector
        );
        vm.stopPrank();
    }

    function test_addCategory_invalidSubmoduleMetricSelector_reverts() public {
        bytes memory err = abi.encodeWithSignature("SPPLY_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(
            toCategory("test"),
            true,
            SupplySubmodule.getProtocolOwnedLiquidityReserves.selector,
            SupplySubmodule.getProtocolOwnedLiquidityReserves.selector
        );
        vm.stopPrank();
    }

    function test_addCategory_emptyStringSubmoduleReservesSelector() public {
        vm.startPrank(writer);
        moduleSupply.addCategory(
            toCategory("test"),
            true,
            SupplySubmodule.getCollateralizedOhm.selector,
            bytes4("")
        );
        vm.stopPrank();

        // Check that the category is contained in the categoryData mapping
        SPPLYv1.CategoryData memory categoryData = moduleSupply.getCategoryData(toCategory("test"));
        assertEq(categoryData.approved, true);
        assertEq(categoryData.useSubmodules, true);
        assertEq(
            categoryData.submoduleMetricSelector,
            SupplySubmodule.getCollateralizedOhm.selector
        );
        assertEq(categoryData.submoduleReservesSelector, bytes4(0)); // submoduleReservesSelector is optional
    }

    function test_addCategory_emptySubmoduleReservesSelector() public {
        vm.startPrank(writer);
        moduleSupply.addCategory(
            toCategory("test"),
            true,
            SupplySubmodule.getCollateralizedOhm.selector,
            bytes4(0)
        );
        vm.stopPrank();

        // Check that the category is contained in the categoryData mapping
        SPPLYv1.CategoryData memory categoryData = moduleSupply.getCategoryData(toCategory("test"));
        assertEq(categoryData.approved, true);
        assertEq(categoryData.useSubmodules, true);
        assertEq(
            categoryData.submoduleMetricSelector,
            SupplySubmodule.getCollateralizedOhm.selector
        );
        assertEq(categoryData.submoduleReservesSelector, bytes4(0)); // submoduleReservesSelector is optional
    }

    function test_addCategory_invalidSubmoduleReservesSelector_reverts() public {
        bytes memory err = abi.encodeWithSignature("SPPLY_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(
            toCategory("test"),
            true,
            SupplySubmodule.getCollateralizedOhm.selector,
            SupplySubmodule.getCollateralizedOhm.selector
        );
        vm.stopPrank();
    }

    function test_addCategory_submodulesDisabled_withSubmoduleMetricSelector_reverts() public {
        bytes memory err = abi.encodeWithSignature("SPPLY_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(
            toCategory("test"),
            false,
            SupplySubmodule.getCollateralizedOhm.selector,
            bytes4(0)
        );
        vm.startPrank(writer);
    }

    function test_addCategory_submodulesDisabled_withSubmoduleReservesSelector_reverts() public {
        bytes memory err = abi.encodeWithSignature("SPPLY_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(writer);
        moduleSupply.addCategory(
            toCategory("test"),
            false,
            bytes4(0),
            SupplySubmodule.getProtocolOwnedLiquidityReserves.selector
        );
        vm.startPrank(writer);
    }

    function test_addCategory() public {
        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit CategoryAdded(toCategory("test"));

        // Add category
        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory("test"), false, bytes4(0), bytes4(0));
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
        assertEq(categoryData.submoduleMetricSelector, bytes4(0));
        assertEq(categoryData.submoduleReservesSelector, bytes4(0));
    }

    function test_addCategory_withSubmodules() public {
        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit CategoryAdded(toCategory("test"));

        // Add category
        vm.startPrank(writer);
        moduleSupply.addCategory(
            toCategory("test"),
            true,
            SupplySubmodule.getCollateralizedOhm.selector,
            SupplySubmodule.getProtocolOwnedLiquidityReserves.selector
        );
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
        assertEq(
            categoryData.submoduleMetricSelector,
            SupplySubmodule.getCollateralizedOhm.selector
        );
        assertEq(
            categoryData.submoduleReservesSelector,
            SupplySubmodule.getProtocolOwnedLiquidityReserves.selector
        );
    }

    // =========  removeCategory ========= //

    function _addCategory(bytes32 name_) internal {
        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory(name_), false, bytes4(0), bytes4(0));
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

    function test_removeCategory_emptyString_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory("")
        );
        vm.expectRevert(err);

        // Remove the category
        vm.startPrank(writer);
        moduleSupply.removeCategory(toCategory(""));
        vm.stopPrank();
    }

    function test_removeCategory_zeroCategory_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory(0)
        );
        vm.expectRevert(err);

        // Remove the category
        vm.startPrank(writer);
        moduleSupply.removeCategory(toCategory(0));
        vm.stopPrank();
    }

    function test_removeCategory_existingLocations_reverts() public {
        // Add the category
        _addCategory("test");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory("test"));
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

        // Expect a revert when trying to get the category data
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory("test")
        );
        vm.expectRevert(err);

        moduleSupply.getCategoryData(toCategory("test"));
    }

    // =========  categorize ========= //

    function test_categorize_notPermissioned_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);

        // Categorize
        moduleSupply.categorize(address(daoAddress), toCategory("protocol-owned-treasury"));
    }

    function test_categorize_notApproved_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory("junk")
        );
        vm.expectRevert(err);

        // Categorize
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory("junk"));
        vm.stopPrank();
    }

    function test_categorize_locationAssigned_reverts() public {
        // Add the category
        _addCategory("test");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory("test"));
        vm.stopPrank();

        bytes memory err = abi.encodeWithSignature(
            "SPPLY_LocationAlreadyCategorized(address,bytes32)",
            address(daoAddress),
            toCategory("test")
        );
        vm.expectRevert(err);

        // Categorize
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory("test"));
        vm.stopPrank();
    }

    function test_categorize_locationAssigned_differentCategory_reverts() public {
        // Add the category
        _addCategory("test");
        _addCategory("test2");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory("test"));
        vm.stopPrank();

        bytes memory err = abi.encodeWithSignature(
            "SPPLY_LocationAlreadyCategorized(address,bytes32)",
            address(daoAddress),
            toCategory("test")
        );
        vm.expectRevert(err);

        // Categorize to a different category
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory("test2"));
        vm.stopPrank();
    }

    function test_categorize() public {
        // Add the category
        _addCategory("test");

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit LocationCategorized(address(daoAddress), toCategory("test"));

        // Categorize
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory("test"));
        vm.stopPrank();

        // Get the category
        Category category = moduleSupply.getCategoryByLocation(address(daoAddress));
        assertEq(fromCategory(category), "test");

        // Get the locations and check that it is present
        address[] memory locations = moduleSupply.getLocationsByCategory(toCategory("test"));
        assertEq(locations.length, 1);
        assertEq(locations[0], address(daoAddress));
    }

    function test_categorize_remove_locationNotAssigned_reverts() public {
        // Add the category
        _addCategory("test");

        bytes memory err = abi.encodeWithSignature(
            "SPPLY_LocationNotCategorized(address)",
            address(daoAddress)
        );
        vm.expectRevert(err);

        // Remove the location
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory(0));
        vm.stopPrank();
    }

    function test_categorize_remove_emptyCategoryString() public {
        // Add the category
        _addCategory("test");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory("test"));
        vm.stopPrank();

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit LocationCategorized(address(daoAddress), toCategory(""));

        // Remove the location
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory(""));
        vm.stopPrank();

        // Check that the location is not contained in the locations array
        bool found = false;
        for (uint256 i = 0; i < moduleSupply.getLocations().length; i++) {
            if (moduleSupply.getLocations()[i] == address(daoAddress)) {
                found = true;
            }
        }
        assertEq(found, false);

        // Check that the location is not contained in the categorization mapping
        Category category = moduleSupply.getCategoryByLocation(address(daoAddress));
        assertEq(fromCategory(category), "");
    }

    function test_categorize_remove_emptyCategoryNumber() public {
        // Add the category
        _addCategory("test");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory("test"));
        vm.stopPrank();

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit LocationCategorized(address(daoAddress), toCategory(0));

        // Remove the location
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory(0));
        vm.stopPrank();

        // Check that the location is not contained in the locations array
        bool found = false;
        for (uint256 i = 0; i < moduleSupply.getLocations().length; i++) {
            if (moduleSupply.getLocations()[i] == address(daoAddress)) {
                found = true;
            }
        }
        assertEq(found, false);

        // Check that the location is not contained in the categorization mapping
        Category category = moduleSupply.getCategoryByLocation(address(daoAddress));
        assertEq(fromCategory(category), "");
    }

    function test_categorize_remove_noCategorization() public {
        // Add the category
        _addCategory("test");

        // Add a location
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory("test"));
        vm.stopPrank();

        // Remove the location
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory(0));
        vm.stopPrank();

        // Expect an error to be thrown
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_LocationNotCategorized(address)",
            address(daoAddress)
        );
        vm.expectRevert(err);

        // Remove the location again
        vm.startPrank(writer);
        moduleSupply.categorize(address(daoAddress), toCategory(0));
        vm.stopPrank();
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
            moduleSupply.addCategory(
                toCategory(bytes32(bytes(categoryNames[i]))),
                false,
                bytes4(0),
                bytes4(0)
            );
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
            assertEq(
                fromCategory(categories[i + CATEGORIES_DEFAULT_COUNT]),
                bytes32(bytes(categoryNames[i]))
            );
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
        assertEq(categoryData.submoduleMetricSelector, bytes4(0));
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
        address[] memory locations = moduleSupply.getLocationsByCategory(
            toCategory("protocol-owned-treasury")
        );

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
        address[] memory locations = moduleSupply.getLocationsByCategory(
            toCategory("protocol-owned-treasury")
        );

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
        gohm.mint(address(treasuryAddress), 1e18); // 1 gOHM

        uint256 expectedOhmSupply = uint256(1e18).mulDiv(GOHM_INDEX, 1e18); // 9 decimals

        // Check supply
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-treasury"));

        assertEq(supply, expectedOhmSupply);
    }

    function test_getSupplyByCategory_submodules_pobo() public {
        _setUpSubmodules();

        // Add OHM/gOHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);
        gohm.mint(address(treasuryAddress), 1e18); // 1 gOHM

        // Categories already defined

        uint256 expected = LENS_SUPPLIED_AMOUNT - LENS_BORROW_AMOUNT;

        // Check supply
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-borrowable"));
        assertEq(supply, expected);
    }

    function test_getSupplyByCategory_submodules_polo() public {
        _setUpSubmodules();

        // Add OHM/gOHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);
        gohm.mint(address(treasuryAddress), 1e18); // 1 gOHM

        // Categories already defined

        uint256 expected = BPT_BALANCE.mulDiv(
            BALANCER_POOL_OHM_BALANCE,
            BALANCER_POOL_TOTAL_SUPPLY
        );

        // Check supply
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("protocol-owned-liquidity"));
        assertEq(supply, expected);
    }

    function test_getSupplyByCategory_submodules_collateralized() public {
        _setUpSubmodules();

        // Add OHM/gOHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);
        gohm.mint(address(treasuryAddress), 1e18); // 1 gOHM

        // Define category for collateralized OHM
        vm.startPrank(writer);
        moduleSupply.addCategory(
            toCategory("collateralized-ohm"),
            true,
            SupplySubmodule.getCollateralizedOhm.selector,
            bytes4(0)
        );
        vm.stopPrank();

        uint256 expected = BLV_POOL_SHARE + LENS_BORROW_AMOUNT;

        // Check supply
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("collateralized-ohm"));
        assertEq(supply, expected);
    }

    function test_getSupplyByCategory_submodules_disabled() public {
        _setUpSubmodules();

        // Add OHM/gOHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);
        gohm.mint(address(treasuryAddress), 1e18); // 1 gOHM

        // Define a new category with submodules disabled
        vm.startPrank(writer);
        moduleSupply.addCategory(toCategory("test"), false, bytes4(0), bytes4(0));
        vm.stopPrank();

        uint256 expected = 0;

        // Check supply
        uint256 supply = moduleSupply.getSupplyByCategory(toCategory("test"));
        assertEq(supply, expected);
    }

    function test_getSupplyByCategory_submoduleFailure() public {
        // Set up a submodule
        {
            MockVaultManager vaultManager = new MockVaultManager(BLV_POOL_SHARE);
            vaultManager.setPoolOhmShareReverts(true);

            address[] memory vaultManagers = new address[](1);
            vaultManagers[0] = address(vaultManager);

            submoduleBLVaultSupply = new BLVaultSupply(moduleSupply, vaultManagers);

            vm.startPrank(writer);
            moduleSupply.installSubmodule(submoduleBLVaultSupply);
            vm.stopPrank();
        }

        // Add OHM/gOHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);
        gohm.mint(address(treasuryAddress), 1e18); // 1 gOHM

        // Define category for collateralized OHM
        vm.startPrank(writer);
        moduleSupply.addCategory(
            toCategory("collateralized-ohm"),
            true,
            SupplySubmodule.getCollateralizedOhm.selector,
            bytes4(0)
        );
        vm.stopPrank();

        // Expect revert
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_SubmoduleFailed(address,bytes4)",
            address(submoduleBLVaultSupply),
            SupplySubmodule.getCollateralizedOhm.selector
        );
        vm.expectRevert(err);

        // Check supply
        moduleSupply.getSupplyByCategory(toCategory("collateralized-ohm"));
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
        (uint256 supply, uint48 timestamp) = moduleSupply.getSupplyByCategory(
            toCategory("protocol-owned-treasury"),
            SPPLYv1.Variant.CURRENT
        );
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
        (uint256 supply, uint48 timestamp) = moduleSupply.getSupplyByCategory(
            toCategory("protocol-owned-treasury"),
            SPPLYv1.Variant.CURRENT
        );
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

        // Check supply - should not return a value
        (uint256 supply, uint48 timestamp) = moduleSupply.getSupplyByCategory(
            toCategory("protocol-owned-treasury"),
            SPPLYv1.Variant.LAST
        );
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
        (uint256 supply, uint48 timestamp) = moduleSupply.getSupplyByCategory(
            toCategory("protocol-owned-treasury"),
            SPPLYv1.Variant.LAST
        );
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
        (uint256 supply, uint48 timestamp) = moduleSupply.getSupplyByCategory(
            toCategory("protocol-owned-treasury"),
            SPPLYv1.Variant.LAST
        );
        assertEq(supply, 100e9);
        assertEq(timestamp, previousTimestamp);
    }

    function test_getSupplyByCategory_variant_invalid_reverts() public {
        bytes memory err = abi.encodeWithSignature("SPPLY_InvalidParams()");
        vm.expectRevert(err);

        // Get supply
        (bool result, ) = address(moduleSupply).call(
            abi.encodeWithSignature(
                "getSupplyByCategory(bytes32,uint8)",
                toCategory("protocol-owned-treasury"),
                2
            )
        );
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
        (uint256 supply, ) = moduleSupply.getSupplyByCategory(
            toCategory("protocol-owned-treasury"),
            SPPLYv1.Variant.LAST
        );
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
        moduleSupply.categorize(
            address(borrowableOhmAddress),
            toCategory("protocol-owned-borrowable")
        );
        vm.stopPrank();

        // Mint OHM into the locations
        ohm.mint(address(treasuryAddress), 100e9);
        ohm.mint(address(daoAddress), 99e9);
        ohm.mint(address(polAddress), 98e9);
        ohm.mint(address(borrowableOhmAddress), 97e9);
    }

    uint256 internal constant TOTAL_OHM = 100e9 + 99e9 + 98e9 + 97e9 + INITIAL_CROSS_CHAIN_SUPPLY;

    /// @dev    Returns the total amount of OHM minted, including cross-chain supply.
    ///         This is useful when using submodules that will have minted OHM.
    function _totalOhm() internal view returns (uint256) {
        return ohm.totalSupply() + INITIAL_CROSS_CHAIN_SUPPLY;
    }

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

    function test_getMetric_circulatingSupply_noSubmodules() public {
        _setupMetricLocations();

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);

        // OHM minted - POT - DAO
        assertEq(metric, TOTAL_OHM - 100e9 - 99e9);
    }

    function test_getMetric_circulatingSupply() public {
        _setupMetricLocations();
        _setUpSubmodules();

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);

        // OHM minted - POT - DAO
        // The "protocol-owned-treasury" and "dao" categories do not have submodules enabled
        assertEq(metric, _totalOhm() - 100e9 - 99e9);
    }

    function test_getMetric_floatingSupply_noSubmodules() public {
        _setupMetricLocations();

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.FLOATING_SUPPLY);

        // OHM minted - POT - DAO - POL - borrowable
        assertEq(metric, TOTAL_OHM - 100e9 - 99e9 - 98e9 - 97e9);
    }

    function test_getMetric_floatingSupply() public {
        _setupMetricLocations();
        _setUpSubmodules();

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.FLOATING_SUPPLY);

        // OHM minted - POT - DAO - POL - borrowable
        assertEq(
            metric,
            _totalOhm() -
                100e9 -
                99e9 -
                98e9 -
                97e9 -
                (submoduleSiloSupply.getProtocolOwnedLiquidityOhm() +
                    submoduleAuraBalancerSupply.getProtocolOwnedLiquidityOhm() +
                    submoduleBLVaultSupply.getProtocolOwnedLiquidityOhm()) -
                (submoduleSiloSupply.getProtocolOwnedBorrowableOhm() +
                    submoduleAuraBalancerSupply.getProtocolOwnedBorrowableOhm() +
                    submoduleBLVaultSupply.getProtocolOwnedBorrowableOhm())
        );
    }

    function test_getMetric_floatingSupply_silo_borrowableZero() public {
        _setupMetricLocations();

        // Set up submodules
        {
            {
                MockSiloLens siloLens = new MockSiloLens();
                siloLens.setTotalDepositsWithInterest(LENS_TOTAL_DEPOSITS);
                siloLens.setTotalBorrowAmountWithInterest(LENS_SUPPLIED_AMOUNT + 1); // POBO = 0
                siloLens.setBalanceOfUnderlying(LENS_SUPPLIED_AMOUNT);

                // Mint the OHM for the silo
                ohm.mint(address(siloLens), LENS_SUPPLIED_AMOUNT);

                MockBaseSilo siloBase = new MockBaseSilo();
                siloBase.setCollateralToken(0x907136B74abA7D5978341eBA903544134A66B065);

                address[] memory users = userFactory.create(1);
                address siloAmo = users[0];

                submoduleSiloSupply = new SiloSupply(
                    moduleSupply,
                    siloAmo,
                    address(siloLens),
                    address(siloBase)
                );
            }

            // Install submodules
            {
                vm.startPrank(writer);
                moduleSupply.installSubmodule(submoduleSiloSupply);
                vm.stopPrank();
            }
        }

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.FLOATING_SUPPLY);

        // OHM minted - POT - DAO - POL - borrowable
        assertEq(
            metric,
            _totalOhm() -
                100e9 -
                99e9 -
                98e9 -
                97e9 -
                submoduleSiloSupply.getProtocolOwnedLiquidityOhm() -
                submoduleSiloSupply.getProtocolOwnedBorrowableOhm()
        );
    }

    function test_getMetric_floatingSupply_submoduleError_reverts() public {
        _setupMetricLocations();

        // Set up submodules
        {
            MockSiloLens siloLens = new MockSiloLens();
            siloLens.setTotalDepositsWithInterest(LENS_TOTAL_DEPOSITS);
            siloLens.setTotalBorrowAmountWithInterest(LENS_BORROW_AMOUNT);
            siloLens.setBalanceOfUnderlying(LENS_SUPPLIED_AMOUNT);
            siloLens.setBalanceOfUnderlyingReverts(true);

            MockBaseSilo siloBase = new MockBaseSilo();
            siloBase.setCollateralToken(0x907136B74abA7D5978341eBA903544134A66B065);

            address[] memory users = userFactory.create(1);
            address siloAmo = users[0];

            submoduleSiloSupply = new SiloSupply(
                moduleSupply,
                siloAmo,
                address(siloLens),
                address(siloBase)
            );

            vm.startPrank(writer);
            moduleSupply.installSubmodule(submoduleSiloSupply);
            vm.stopPrank();
        }

        // Expect revert
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_SubmoduleFailed(address,bytes4)",
            address(submoduleSiloSupply),
            SupplySubmodule.getProtocolOwnedBorrowableOhm.selector
        );
        vm.expectRevert(err);

        // Get metric
        moduleSupply.getMetric(SPPLYv1.Metric.FLOATING_SUPPLY);
    }

    function test_getMetric_backedSupply_noSubmodules() public {
        _setupMetricLocations();

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.BACKED_SUPPLY);

        // OHM minted - POT - DAO - POL - borrowable
        assertEq(metric, TOTAL_OHM - 100e9 - 99e9 - 98e9 - 97e9);
    }

    function test_getMetric_backedSupply() public {
        _setupMetricLocations();
        _setUpSubmodules();

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.BACKED_SUPPLY);

        // OHM minted - POT - DAO - POL - borrowable - collateralized
        assertEq(
            metric,
            _totalOhm() -
                100e9 -
                99e9 -
                98e9 -
                97e9 -
                (submoduleSiloSupply.getProtocolOwnedLiquidityOhm() +
                    submoduleAuraBalancerSupply.getProtocolOwnedLiquidityOhm() +
                    submoduleBLVaultSupply.getProtocolOwnedLiquidityOhm()) -
                (submoduleSiloSupply.getProtocolOwnedBorrowableOhm() +
                    submoduleAuraBalancerSupply.getProtocolOwnedBorrowableOhm() +
                    submoduleBLVaultSupply.getProtocolOwnedBorrowableOhm()) -
                (submoduleSiloSupply.getCollateralizedOhm() +
                    submoduleAuraBalancerSupply.getCollateralizedOhm() +
                    submoduleBLVaultSupply.getCollateralizedOhm())
        );
    }

    function test_getMetric_backedSupply_silo_collateralizedZero() public {
        _setupMetricLocations();

        // Set up submodules
        {
            {
                MockSiloLens siloLens = new MockSiloLens();
                siloLens.setTotalDepositsWithInterest(LENS_TOTAL_DEPOSITS);
                siloLens.setTotalBorrowAmountWithInterest(0); // Collateralized OHM = 0
                siloLens.setBalanceOfUnderlying(LENS_SUPPLIED_AMOUNT);

                // Mint the OHM for the silo
                ohm.mint(address(siloLens), LENS_SUPPLIED_AMOUNT);

                MockBaseSilo siloBase = new MockBaseSilo();
                siloBase.setCollateralToken(0x907136B74abA7D5978341eBA903544134A66B065);

                address[] memory users = userFactory.create(1);
                address siloAmo = users[0];

                submoduleSiloSupply = new SiloSupply(
                    moduleSupply,
                    siloAmo,
                    address(siloLens),
                    address(siloBase)
                );
            }

            // Install submodules
            {
                vm.startPrank(writer);
                moduleSupply.installSubmodule(submoduleSiloSupply);
                vm.stopPrank();
            }
        }

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.BACKED_SUPPLY);

        // OHM minted - POT - DAO - POL - borrowable
        assertEq(
            metric,
            _totalOhm() -
                100e9 -
                99e9 -
                98e9 -
                97e9 -
                submoduleSiloSupply.getProtocolOwnedLiquidityOhm() -
                submoduleSiloSupply.getProtocolOwnedBorrowableOhm()
        );
    }

    function test_getMetric_backedSupply_submoduleError_reverts() public {
        _setupMetricLocations();

        // Set up submodules
        {
            MockVaultManager vaultManager = new MockVaultManager(BLV_POOL_SHARE);
            vaultManager.setPoolOhmShareReverts(true);

            address[] memory vaultManagers = new address[](1);
            vaultManagers[0] = address(vaultManager);

            submoduleBLVaultSupply = new BLVaultSupply(moduleSupply, vaultManagers);

            vm.startPrank(writer);
            moduleSupply.installSubmodule(submoduleBLVaultSupply);
            vm.stopPrank();
        }

        // Expect revert
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_SubmoduleFailed(address,bytes4)",
            address(submoduleBLVaultSupply),
            SupplySubmodule.getCollateralizedOhm.selector
        );
        vm.expectRevert(err);

        // Get metric
        moduleSupply.getMetric(SPPLYv1.Metric.BACKED_SUPPLY);
    }

    function test_getMetric_collateralizedSupply_noSubmodules() public {
        _setupMetricLocations();

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.COLLATERALIZED_SUPPLY);

        // collateralized only
        assertEq(metric, 0);
    }

    function test_getMetric_collateralizedSupply() public {
        _setupMetricLocations();
        _setUpSubmodules();

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.COLLATERALIZED_SUPPLY);

        // collateralized only
        assertEq(
            metric,
            (submoduleSiloSupply.getCollateralizedOhm() +
                submoduleAuraBalancerSupply.getCollateralizedOhm() +
                submoduleBLVaultSupply.getCollateralizedOhm())
        );
    }

    function test_getMetric_collateralizedSupply_silo_collateralizedZero() public {
        _setupMetricLocations();

        // Set up submodules
        {
            {
                MockSiloLens siloLens = new MockSiloLens();
                siloLens.setTotalDepositsWithInterest(LENS_TOTAL_DEPOSITS);
                siloLens.setTotalBorrowAmountWithInterest(0); // Collateralized OHM = 0
                siloLens.setBalanceOfUnderlying(LENS_SUPPLIED_AMOUNT);

                // Mint the OHM for the silo
                ohm.mint(address(siloLens), LENS_SUPPLIED_AMOUNT);

                MockBaseSilo siloBase = new MockBaseSilo();
                siloBase.setCollateralToken(0x907136B74abA7D5978341eBA903544134A66B065);

                address[] memory users = userFactory.create(1);
                address siloAmo = users[0];

                submoduleSiloSupply = new SiloSupply(
                    moduleSupply,
                    siloAmo,
                    address(siloLens),
                    address(siloBase)
                );
            }

            // Install submodules
            {
                vm.startPrank(writer);
                moduleSupply.installSubmodule(submoduleSiloSupply);
                vm.stopPrank();
            }
        }

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.COLLATERALIZED_SUPPLY);

        // collateralized only
        assertEq(metric, 0);
    }

    function test_getMetric_collateralizedSupply_submoduleError_reverts() public {
        _setupMetricLocations();

        // Set up submodules
        {
            MockSiloLens siloLens = new MockSiloLens();
            siloLens.setTotalDepositsWithInterest(LENS_TOTAL_DEPOSITS);
            siloLens.setTotalBorrowAmountWithInterest(LENS_BORROW_AMOUNT);
            siloLens.setBalanceOfUnderlying(LENS_SUPPLIED_AMOUNT);
            siloLens.setBalanceOfUnderlyingReverts(true);

            MockBaseSilo siloBase = new MockBaseSilo();
            siloBase.setCollateralToken(0x907136B74abA7D5978341eBA903544134A66B065);

            address[] memory users = userFactory.create(1);
            address siloAmo = users[0];

            submoduleSiloSupply = new SiloSupply(
                moduleSupply,
                siloAmo,
                address(siloLens),
                address(siloBase)
            );

            vm.startPrank(writer);
            moduleSupply.installSubmodule(submoduleSiloSupply);
            vm.stopPrank();
        }

        // Expect revert
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_SubmoduleFailed(address,bytes4)",
            address(submoduleSiloSupply),
            SupplySubmodule.getCollateralizedOhm.selector
        );
        vm.expectRevert(err);

        // Get metric
        moduleSupply.getMetric(SPPLYv1.Metric.COLLATERALIZED_SUPPLY);
    }

    function test_getMetric_invalidMetric_reverts() public {
        bytes memory err = abi.encodeWithSignature("SPPLY_InvalidParams()");
        vm.expectRevert(err);

        // Get metric
        (bool result, ) = address(moduleSupply).call(
            abi.encodeWithSignature("getMetric(uint8)", 99)
        );
    }

    function test_getMetric_sameTimestamp_usesCache() public {
        _setupMetricLocations();

        // Store the metric value
        vm.startPrank(writer);
        moduleSupply.storeMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);
        vm.stopPrank();

        // Mint more OHM (so the cached value is incorrect)
        ohm.mint(address(treasuryAddress), 100e9);

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);

        // Should use the cached value
        assertEq(metric, TOTAL_OHM - 100e9 - 99e9);
    }

    function test_getMetric_sameTimestamp_withoutCache() public {
        _setupMetricLocations();

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);

        // Should return a value
        assertEq(metric, TOTAL_OHM - 100e9 - 99e9);
    }

    function test_getMetric_differentTimestamp_ignoresCache() public {
        _setupMetricLocations();

        // Store the metric value
        vm.startPrank(writer);
        moduleSupply.storeMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);
        vm.stopPrank();

        // Mint more OHM (so the cached value is incorrect)
        ohm.mint(address(treasuryAddress), 100e9);

        // Warp forward 1 second
        vm.warp(block.timestamp + 1);

        // Get metric - should NOT use the cached value
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);
        assertEq(metric, TOTAL_OHM + 100e9 - 200e9 - 99e9);
    }

    function test_getMetric_maxAge_withinThreshold() public {
        _setupMetricLocations();

        // Store the metric value
        vm.startPrank(writer);
        moduleSupply.storeMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);
        vm.stopPrank();

        // Mint more OHM (so the cached value is incorrect)
        ohm.mint(address(treasuryAddress), 100e9);

        // Warp forward 1 second
        vm.warp(block.timestamp + 1);

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY, 2);

        // Should use the cached value
        assertEq(metric, TOTAL_OHM - 100e9 - 99e9);
    }

    function test_getMetric_maxAge_withinThreshold_withoutCache() public {
        _setupMetricLocations();

        // Get metric
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY, 2);

        // Should return a value
        assertEq(metric, TOTAL_OHM - 100e9 - 99e9);
    }

    function test_getMetric_maxAge_afterThreshold() public {
        _setupMetricLocations();

        // Store the metric value
        vm.startPrank(writer);
        moduleSupply.storeMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);
        vm.stopPrank();

        // Mint more OHM (so the cached value is incorrect)
        ohm.mint(address(treasuryAddress), 100e9);

        // Warp forward 3 seconds
        vm.warp(block.timestamp + 3);

        // Get metric - should NOT use the cached value
        uint256 metric = moduleSupply.getMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY, 2);
        assertEq(metric, TOTAL_OHM + 100e9 - 200e9 - 99e9);
    }

    function test_getMetric_maxAge_invalidMetric() public {
        bytes memory err = abi.encodeWithSignature("SPPLY_InvalidParams()");
        vm.expectRevert(err);

        // Get metric
        (bool result, ) = address(moduleSupply).call(
            abi.encodeWithSignature("getMetric(uint8,uint256)", 99, 2)
        );
    }

    function test_getMetric_variant_current() public {
        _setupMetricLocations();

        // Get metric
        (uint256 metric, uint48 timestamp) = moduleSupply.getMetric(
            SPPLYv1.Metric.CIRCULATING_SUPPLY,
            SPPLYv1.Variant.CURRENT
        );

        // Should return a value
        assertEq(metric, TOTAL_OHM - 100e9 - 99e9);
        assertEq(timestamp, uint48(block.timestamp));
    }

    function test_getMetric_variant_current_withCache() public {
        _setupMetricLocations();

        // Store the metric value
        vm.startPrank(writer);
        moduleSupply.storeMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);
        vm.stopPrank();

        // Mint more OHM (so the cached value is incorrect)
        ohm.mint(address(treasuryAddress), 100e9);

        // Get metric - should NOT use the cached value
        (uint256 metric, uint48 timestamp) = moduleSupply.getMetric(
            SPPLYv1.Metric.CIRCULATING_SUPPLY,
            SPPLYv1.Variant.CURRENT
        );
        assertEq(metric, TOTAL_OHM + 100e9 - 200e9 - 99e9);
        assertEq(timestamp, uint48(block.timestamp));
    }

    function test_getMetric_variant_last() public {
        _setupMetricLocations();

        // Get metric
        (uint256 metric, uint48 timestamp) = moduleSupply.getMetric(
            SPPLYv1.Metric.CIRCULATING_SUPPLY,
            SPPLYv1.Variant.LAST
        );

        // Should NOT return a value
        assertEq(metric, 0);
        assertEq(timestamp, 0);
    }

    function test_getMetric_variant_last_withCache() public {
        _setupMetricLocations();

        // Store the metric value
        vm.startPrank(writer);
        moduleSupply.storeMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);
        vm.stopPrank();

        // Mint more OHM (so the cached value is incorrect)
        ohm.mint(address(treasuryAddress), 100e9);

        // Get metric - should use the cached value
        (uint256 metric, uint48 timestamp) = moduleSupply.getMetric(
            SPPLYv1.Metric.CIRCULATING_SUPPLY,
            SPPLYv1.Variant.LAST
        );
        assertEq(metric, TOTAL_OHM - 100e9 - 99e9);
        assertEq(timestamp, uint48(block.timestamp));
    }

    function test_getMetric_variant_last_laterBlock_withCache() public {
        _setupMetricLocations();

        // Store the metric value
        vm.startPrank(writer);
        moduleSupply.storeMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);
        vm.stopPrank();

        // Warp forward 1 second
        uint256 previousTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1);

        // Get metric - should use the cached value
        (uint256 metric, uint48 timestamp) = moduleSupply.getMetric(
            SPPLYv1.Metric.CIRCULATING_SUPPLY,
            SPPLYv1.Variant.LAST
        );
        assertEq(metric, TOTAL_OHM - 100e9 - 99e9);
        assertEq(timestamp, previousTimestamp);
    }

    function test_getMetric_variant_invalid_reverts() public {
        bytes memory err = abi.encodeWithSignature("SPPLY_InvalidParams()");
        vm.expectRevert(err);

        // Get metric
        (bool result, ) = address(moduleSupply).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", SPPLYv1.Metric.CIRCULATING_SUPPLY, 2)
        );
    }

    function test_getMetric_variant_invalidMetric_reverts() public {
        bytes memory err = abi.encodeWithSignature("SPPLY_InvalidParams()");
        vm.expectRevert(err);

        // Get metric
        (bool result, ) = address(moduleSupply).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", 99, SPPLYv1.Variant.CURRENT)
        );
    }

    // =========  storeMetric ========= //

    function test_storeMetric_invalidMetric_reverts() public {
        bytes memory err = abi.encodeWithSignature("SPPLY_InvalidParams()");
        vm.expectRevert(err);

        // Store metric
        (bool result, ) = address(moduleSupply).call(
            abi.encodeWithSignature("storeMetric(uint8)", 99)
        );
    }

    function test_storeMetric_notPermissioned_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);

        // Store metric
        moduleSupply.storeMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);
    }

    function test_storeMetric() public {
        _setupMetricLocations();

        // Store metric
        vm.startPrank(writer);
        moduleSupply.storeMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY);
        vm.stopPrank();

        // Mint more OHM (so the cached value is incorrect)
        ohm.mint(address(treasuryAddress), 100e9);

        // Get metric
        (uint256 metric, ) = moduleSupply.getMetric(
            SPPLYv1.Metric.CIRCULATING_SUPPLY,
            SPPLYv1.Variant.LAST
        );
        assertEq(metric, TOTAL_OHM - 100e9 - 99e9);
    }

    // =========  getReservesByCategory ========= //

    // [X] getReservesByCategory
    //  [X] categoryNotApproved
    //  [X] supply calculations
    //    [X] no locations in category
    //    [X] no submodule selector defined
    //    [X] zero supply
    //    [X] OHM supply
    //    [X] gOHM supply
    //    [X] uses submodule reserves
    //    [X] reverts upon submodule failure

    function test_getReservesByCategory_categoryNotApproved_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_CategoryNotApproved(bytes32)",
            toCategory("junk")
        );
        vm.expectRevert(err);

        // Get supply
        moduleSupply.getReservesByCategory(toCategory("junk"));
    }

    function test_getReservesByCategory_noLocations() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Remove the existing location
        vm.startPrank(writer);
        moduleSupply.categorize(address(treasuryAddress), toCategory(0));
        vm.stopPrank();

        // Check supply
        SPPLYv1.Reserves[] memory reserves = moduleSupply.getReservesByCategory(
            toCategory("protocol-owned-treasury")
        );

        assertEq(reserves.length, 0);
    }

    function test_getReservesByCategory_noSubmoduleReservesSelector() public {
        // Add OHM in the treasury
        ohm.mint(address(treasuryAddress), 100e9);

        // Check supply
        SPPLYv1.Reserves[] memory reserves = moduleSupply.getReservesByCategory(
            toCategory("protocol-owned-treasury")
        );

        assertEq(reserves.length, 1);
        assertEq(reserves[0].tokens.length, 1);
        assertEq(reserves[0].tokens[0], address(ohm));
        assertEq(reserves[0].balances.length, 1);
        assertEq(reserves[0].balances[0], 100e9);
    }

    function test_getReservesByCategory_submoduleFailureReverts() public {
        _setUpSubmodules();

        // Set up submodule failure
        {
            vm.mockCallRevert(
                address(submoduleBLVaultSupply),
                abi.encodeWithSelector(SupplySubmodule.getProtocolOwnedLiquidityReserves.selector),
                abi.encode("revert")
            );
        }

        // Expect revert
        bytes memory err = abi.encodeWithSignature(
            "SPPLY_SubmoduleFailed(address,bytes4)",
            address(submoduleBLVaultSupply),
            SupplySubmodule.getProtocolOwnedLiquidityReserves.selector
        );
        vm.expectRevert(err);

        // Check reserves
        moduleSupply.getReservesByCategory(toCategory("protocol-owned-liquidity"));
    }

    function test_getReservesByCategory_includesSubmodules() public {
        _setUpSubmodules();

        // Add OHM/gOHM in the treasury (which will not be included)
        ohm.mint(address(treasuryAddress), 100e9);
        gohm.mint(address(treasuryAddress), 1e18); // 1 gOHM

        // Categories already defined

        uint256 expectedBptDai = BPT_BALANCE.mulDiv(
            BALANCER_POOL_DAI_BALANCE,
            BALANCER_POOL_TOTAL_SUPPLY
        );
        uint256 expectedBptOhm = BPT_BALANCE.mulDiv(
            BALANCER_POOL_OHM_BALANCE,
            BALANCER_POOL_TOTAL_SUPPLY
        );

        // Check reserves
        SPPLYv1.Reserves[] memory reserves = moduleSupply.getReservesByCategory(
            toCategory("protocol-owned-liquidity")
        );
        assertEq(reserves.length, 3);
        // Check reserves: Aura - Balancer
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].balances[0], expectedBptDai);
        assertEq(reserves[0].balances[1], expectedBptOhm);
        // Check reserves: BLVault
        assertEq(reserves[1].tokens.length, 0);
        assertEq(reserves[1].balances.length, 0);
        // Check reserves: Silo
        assertEq(reserves[2].tokens.length, 0);
        assertEq(reserves[2].balances.length, 0);
        // Treasury OHM/gOHM not included in the category
    }

    function test_getReservesByCategory_includesSubmodulesAndOhm() public {
        _setUpSubmodules();

        // Add OHM/gOHM in the polAddress
        ohm.mint(address(polAddress), 100e9);
        gohm.mint(address(polAddress), 1e18); // 1 gOHM

        // Add polAddress to the POL category
        vm.startPrank(writer);
        moduleSupply.categorize(address(polAddress), toCategory("protocol-owned-liquidity"));
        vm.stopPrank();

        uint256 expectedBptDai = BPT_BALANCE.mulDiv(
            BALANCER_POOL_DAI_BALANCE,
            BALANCER_POOL_TOTAL_SUPPLY
        );
        uint256 expectedBptOhm = BPT_BALANCE.mulDiv(
            BALANCER_POOL_OHM_BALANCE,
            BALANCER_POOL_TOTAL_SUPPLY
        );
        uint256 expectedOhm = 100e9 + gohm.balanceFrom(1e18);

        // Check reserves
        SPPLYv1.Reserves[] memory reserves = moduleSupply.getReservesByCategory(
            toCategory("protocol-owned-liquidity")
        );

        assertEq(reserves.length, 4);
        // Check reserves: Aura - Balancer
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].balances[0], expectedBptDai);
        assertEq(reserves[0].balances[1], expectedBptOhm);
        // Check reserves: BLVault
        assertEq(reserves[1].tokens.length, 0);
        assertEq(reserves[1].balances.length, 0);
        // Check reserves: Silo
        assertEq(reserves[2].tokens.length, 0);
        assertEq(reserves[2].balances.length, 0);
        // Check reserves: Treasury
        assertEq(reserves[3].source, polAddress);
        assertEq(reserves[3].tokens.length, 1);
        assertEq(reserves[3].tokens[0], address(ohm));
        assertEq(reserves[3].balances.length, 1);
        assertEq(reserves[3].balances[0], expectedOhm);
    }
}
