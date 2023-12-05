// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {FullMath} from "libraries/FullMath.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockMultiplePoolBalancerVault} from "test/mocks/MockBalancerVault.sol";

// Modules and Submodules
import "src/Submodules.sol";
import {OlympusSupply, SPPLYv1, Category as SupplyCategory} from "modules/SPPLY/OlympusSupply.sol";
import {OlympusTreasury, TRSRYv1_1} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";

// Policies
import {Appraiser} from "policies/OCA/Appraiser.sol";
import {Bookkeeper, AssetCategory} from "policies/OCA/Bookkeeper.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

// Submodules
import {AuraBalancerSupply} from "src/modules/SPPLY/submodules/AuraBalancerSupply.sol";
import {IBalancerPool} from "src/external/balancer/interfaces/IBalancerPool.sol";
import {IAuraRewardPool} from "src/external/aura/interfaces/IAuraRewardPool.sol";

// Interfaces
import {IAppraiser} from "policies/OCA/interfaces/IAppraiser.sol";

contract AppraiserTest is Test {
    using FullMath for uint256;

    MockERC20 internal ohm;
    MockGohm internal gohm;
    MockERC20 internal reserve;
    MockERC20 internal weth;

    address internal daoWallet = address(bytes20("DAO"));
    address internal protocolWallet = address(bytes20("POT"));

    Kernel internal kernel;

    MockPrice internal PRICE;
    OlympusSupply internal SPPLY;
    OlympusTreasury internal TRSRY;
    OlympusRoles internal ROLES;

    Appraiser internal appraiser;
    Bookkeeper internal bookkeeper;
    RolesAdmin internal rolesAdmin;

    AuraBalancerSupply internal submoduleAuraBalancerSupply;

    uint32 internal constant OBSERVATION_FREQUENCY = 8 hours;
    uint8 internal constant DECIMALS = 18;
    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals
    uint256 internal constant OHM_PRICE = 10e18;
    uint256 internal constant OHM_MINT_BALANCE = 999_900e9;
    uint256 internal constant OHM_MINT_DAO = 100e9;
    uint256 internal constant OHM_MINT_PROTOCOL = 200e9;

    uint256 internal constant RESERVE_VALUE_AT_1 = 1_000_000e18;
    uint256 internal constant RESERVE_VALUE_AT_2 = 2_000_000e18;
    uint256 internal constant WETH_VALUE_AT_2000 = 2_000_000e18;
    uint256 internal constant WETH_VALUE_AT_4000 = 4_000_000e18;

    uint256 internal constant BALANCER_POOL_RESERVE_BALANCE = 100e18; // 100 RSV
    uint256 internal constant BALANCER_POOL_OHM_BALANCE = 100e9; // 100 OHM
    uint256 internal constant BALANCER_POOL_TOTAL_SUPPLY = 100e18; // 100 LP
    uint256 internal constant BPT_BALANCE = 1e18;
    uint256 internal constant BPT_PRICE = 2_000_000e9;
    uint256 internal backingPOL =
        BPT_BALANCE.mulDiv(BALANCER_POOL_RESERVE_BALANCE, BALANCER_POOL_TOTAL_SUPPLY);
    uint256 internal POL_VALUE_AT_1 = BPT_BALANCE.mulDiv(BPT_PRICE, 1e18);
    uint256 internal POL_BACKING_AT_1 = backingPOL;
    uint256 internal POL_BACKING_AT_2 = 2 * backingPOL;

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
            gohm = new MockGohm(GOHM_INDEX);
            reserve = new MockERC20("Reserve", "RSV", 18);
            weth = new MockERC20("Wrapped ETH", "WETH", 18);
        }

        // Kernel and Modules
        {
            address[2] memory tokens = [address(ohm), address(gohm)];

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

        address balancerPool = _setupSupplySubmodules();

        // Configure Price mock
        {
            PRICE.setPrice(address(ohm), OHM_PRICE);
            PRICE.setPrice(address(reserve), 1e18);
            PRICE.setPrice(address(weth), 2000e18);
            PRICE.setPrice(balancerPool, BPT_PRICE);
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

            locations = new address[](1);
            locations[0] = address(bytes20("POL"));
            bookkeeper.addAsset(balancerPool, locations);

            // Categorize assets
            bookkeeper.categorizeAsset(address(reserve), AssetCategory.wrap("liquid"));
            bookkeeper.categorizeAsset(address(reserve), AssetCategory.wrap("stable"));
            bookkeeper.categorizeAsset(address(reserve), AssetCategory.wrap("reserves"));
            bookkeeper.categorizeAsset(address(weth), AssetCategory.wrap("liquid"));
            bookkeeper.categorizeAsset(address(weth), AssetCategory.wrap("volatile"));
            bookkeeper.categorizeAsset(
                balancerPool,
                AssetCategory.wrap("protocol-owned-liquidity")
            );

            // Categorize supplies
            bookkeeper.installSubmodule(SPPLY.KEYCODE(), submoduleAuraBalancerSupply);
            bookkeeper.categorizeSupply(
                address(bytes20("POL")),
                SupplyCategory.wrap("protocol-owned-liquidity")
            );
            bookkeeper.categorizeSupply(daoWallet, SupplyCategory.wrap("dao"));
            bookkeeper.categorizeSupply(
                protocolWallet,
                SupplyCategory.wrap("protocol-owned-treasury")
            );
        }

        // Mint tokens
        {
            ohm.mint(address(this), OHM_MINT_BALANCE);
            ohm.mint(address(daoWallet), OHM_MINT_DAO);
            ohm.mint(address(protocolWallet), OHM_MINT_PROTOCOL);
            reserve.mint(address(TRSRY), 1_000_000e18);
            weth.mint(address(TRSRY), 1_000e18);
        }
    }

    function _setupSupplySubmodules() internal returns (address) {
        // AuraBalancerSupply setup
        MockMultiplePoolBalancerVault balancerVault = new MockMultiplePoolBalancerVault();
        bytes32 poolId = "hello";

        address[] memory balancerPoolTokens = new address[](2);
        balancerPoolTokens[0] = address(reserve);
        balancerPoolTokens[1] = address(ohm);
        balancerVault.setTokens(poolId, balancerPoolTokens);

        uint256[] memory balancerPoolBalances = new uint256[](2);
        balancerPoolBalances[0] = BALANCER_POOL_RESERVE_BALANCE;
        balancerPoolBalances[1] = BALANCER_POOL_OHM_BALANCE;
        balancerVault.setBalances(poolId, balancerPoolBalances);

        // Mint the OHM in the pool
        ohm.mint(address(balancerVault), BALANCER_POOL_OHM_BALANCE);

        MockBalancerPool balancerPool = new MockBalancerPool(poolId);
        balancerPool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);
        balancerPool.setBalance(address(bytes20("POL")), BPT_BALANCE); // balance for POL address
        balancerPool.setDecimals(uint8(18));

        AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](1);
        pools[0] = AuraBalancerSupply.Pool(
            IBalancerPool(balancerPool),
            IAuraRewardPool(address(0))
        );

        submoduleAuraBalancerSupply = new AuraBalancerSupply(
            SPPLY,
            address(bytes20("POL")),
            address(balancerVault),
            pools
        );

        return address(balancerPool);
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
        assertEq(value, RESERVE_VALUE_AT_1);
        assertEq(timestamp, uint48(block.timestamp));
    }

    function testCorrectness_getAssetValueAddressPreviousTimestamp() public {
        uint48 timestampBefore = uint48(block.timestamp);

        // Cache current asset value and timestamp
        appraiser.storeAssetValue(address(reserve));

        // Now update price and timestamp
        vm.warp(block.timestamp + 100);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Assert value is in cache
        (uint256 cacheValue, uint48 timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, RESERVE_VALUE_AT_1);
        assertEq(timestamp, timestampBefore);

        // Get asset value
        uint256 value = appraiser.getAssetValue(address(reserve));

        // Assert value is correct and cache is unchanged
        (cacheValue, timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(value, RESERVE_VALUE_AT_2);
        assertEq(cacheValue, RESERVE_VALUE_AT_1);
        assertEq(timestamp, timestampBefore);
    }

    /// [X]  getAssetValue(address asset_, uint48 maxAge_)
    ///     [X]  if latest value was captured more recently than the passed maxAge, return that value
    ///     [X]  if latest value was captured at a too outdated timestamp, fetch and return the current value

    function testCorrectness_getAssetValueAddressAgeRecentTimestamp(uint48 maxAge_) public {
        vm.assume(maxAge_ > 0 && maxAge_ < 30 days); // test value to avoid overflow situations that just revert

        uint48 timestampBefore = uint48(block.timestamp);

        // Cache current asset value and timestamp
        appraiser.storeAssetValue(address(reserve));

        // Now update price and timestamp
        vm.warp(block.timestamp + maxAge_ - 1);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Assert value is in cache
        (uint256 cacheValue, uint48 timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, RESERVE_VALUE_AT_1);
        assertEq(timestamp, timestampBefore);

        // Get asset value
        uint256 value = appraiser.getAssetValue(address(reserve), maxAge_);

        // Assert value is correct and cache is unchanged
        (cacheValue, timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(value, RESERVE_VALUE_AT_1);
        assertEq(cacheValue, RESERVE_VALUE_AT_1);
        assertEq(timestamp, timestampBefore);
    }

    function testCorrectness_getAssetValueAddressAgeOutdatedTimestamp(uint48 maxAge_) public {
        vm.assume(maxAge_ > 0 && maxAge_ < 30 days); // test value to avoid overflow situations that just revert

        uint48 timestampBefore = uint48(block.timestamp);

        // Cache current asset value and timestamp
        appraiser.storeAssetValue(address(reserve));

        // Now update price and timestamp
        vm.warp(block.timestamp + maxAge_ + 1);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Assert value is in cache
        (uint256 cacheValue, uint48 timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, RESERVE_VALUE_AT_1);
        assertEq(timestamp, timestampBefore);

        // Get asset value
        uint256 value = appraiser.getAssetValue(address(reserve), maxAge_);

        // Assert value is correct and cache is unchanged
        (cacheValue, timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(value, RESERVE_VALUE_AT_2);
        assertEq(cacheValue, RESERVE_VALUE_AT_1);
        assertEq(timestamp, timestampBefore);
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
        uint48 timestampBefore = uint48(block.timestamp);

        // Cache current asset value and timestamp
        appraiser.storeAssetValue(address(reserve));

        // Now update price and timestamp
        vm.warp(block.timestamp + 100);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Assert value is in cache
        (uint256 cacheValue, uint48 timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, RESERVE_VALUE_AT_1);
        assertEq(timestamp, timestampBefore);

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
        assertEq(cacheValue, RESERVE_VALUE_AT_1);
        assertEq(timestamp, timestampBefore);
        assertEq(value, RESERVE_VALUE_AT_1);
        assertEq(variantTimestamp, timestampBefore);
    }

    function testCorrectness_getAssetValueAddressVariantCurrent() public {
        uint48 timestampBefore = uint48(block.timestamp);

        // Cache current asset value and timestamp
        appraiser.storeAssetValue(address(reserve));

        // Now update price and timestamp
        vm.warp(block.timestamp + 100);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Assert value is in cache
        (uint256 cacheValue, uint48 timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, RESERVE_VALUE_AT_1);
        assertEq(timestamp, timestampBefore);

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
        assertEq(cacheValue, RESERVE_VALUE_AT_1);
        assertEq(timestamp, timestampBefore);
        assertEq(value, RESERVE_VALUE_AT_2);
        assertEq(variantTimestamp, uint48(block.timestamp));
    }

    /// [X]  getCategoryValue(Category category_)
    ///     [X]  if latest value was captured at the current timestamp, return that value
    ///     [X]  if latest value was captured at a previous timestamp, fetch and return the current value

    function testCorrectness_getCategoryValueCategoryCurrentTimestamp() public {
        // Cache current category value and timestamp
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
        appraiser.storeCategoryValue(AssetCategory.wrap("stable"));
        appraiser.storeCategoryValue(AssetCategory.wrap("reserves"));

        // Assert category values are in cache
        (uint256 liquidCacheValue, uint48 liquidTimestamp) = appraiser.categoryValueCache(
            AssetCategory.wrap("liquid")
        );
        (uint256 stableCacheValue, uint48 stableTimestamp) = appraiser.categoryValueCache(
            AssetCategory.wrap("stable")
        );
        (uint256 reservesCacheValue, uint48 reservesTimestamp) = appraiser.categoryValueCache(
            AssetCategory.wrap("reserves")
        );
        assertEq(liquidCacheValue, 3_000_000e18);
        assertEq(liquidTimestamp, uint48(block.timestamp));
        assertEq(stableCacheValue, 1_000_000e18);
        assertEq(stableTimestamp, uint48(block.timestamp));
        assertEq(reservesCacheValue, 1_000_000e18);
        assertEq(reservesTimestamp, uint48(block.timestamp));

        // Get category values
        uint256 liquidValue = appraiser.getCategoryValue(AssetCategory.wrap("liquid"));
        uint256 stableValue = appraiser.getCategoryValue(AssetCategory.wrap("stable"));
        uint256 reservesValue = appraiser.getCategoryValue(AssetCategory.wrap("reserves"));

        // Assert category values are correct and timestamp is unchanged
        (liquidCacheValue, liquidTimestamp) = appraiser.categoryValueCache(
            AssetCategory.wrap("liquid")
        );
        (stableCacheValue, stableTimestamp) = appraiser.categoryValueCache(
            AssetCategory.wrap("stable")
        );
        (reservesCacheValue, reservesTimestamp) = appraiser.categoryValueCache(
            AssetCategory.wrap("reserves")
        );
        assertEq(liquidValue, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000);
        assertEq(stableValue, RESERVE_VALUE_AT_1);
        assertEq(reservesValue, RESERVE_VALUE_AT_1);
        assertEq(liquidCacheValue, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000);
        assertEq(liquidTimestamp, uint48(block.timestamp));
        assertEq(stableCacheValue, RESERVE_VALUE_AT_1);
        assertEq(stableTimestamp, uint48(block.timestamp));
        assertEq(reservesCacheValue, RESERVE_VALUE_AT_1);
        assertEq(reservesTimestamp, uint48(block.timestamp));
    }

    function testCorrectness_getCategoryValueCategoryPreviousTimestamp() public {
        uint48 timestampBefore = uint48(block.timestamp);

        // Cache current category value and timestamp
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
        appraiser.storeCategoryValue(AssetCategory.wrap("stable"));
        appraiser.storeCategoryValue(AssetCategory.wrap("reserves"));

        // Now update price and timestamp
        vm.warp(block.timestamp + 100);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));
        PRICE.setPrice(address(weth), 4000e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Assert category values are in cache
        (uint256 liquidCacheValue, uint48 liquidTimestamp) = appraiser.categoryValueCache(
            AssetCategory.wrap("liquid")
        );
        (uint256 stableCacheValue, uint48 stableTimestamp) = appraiser.categoryValueCache(
            AssetCategory.wrap("stable")
        );
        (uint256 reservesCacheValue, uint48 reservesTimestamp) = appraiser.categoryValueCache(
            AssetCategory.wrap("reserves")
        );
        assertEq(liquidCacheValue, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000);
        assertEq(liquidTimestamp, timestampBefore);
        assertEq(stableCacheValue, RESERVE_VALUE_AT_1);
        assertEq(stableTimestamp, timestampBefore);
        assertEq(reservesCacheValue, RESERVE_VALUE_AT_1);
        assertEq(reservesTimestamp, timestampBefore);

        // Get category values
        uint256 liquidValue = appraiser.getCategoryValue(AssetCategory.wrap("liquid"));
        uint256 stableValue = appraiser.getCategoryValue(AssetCategory.wrap("stable"));
        uint256 reservesValue = appraiser.getCategoryValue(AssetCategory.wrap("reserves"));

        // Assert category values are correct and timestamp is unchanged
        (liquidCacheValue, liquidTimestamp) = appraiser.categoryValueCache(
            AssetCategory.wrap("liquid")
        );
        (stableCacheValue, stableTimestamp) = appraiser.categoryValueCache(
            AssetCategory.wrap("stable")
        );
        (reservesCacheValue, reservesTimestamp) = appraiser.categoryValueCache(
            AssetCategory.wrap("reserves")
        );
        assertEq(liquidValue, RESERVE_VALUE_AT_2 + WETH_VALUE_AT_4000);
        assertEq(stableValue, RESERVE_VALUE_AT_2);
        assertEq(reservesValue, RESERVE_VALUE_AT_2);
        assertEq(liquidCacheValue, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000);
        assertEq(liquidTimestamp, timestampBefore);
        assertEq(stableCacheValue, RESERVE_VALUE_AT_1);
        assertEq(stableTimestamp, timestampBefore);
        assertEq(reservesCacheValue, RESERVE_VALUE_AT_1);
        assertEq(reservesTimestamp, timestampBefore);
    }

    /// [X]  getCategoryValue(Category category_, uint48 maxAge_)
    ///     [X]  if latest value was captured more recently than the passed maxAge, return that value
    ///     [X]  if latest value was captured at a too outdated timestamp, fetch and return the current value

    function testCorrectness_getCategoryValueCategoryAgeRecentTimestamp(uint48 maxAge_) public {
        vm.assume(maxAge_ > 0 && maxAge_ < 30 days); // test value to avoid overflow situations that just revert

        // Cache current category value and timestamp
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
        appraiser.storeCategoryValue(AssetCategory.wrap("stable"));
        appraiser.storeCategoryValue(AssetCategory.wrap("reserves"));

        // Now update price and timestamp
        vm.warp(block.timestamp + maxAge_ - 1);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));
        PRICE.setPrice(address(weth), 4000e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Get category values
        (bool liquidSuccess, bytes memory liquidData) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint48)",
                AssetCategory.wrap("liquid"),
                maxAge_
            )
        );
        (bool stableSuccess, bytes memory stableData) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint48)",
                AssetCategory.wrap("stable"),
                maxAge_
            )
        );
        (bool reservesSuccess, bytes memory reservesData) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint48)",
                AssetCategory.wrap("reserves"),
                maxAge_
            )
        );

        // Assert calls succeeded
        assertEq(liquidSuccess, true);
        assertEq(stableSuccess, true);
        assertEq(reservesSuccess, true);

        // Decode return data to values
        uint256 liquidValue = abi.decode(liquidData, (uint256));
        uint256 stableValue = abi.decode(stableData, (uint256));
        uint256 reservesValue = abi.decode(reservesData, (uint256));

        // Assert category values are correct
        assertEq(liquidValue, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000);
        assertEq(stableValue, RESERVE_VALUE_AT_1);
        assertEq(reservesValue, RESERVE_VALUE_AT_1);
    }

    function testCorrectness_getCategoryValueCategoryAgeOutdatedTimestamp(uint48 maxAge_) public {
        vm.assume(maxAge_ > 0 && maxAge_ < 30 days); // test value to avoid overflow situations that just revert

        // Cache current category value and timestamp
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
        appraiser.storeCategoryValue(AssetCategory.wrap("stable"));
        appraiser.storeCategoryValue(AssetCategory.wrap("reserves"));

        // Now update price and timestamp
        vm.warp(block.timestamp + maxAge_ + 1);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));
        PRICE.setPrice(address(weth), 4000e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Get category values
        (bool liquidSuccess, bytes memory liquidData) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint48)",
                AssetCategory.wrap("liquid"),
                maxAge_
            )
        );
        (bool stableSuccess, bytes memory stableData) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint48)",
                AssetCategory.wrap("stable"),
                maxAge_
            )
        );
        (bool reservesSuccess, bytes memory reservesData) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint48)",
                AssetCategory.wrap("reserves"),
                maxAge_
            )
        );

        // Assert calls succeeded
        assertEq(liquidSuccess, true);
        assertEq(stableSuccess, true);
        assertEq(reservesSuccess, true);

        // Decode return data to values
        uint256 liquidValue = abi.decode(liquidData, (uint256));
        uint256 stableValue = abi.decode(stableData, (uint256));
        uint256 reservesValue = abi.decode(reservesData, (uint256));

        // Assert category values are correct
        assertEq(liquidValue, RESERVE_VALUE_AT_2 + WETH_VALUE_AT_4000);
        assertEq(stableValue, RESERVE_VALUE_AT_2);
        assertEq(reservesValue, RESERVE_VALUE_AT_2);
    }

    /// [X]  getCategoryValue(Category category_, Variant variant_)
    ///     [X]  reverts if variant is not LAST or CURRENT
    ///     [X]  gets latest category value if variant is LAST
    ///     [X]  gets current category value if variant is CURRENT

    function testCorrectness_getCategoryValueCategoryVariantInvalid() public {
        // Cache current category value and timestamp
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
        appraiser.storeCategoryValue(AssetCategory.wrap("stable"));
        appraiser.storeCategoryValue(AssetCategory.wrap("reserves"));

        // Directly call getCategoryValue with invalid variant
        (bool liquidSuccess, ) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint8)",
                AssetCategory.wrap("liquid"),
                2
            )
        );
        (bool stableSuccess, ) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint8)",
                AssetCategory.wrap("stable"),
                2
            )
        );
        (bool reservesSuccess, ) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint8)",
                AssetCategory.wrap("reserves"),
                2
            )
        );

        // Assert calls reverts
        assertEq(liquidSuccess, false);
        assertEq(stableSuccess, false);
        assertEq(reservesSuccess, false);
    }

    function testCorrectness_getCategoryValueCategoryVariantLast() public {
        uint48 timestampBefore = uint48(block.timestamp);

        // Cache current category value and timestamp
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
        appraiser.storeCategoryValue(AssetCategory.wrap("stable"));
        appraiser.storeCategoryValue(AssetCategory.wrap("reserves"));

        // Now update price and timestamp
        vm.warp(block.timestamp + 100);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));
        PRICE.setPrice(address(weth), 4000e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Directly call getCategoryValue with valid variant
        (bool liquidSuccess, bytes memory liquidData) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint8)",
                AssetCategory.wrap("liquid"),
                1
            )
        );
        (bool stableSuccess, bytes memory stableData) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint8)",
                AssetCategory.wrap("stable"),
                1
            )
        );
        (bool reservesSuccess, bytes memory reservesData) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint8)",
                AssetCategory.wrap("reserves"),
                1
            )
        );

        // Assert calls succeeded
        assertEq(liquidSuccess, true);
        assertEq(stableSuccess, true);
        assertEq(reservesSuccess, true);

        // Decode return data to values and timestamps
        (uint256 liquidValue, uint48 liquidTimestamp) = abi.decode(liquidData, (uint256, uint48));
        (uint256 stableValue, uint48 stableTimestamp) = abi.decode(stableData, (uint256, uint48));
        (uint256 reservesValue, uint48 reservesTimestamp) = abi.decode(
            reservesData,
            (uint256, uint48)
        );

        // Assert category values and timestamps are correct
        assertEq(liquidValue, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000);
        assertEq(liquidTimestamp, timestampBefore);
        assertEq(stableValue, RESERVE_VALUE_AT_1);
        assertEq(stableTimestamp, timestampBefore);
        assertEq(reservesValue, RESERVE_VALUE_AT_1);
        assertEq(reservesTimestamp, timestampBefore);
    }

    function testCorrectness_getCategoryValueCategoryVariantCurrent() public {
        // Cache current category value and timestamp
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
        appraiser.storeCategoryValue(AssetCategory.wrap("stable"));
        appraiser.storeCategoryValue(AssetCategory.wrap("reserves"));

        // Now update price and timestamp
        vm.warp(block.timestamp + 100);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));
        PRICE.setPrice(address(weth), 4000e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Directly call getCategoryValue with valid variant
        (bool liquidSuccess, bytes memory liquidData) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint8)",
                AssetCategory.wrap("liquid"),
                0
            )
        );
        (bool stableSuccess, bytes memory stableData) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint8)",
                AssetCategory.wrap("stable"),
                0
            )
        );
        (bool reservesSuccess, bytes memory reservesData) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint8)",
                AssetCategory.wrap("reserves"),
                0
            )
        );

        // Assert calls succeeded
        assertEq(liquidSuccess, true);
        assertEq(stableSuccess, true);
        assertEq(reservesSuccess, true);

        // Decode return data to values and timestamps
        (uint256 liquidValue, uint48 liquidTimestamp) = abi.decode(liquidData, (uint256, uint48));
        (uint256 stableValue, uint48 stableTimestamp) = abi.decode(stableData, (uint256, uint48));
        (uint256 reservesValue, uint48 reservesTimestamp) = abi.decode(
            reservesData,
            (uint256, uint48)
        );

        // Assert category values and timestamps are correct
        assertEq(liquidValue, RESERVE_VALUE_AT_2 + WETH_VALUE_AT_4000);
        assertEq(liquidTimestamp, uint48(block.timestamp));
        assertEq(stableValue, RESERVE_VALUE_AT_2);
        assertEq(stableTimestamp, uint48(block.timestamp));
        assertEq(reservesValue, RESERVE_VALUE_AT_2);
        assertEq(reservesTimestamp, uint48(block.timestamp));
    }

    //============================================================================================//
    //                                       VALUE METRICS                                        //
    //============================================================================================//

    /// [X]  getMetric(Metric metric_)
    ///     [X]  if latest value was captured at the current timestamp, return that value
    ///     [X]  if latest value was captured at a previous timestamp, fetch and return the current value
    ///     [X]  correctly calculates backing with non-OHM in POL

    function testCorrectness_getMetricCurrentTimestamp() public {
        // Cache current metric value and timestamp
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Get metric value
        uint256 value = appraiser.getMetric(IAppraiser.Metric.BACKING);

        // Assert that metric value is correct
        assertEq(value, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_BACKING_AT_1);
    }

    function testCorrectness_getMetricPreviousTimestamp() public {
        // Cache current metric value and timestamp
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Now update price and timestamp
        vm.warp(block.timestamp + 100);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));
        PRICE.setPrice(address(weth), 4000e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Get metric value
        uint256 value = appraiser.getMetric(IAppraiser.Metric.BACKING);

        // Assert that metric value is correct
        assertEq(value, RESERVE_VALUE_AT_2 + WETH_VALUE_AT_4000 + POL_BACKING_AT_2);
    }

    function testCorrectness_getMetric_backing_POL() public {
        // Cache current metric value and timestamp
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Get metric value
        uint256 value = appraiser.getMetric(IAppraiser.Metric.BACKING);
        // Assert that metric value is correct
        assertEq(value, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_BACKING_AT_1);
    }

    function testCorrectness_getMetricPreviousTimestamp_backing_POL() public {
        // Cache current metric value and timestamp
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Now update price and timestamp
        vm.warp(block.timestamp + 100);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));
        PRICE.setPrice(address(weth), 4000e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Get metric value
        uint256 value = appraiser.getMetric(IAppraiser.Metric.BACKING);
        // Assert that metric value is correct
        assertEq(value, RESERVE_VALUE_AT_2 + WETH_VALUE_AT_4000 + POL_BACKING_AT_2);
    }

    /// [X]  getMetric(Metric metric_, uint48 maxAge_)
    ///     [X]  if latest value was captured more recently than the passed maxAge, return that value
    ///     [X]  if latest value was captured at a too outdated timestamp, fetch and return the current value

    function testCorrectness_getMetricAgeRecentTimestamp(uint48 maxAge_) public {
        vm.assume(maxAge_ > 0 && maxAge_ < 30 days); // test value to avoid overflow situations that just revert

        // Cache current metric value and timestamp
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Now update price and timestamp
        vm.warp(block.timestamp + maxAge_ - 1);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));
        PRICE.setPrice(address(weth), 4000e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Get metric value
        uint256 value = appraiser.getMetric(IAppraiser.Metric.BACKING, maxAge_);

        // Assert that metric value is correct
        assertEq(value, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_BACKING_AT_1);
    }

    function testCorrectness_getMetricAgeOutdatedTimestamp(uint48 maxAge_) public {
        vm.assume(maxAge_ > 0 && maxAge_ < 30 days); // test value to avoid overflow situations that just revert

        // Cache current metric value and timestamp
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Now update price and timestamp
        vm.warp(block.timestamp + maxAge_ + 1);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));
        PRICE.setPrice(address(weth), 4000e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Get metric value
        uint256 value = appraiser.getMetric(IAppraiser.Metric.BACKING, maxAge_);

        // Assert that metric value is correct
        assertEq(value, RESERVE_VALUE_AT_2 + WETH_VALUE_AT_4000 + POL_BACKING_AT_2);
    }

    /// [X]  getMetric(Metric metric_, Variant variant_)
    ///     [X]  reverts if variant is not LAST or CURRENT
    ///     [X]  reverts if metric is not a valid metric
    ///     [X]  gets latest metric value if variant is LAST
    ///     [X]  gets current metric value if variant is CURRENT
    ///     [X]  handles all valid metrics
    ///     [X]  handles volatility metric

    function testCorrectness_getMetricVariantInvalid() public {
        // Cache current metric value and timestamp
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Directly call getMetric with invalid variant
        (bool success, ) = address(appraiser).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", 0, 2)
        );

        // Assert call reverts
        assertEq(success, false);
    }

    function testCorrectness_getMetricVariantInvalidMetric() public {
        // Cache current metric value and timestamp
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Directly call getMetric with invalid metric
        (bool success, ) = address(appraiser).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", 7, 0)
        );

        // Assert call reverts
        assertEq(success, false);
    }

    function testCorrectness_getMetricVariantLast() public {
        uint48 timestampBefore = uint48(block.timestamp);

        // Cache current metric value and timestamp
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Now update price and timestamp
        vm.warp(block.timestamp + 100);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));
        PRICE.setPrice(address(weth), 4000e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Directly call getMetric with variant LAST
        (bool success, bytes memory data) = address(appraiser).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", 0, 1)
        );

        // Assert call succeeded
        assertEq(success, true);

        // Decode return data to value and timestamp
        (uint256 value, uint48 variantTimestamp) = abi.decode(data, (uint256, uint48));

        // Assert value is from cache and cache is unchanged
        assertEq(value, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_BACKING_AT_1);
        assertEq(variantTimestamp, timestampBefore);
    }

    function testCorrectness_getMetricVariantCurrent() public {
        // Cache current metric value and timestamp
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Now update price and timestamp
        vm.warp(block.timestamp + 100);
        PRICE.setPrice(address(reserve), 2e18);
        PRICE.setTimestamp(uint48(block.timestamp));
        PRICE.setPrice(address(weth), 4000e18);
        PRICE.setTimestamp(uint48(block.timestamp));

        // Directly call getMetric with variant CURRENT
        (bool success, bytes memory data) = address(appraiser).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", 0, 0)
        );

        // Assert call succeeded
        assertEq(success, true);

        // Decode return data to value and timestamp
        (uint256 value, uint48 variantTimestamp) = abi.decode(data, (uint256, uint48));

        // Assert value is current but cache is unchanged
        assertEq(value, RESERVE_VALUE_AT_2 + WETH_VALUE_AT_4000 + POL_BACKING_AT_2);
        assertEq(variantTimestamp, uint48(block.timestamp));
    }

    function testCorrectness_getMetricCurrentForAllMetrics() public {
        // Categorize assets
        bookkeeper.categorizeAsset(address(weth), AssetCategory.wrap("illiquid"));

        // Set OHM observations to be all 10
        uint256[] memory ohmObservations = new uint256[](90);
        for (uint256 i; i < 90; i++) {
            ohmObservations[i] = 10e18;
        }
        PRICE.setObservations(address(ohm), ohmObservations);

        // Directly call getMetric with variant CURRENT for all metrics
        (bool backingSuccess, bytes memory backingData) = address(appraiser).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", 0, 0)
        );
        (bool liquidSuccess, bytes memory liquidData) = address(appraiser).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", 1, 0)
        );
        (bool liquidPerOhmSuccess, bytes memory liquidPerOhmData) = address(appraiser).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", 2, 0)
        );
        (bool mvSuccess, bytes memory mvData) = address(appraiser).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", 3, 0)
        );
        (bool mcSuccess, bytes memory mcData) = address(appraiser).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", 4, 0)
        );
        (bool premiumSuccess, bytes memory premiumData) = address(appraiser).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", 5, 0)
        );
        (bool volSuccess, bytes memory volData) = address(appraiser).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", 6, 0)
        );

        // Assert calls succeeded
        assertEq(backingSuccess, true);
        assertEq(liquidSuccess, true);
        assertEq(liquidPerOhmSuccess, true);
        assertEq(mvSuccess, true);
        assertEq(mcSuccess, true);
        assertEq(premiumSuccess, true);
        assertEq(volSuccess, true);

        // Decode return data to values and timestamps
        {
            (uint256 value, uint48 variantTimestamp) = abi.decode(backingData, (uint256, uint48));
            assertEq(value, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_BACKING_AT_1, "BACKING");
            assertEq(variantTimestamp, uint48(block.timestamp));
        }
        {
            (uint256 value, uint48 variantTimestamp) = abi.decode(liquidData, (uint256, uint48));
            assertEq(value, RESERVE_VALUE_AT_1 + POL_BACKING_AT_1, "LIQUID"); // wEth is illiquid, so excluded
            assertEq(variantTimestamp, uint48(block.timestamp));
        }
        {
            (uint256 value, uint48 variantTimestamp) = abi.decode(
                liquidPerOhmData,
                (uint256, uint48)
            );
            // Backed OHM = Floating OHM = All minted OHM - OHM in Protocol Owned Liq
            uint256 expectedBackedSupply = OHM_MINT_BALANCE +
                BALANCER_POOL_OHM_BALANCE -
                BALANCER_POOL_OHM_BALANCE.mulDiv(BPT_BALANCE, BALANCER_POOL_TOTAL_SUPPLY);
            assertEq(
                value,
                (RESERVE_VALUE_AT_1 + POL_BACKING_AT_1).mulDiv(1e9, expectedBackedSupply), // wEth is illiquid, so excluded
                "LIQUID_PER_OHM"
            );
            assertEq(variantTimestamp, uint48(block.timestamp));
        }
        {
            (uint256 value, uint48 variantTimestamp) = abi.decode(mvData, (uint256, uint48));
            uint256 expectedMarketVal = RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_VALUE_AT_1;
            assertEq(
                value,
                RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_VALUE_AT_1,
                "MARKET_VALUE"
            );
            assertEq(variantTimestamp, uint48(block.timestamp));

            uint256 expectedMarketCap = (OHM_MINT_BALANCE + BALANCER_POOL_OHM_BALANCE).mulDiv(
                OHM_PRICE,
                1e9
            );
            (value, variantTimestamp) = abi.decode(mcData, (uint256, uint48));
            assertEq(value, expectedMarketCap, "MARKET_CAP");
            assertEq(variantTimestamp, uint48(block.timestamp));

            // Market cap = circulating supply * price
            assertEq(
                value,
                SPPLY.getMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY).mulDiv(OHM_PRICE, 1e9),
                "MARKET_CAP_VIA_SPPLY"
            );

            (value, variantTimestamp) = abi.decode(premiumData, (uint256, uint48));
            assertEq(value, expectedMarketCap.mulDiv(1e18, expectedMarketVal), "PREMIUM");
            assertEq(variantTimestamp, uint48(block.timestamp));
        }
        {
            (uint256 value, uint48 variantTimestamp) = abi.decode(volData, (uint256, uint48));
            assertEq(value, 0, "VOLATILITY");
            assertEq(variantTimestamp, uint48(block.timestamp));
        }
    }

    function testCorrectness_getMetricVolatility() public {
        // Generate observations
        uint256[] memory observations = new uint256[](90);
        for (uint256 i; i < 90; i++) {
            uint256 counter = i % 3;

            if (counter == 0) {
                observations[i] = 9e18;
                continue;
            } else if (counter == 1) {
                observations[i] = 10e18;
                continue;
            } else {
                observations[i] = 11e18;
                continue;
            }
        }

        // Set observations
        PRICE.setObservations(address(ohm), observations);

        // Directly call getMetric with variant CURRENT for volatility metric
        (bool success, bytes memory data) = address(appraiser).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", 6, 0)
        );

        // Assert call succeeded
        assertEq(success, true);

        // Decode return data to value and timestamp
        (uint256 value, uint48 variantTimestamp) = abi.decode(data, (uint256, uint48));

        // Assert value and timestamp are correct
        assertApproxEqRel(value, 4.486e18, 1e16); // within 1%
        assertEq(variantTimestamp, uint48(block.timestamp));
    }

    //============================================================================================//
    //                                       CACHING                                              //
    //============================================================================================//

    /// [X]  storeAssetValue(address asset_)
    ///     [X]  stores current asset value

    function testCorrectness_storeAssetValue() public {
        // Assert nothing is cached
        (uint256 cacheValue, uint48 timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, 0);
        assertEq(timestamp, 0);

        // Cache current asset value and timestamp
        appraiser.storeAssetValue(address(reserve));

        // Assert value is in cache
        (cacheValue, timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, RESERVE_VALUE_AT_1);
        assertEq(timestamp, uint48(block.timestamp));
    }

    /// [X]  storeCategoryValue(Category category_)
    ///     [X]  stores current category value

    function testCorrectness_storeCategoryValue() public {
        // Assert nothing is cached
        (uint256 cacheValue, uint48 timestamp) = appraiser.categoryValueCache(
            AssetCategory.wrap("liquid")
        );
        assertEq(cacheValue, 0);
        assertEq(timestamp, 0);

        // Cache current category value and timestamp
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));

        // Assert value is in cache
        (cacheValue, timestamp) = appraiser.categoryValueCache(AssetCategory.wrap("liquid"));
        assertEq(cacheValue, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000);
        assertEq(timestamp, uint48(block.timestamp));
    }

    /// [X]  storeMetric(Metric metric_)
    ///     [X]  stores current metric value

    function testCorrectness_storeMetric() public {
        // Assert nothing is cached
        (uint256 cacheValue, uint48 timestamp) = appraiser.metricCache(IAppraiser.Metric.BACKING);
        assertEq(cacheValue, 0);
        assertEq(timestamp, 0);

        // Cache current metric value and timestamp
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Assert value is in cache
        (cacheValue, timestamp) = appraiser.metricCache(IAppraiser.Metric.BACKING);
        assertEq(cacheValue, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_BACKING_AT_1);
        assertEq(timestamp, uint48(block.timestamp));
    }
}

contract MockBalancerPool is IBalancerPool {
    bytes32 internal immutable _poolId;
    uint8 internal _decimals;
    uint256 internal _totalSupply;
    mapping(address => uint256) internal _balanceOf;

    constructor(bytes32 poolId_) {
        _poolId = poolId_;
    }

    function getPoolId() external view returns (bytes32) {
        return _poolId;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function setDecimals(uint8 decimals_) public {
        _decimals = decimals_;
    }

    function setTotalSupply(uint256 totalSupply_) external {
        _totalSupply = totalSupply_;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function setBalance(address address_, uint256 balance_) external {
        _balanceOf[address_] = balance_;
    }

    function balanceOf(address address_) external view override returns (uint256) {
        return _balanceOf[address_];
    }
}
