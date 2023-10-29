// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";

// Modules and Submodules
import "src/Submodules.sol";
import {OlympusSupply, SPPLYv1, Category as SupplyCategory} from "modules/SPPLY/OlympusSupply.sol";
import {OlympusTreasury, TRSRYv1_1} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";

// Policies
import {Appraiser} from "policies/OCA/Appraiser.sol";
import {Bookkeeper, AssetCategory} from "policies/OCA/Bookkeeper.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

// Interfaces
import {IAppraiser} from "policies/OCA/interfaces/IAppraiser.sol";

contract AppraiserTest is Test {
    MockERC20 internal ohm;
    MockERC20 internal reserve;
    MockERC20 internal weth;

    Kernel internal kernel;

    MockPrice internal PRICE;
    OlympusSupply internal SPPLY;
    OlympusTreasury internal TRSRY;
    OlympusRoles internal ROLES;

    Appraiser internal appraiser;
    Bookkeeper internal bookkeeper;
    RolesAdmin internal rolesAdmin;

    uint32 internal constant OBSERVATION_FREQUENCY = 8 hours;
    uint8 internal constant DECIMALS = 18;

    enum Variant {
        CURRENT,
        LAST,
        ERROR
    }

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Tokens
        {
            ohm = new MockERC20("Olympus", "OHM", 9);
            reserve = new MockERC20("Reserve", "RSV", 18);
            weth = new MockERC20("Wrapped ETH", "WETH", 18);
        }

        // Kernel and Modules
        {
            address[2] memory tokens = [address(ohm), address(reserve)];

            kernel = new Kernel();
            PRICE = new MockPrice(kernel, DECIMALS, OBSERVATION_FREQUENCY);
            TRSRY = new OlympusTreasury(kernel);
            SPPLY = new OlympusSupply(kernel, tokens, 0);
            ROLES = new OlympusRoles(kernel);
        }

        // Policies
        {
            appraiser = new Appraiser(kernel);
            bookkeeper = new Bookkeeper(kernel);
            rolesAdmin = new RolesAdmin(kernel);
        }

        // Configure Price mock
        {
            PRICE.setPrice(address(ohm), 10e18);
            PRICE.setPrice(address(reserve), 1e18);
            PRICE.setPrice(address(weth), 2000e18);
        }

        // Default Framework Initialization
        {
            // Install modules
            kernel.executeAction(Actions.InstallModule, address(PRICE));
            kernel.executeAction(Actions.InstallModule, address(TRSRY));
            kernel.executeAction(Actions.InstallModule, address(SPPLY));
            kernel.executeAction(Actions.InstallModule, address(ROLES));

            // Activate policies
            kernel.executeAction(Actions.ActivatePolicy, address(appraiser));
            kernel.executeAction(Actions.ActivatePolicy, address(bookkeeper));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }

        // Roles management
        {
            // Bookkeeper roles
            rolesAdmin.grantRole("bookkeeper_policy", address(this));
            rolesAdmin.grantRole("bookkeeper_admin", address(this));
        }

        // Configure assets
        {
            // Add assets to Treasury
            address[] memory locations = new address[](0);
            bookkeeper.addAsset(address(reserve), locations);
            bookkeeper.addAsset(address(weth), locations);

            // Categorize assets
            bookkeeper.categorizeAsset(address(reserve), AssetCategory.wrap("liquid"));
            bookkeeper.categorizeAsset(address(reserve), AssetCategory.wrap("stable"));
            bookkeeper.categorizeAsset(address(reserve), AssetCategory.wrap("reserves"));
            bookkeeper.categorizeAsset(address(weth), AssetCategory.wrap("liquid"));
        }

        // Mint tokens
        {
            reserve.mint(address(TRSRY), 1_000_000e18);
            weth.mint(address(TRSRY), 1_000e18);
        }
    }

    //============================================================================================//
    //                                       ASSET VALUES                                         //
    //============================================================================================//

    /// [X]  getAssetValue(address asset_)
    ///     [X]  if latest value was captured at the current timestamp, return that value
    ///     [X]  if latest value was captured at a previous timestamp, fetch and return the current value

    function testCorrectness_getAssetValueAddressCurrentTimestamp() public {
        // Cache current asset value and timestamp
        appraiser.storeAssetValue(address(reserve));

        // Assert value is in cache
        (, uint48 timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(timestamp, uint48(block.timestamp));

        // Get asset value
        uint256 value = appraiser.getAssetValue(address(reserve));

        // Assert value is correct and timestamp is unchanged
        (, timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(value, 1_000_000e18);
        assertEq(timestamp, uint48(block.timestamp));
    }

    function testCorrectness_getAssetValueAddressPreviousTimestamp() public {
        // Cache current asset value and timestamp
        appraiser.storeAssetValue(address(reserve));

        // Now update price and timestamp
        vm.warp(block.timestamp + 100);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Assert value is in cache
        (uint256 cacheValue, uint48 timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, 1_000_000e18);
        assertEq(timestamp, uint48(block.timestamp - 100));

        // Get asset value
        uint256 value = appraiser.getAssetValue(address(reserve));

        // Assert value is correct and cache is unchanged
        (cacheValue, timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(value, 2_000_000e18);
        assertEq(cacheValue, 1_000_000e18);
        assertEq(timestamp, uint48(block.timestamp - 100));
    }

    /// [X]  getAssetValue(address asset_, uint48 maxAge_)
    ///     [X]  if latest value was captured more recently than the passed maxAge, return that value
    ///     [X]  if latest value was captured at a too outdated timestamp, fetch and return the current value

    function testCorrectness_getAssetValueAddressAgeRecentTimestamp(uint48 maxAge_) public {
        vm.assume(maxAge_ < 30 days); // test value to avoid overflow situations that just revert

        // Cache current asset value and timestamp
        appraiser.storeAssetValue(address(reserve));

        // Now update price and timestamp
        vm.warp(block.timestamp + maxAge_ - 1);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Assert value is in cache
        (uint256 cacheValue, uint48 timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, 1_000_000e18);
        assertEq(timestamp, uint48(block.timestamp - maxAge_ + 1));

        // Get asset value
        uint256 value = appraiser.getAssetValue(address(reserve), maxAge_);

        // Assert value is correct and cache is unchanged
        (cacheValue, timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(value, 1_000_000e18);
        assertEq(cacheValue, 1_000_000e18);
        assertEq(timestamp, uint48(block.timestamp - maxAge_ + 1));
    }

    function testCorrectness_getAssetValueAddressAgeOutdatedTimestamp(uint48 maxAge_) public {
        vm.assume(maxAge_ < 30 days); // test value to avoid overflow situations that just revert

        // Cache current asset value and timestamp
        appraiser.storeAssetValue(address(reserve));

        // Now update price and timestamp
        vm.warp(block.timestamp + maxAge_ + 1);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Assert value is in cache
        (uint256 cacheValue, uint48 timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, 1_000_000e18);
        assertEq(timestamp, uint48(block.timestamp - maxAge_ - 1));

        // Get asset value
        uint256 value = appraiser.getAssetValue(address(reserve), maxAge_);

        // Assert value is correct and cache is unchanged
        (cacheValue, timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(value, 2_000_000e18);
        assertEq(cacheValue, 1_000_000e18);
        assertEq(timestamp, uint48(block.timestamp - maxAge_ - 1));
    }

    /// [X]  getAssetValue(address asset_, Variant variant_)
    ///     [X]  reverts if variant is not LAST or CURRENT
    ///     [X]  gets latest asset value if variant is LAST
    ///     [X]  gets current asset value if variant is CURRENT

    function testCorrectness_getAssetValueAddressVariantInvalid() public {
        // Cache current asset value and timestamp
        appraiser.storeAssetValue(address(reserve));

        // Directly call getAssetValue with invalid variant
        (bool success, ) = address(appraiser).call(
            abi.encodeWithSignature("getAssetValue(address,uint8)", address(reserve), 2)
        );

        // Assert call reverts
        assertEq(success, false);
    }

    function testCorrectness_getAssetValueAddressVariantLast() public {
        // Cache current asset value and timestamp
        appraiser.storeAssetValue(address(reserve));

        // Now update price and timestamp
        vm.warp(block.timestamp + 100);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Assert value is in cache
        (uint256 cacheValue, uint48 timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, 1_000_000e18);
        assertEq(timestamp, uint48(block.timestamp - 100));

        // Directly call getAssetValue with variant LAST
        (bool success, bytes memory data) = address(appraiser).call(
            abi.encodeWithSignature("getAssetValue(address,uint8)", address(reserve), 1)
        );

        // Assert call succeeded
        assertEq(success, true);

        // Decode return data to value and timestamp
        (uint256 value, uint48 variantTimestamp) = abi.decode(data, (uint256, uint48));

        // Assert value is from cache and cache is unchanged
        (cacheValue, timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, 1_000_000e18);
        assertEq(timestamp, uint48(block.timestamp - 100));
        assertEq(value, 1_000_000e18);
        assertEq(variantTimestamp, uint48(block.timestamp - 100));
    }

    function testCorrectness_getAssetValueAddressVariantCurrent() public {
        // Cache current asset value and timestamp
        appraiser.storeAssetValue(address(reserve));

        // Now update price and timestamp
        vm.warp(block.timestamp + 100);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Assert value is in cache
        (uint256 cacheValue, uint48 timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, 1_000_000e18);
        assertEq(timestamp, uint48(block.timestamp - 100));

        // Directly call getAssetValue with variant CURRENT
        (bool success, bytes memory data) = address(appraiser).call(
            abi.encodeWithSignature("getAssetValue(address,uint8)", address(reserve), 0)
        );

        // Assert call succeeded
        assertEq(success, true);

        // Decode return data to value and timestamp
        (uint256 value, uint48 variantTimestamp) = abi.decode(data, (uint256, uint48));

        // Assert value is current but cache is unchanged
        (cacheValue, timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, 1_000_000e18);
        assertEq(timestamp, uint48(block.timestamp - 100));
        assertEq(value, 2_000_000e18);
        assertEq(variantTimestamp, uint48(block.timestamp));
    }

    /// []  getCategoryValue(Category category_)
    ///     []  if latest value was captured at the current timestamp, return that value
    ///     []  if latest value was captured at a previous timestamp, fetch and return the current value

    /// []  getCategoryValue(Category category_, uint48 maxAge_)
    ///     []  if latest value was captured more recently than the passed maxAge, return that value
    ///     []  if latest value was captured at a too outdated timestamp, fetch and return the current value

    /// []  getCategoryValue(Category category_, Variant variant_)
    ///     []  reverts if variant is not LAST or CURRENT
    ///     []  gets latest category value if variant is LAST
    ///     []  gets current category value if variant is CURRENT

    //============================================================================================//
    //                                       VALUE METRICS                                        //
    //============================================================================================//

    /// []  getMetric(Metric metric_)
    ///     []  if latest value was captured at the current timestamp, return that value
    ///     []  if latest value was captured at a previous timestamp, fetch and return the current value

    /// []  getMetric(Metric metric_, uint48 maxAge_)
    ///     []  if latest value was captured more recently than the passed maxAge, return that value
    ///     []  if latest value was captured at a too outdated timestamp, fetch and return the current value

    /// []  getMetric(Metric metric_, Variant variant_)
    ///     []  reverts if variant is not LAST or CURRENT
    ///     []  reverts if metric is not a valid metric
    ///     []  gets latest metric value if variant is LAST
    ///     []  gets current metric value if variant is CURRENT

    //============================================================================================//
    //                                       CACHING                                              //
    //============================================================================================//

    /// []  storeAssetValue(address asset_)
    ///     []  stores current asset value

    /// []  storeCategoryValue(Category category_)
    ///     []  stores current category value

    /// []  storeMetric(Metric metric_)
    ///     []  stores current metric value
}
