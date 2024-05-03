// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";
import {FullMath} from "libraries/FullMath.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockMultiplePoolBalancerVault} from "test/mocks/MockBalancerVault.sol";
import {MockIncurDebt} from "test/mocks/MockIncurDebt.sol";

// Modules and Submodules
import "src/Submodules.sol";
import {OlympusSupply, SPPLYv1, Category as SupplyCategory} from "modules/SPPLY/OlympusSupply.sol";
import {OlympusTreasury, TRSRYv1_1, Category as AssetCategory} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles, ROLESv1} from "modules/ROLES/OlympusRoles.sol";

// Policies
import {Appraiser} from "policies/OCA/Appraiser.sol";
import {TreasuryConfig} from "policies/OCA/TreasuryConfig.sol";
import {SupplyConfig} from "policies/OCA/SupplyConfig.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

// Submodules
import {AuraBalancerSupply} from "src/modules/SPPLY/submodules/AuraBalancerSupply.sol";
import {IBalancerPool} from "src/external/balancer/interfaces/IBalancerPool.sol";
import {IAuraRewardPool} from "src/external/aura/interfaces/IAuraRewardPool.sol";
import {IncurDebtSupply} from "src/modules/SPPLY/submodules/IncurDebtSupply.sol";
import {BLVaultSupply} from "src/modules/SPPLY/submodules/BLVaultSupply.sol";
import {SiloSupply} from "src/modules/SPPLY/submodules/SiloSupply.sol";

// Interfaces
import {IAppraiser} from "policies/OCA/interfaces/IAppraiser.sol";

contract AppraiserTest is Test {
    using FullMath for uint256;

    address internal mockHeart;

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
    TreasuryConfig internal treasuryConfig;
    SupplyConfig internal supplyConfig;
    RolesAdmin internal rolesAdmin;

    address internal balancerVaultAddress;

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

        // Addresses
        {
            UserFactory userFactory = new UserFactory();
            address[] memory users = userFactory.create(1);
            mockHeart = users[0];
        }

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
            SPPLY = new OlympusSupply(kernel, tokens, 0, uint32(8 hours));
            ROLES = new OlympusRoles(kernel);
        }

        // Policies
        {
            appraiser = new Appraiser(kernel, 8 hours);
            treasuryConfig = new TreasuryConfig(kernel);
            supplyConfig = new SupplyConfig(kernel);
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
            kernel.executeAction(Actions.ActivatePolicy, address(treasuryConfig));
            kernel.executeAction(Actions.ActivatePolicy, address(supplyConfig));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }

        // Roles management
        {
            // TreasuryConfig roles
            rolesAdmin.grantRole("treasuryconfig_policy", address(this));

            // SupplyConfig roles
            rolesAdmin.grantRole("supplyconfig_admin", address(this));
            rolesAdmin.grantRole("supplyconfig_policy", address(this));

            // Appraiser roles
            rolesAdmin.grantRole("appraiser_admin", address(this));
            rolesAdmin.grantRole("appraiser_store", mockHeart);
        }

        // Configure assets
        {
            // Add assets to Treasury
            address[] memory locations = new address[](0);
            treasuryConfig.addAsset(address(reserve), locations);
            treasuryConfig.addAsset(address(weth), locations);

            locations = new address[](1);
            locations[0] = address(bytes20("POL"));
            treasuryConfig.addAsset(balancerPool, locations);

            // Categorize assets
            treasuryConfig.categorizeAsset(address(reserve), AssetCategory.wrap("liquid"));
            treasuryConfig.categorizeAsset(address(reserve), AssetCategory.wrap("stable"));
            treasuryConfig.categorizeAsset(address(reserve), AssetCategory.wrap("reserves"));
            treasuryConfig.categorizeAsset(address(weth), AssetCategory.wrap("liquid"));
            treasuryConfig.categorizeAsset(address(weth), AssetCategory.wrap("volatile"));
            treasuryConfig.categorizeAsset(
                balancerPool,
                AssetCategory.wrap("protocol-owned-liquidity")
            );

            // Categorize supplies
            supplyConfig.installSubmodule(submoduleAuraBalancerSupply);
            supplyConfig.categorizeSupply(
                address(bytes20("POL")),
                SupplyCategory.wrap("protocol-owned-liquidity")
            );
            supplyConfig.categorizeSupply(daoWallet, SupplyCategory.wrap("dao"));
            supplyConfig.categorizeSupply(
                protocolWallet,
                SupplyCategory.wrap("protocol-owned-treasury")
            );
        }

        {
            // Generate moving average values for LBBO
            uint256[] memory values = new uint256[](30 * 3);
            for (uint256 i = 0; i < 90; i++) {
                if (i < 30) {
                    values[i] = 10e18;
                } else if (i < 60) {
                    values[i] = 11e18;
                } else {
                    values[i] = 12e18;
                }
            }

            // Configure moving average for LBBO on the Appraiser
            appraiser.updateMetricMovingAverage(
                IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
                30 days,
                uint48(block.timestamp),
                values
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
        balancerVaultAddress = address(balancerVault);
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
        vm.prank(mockHeart);
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
        vm.prank(mockHeart);
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
        vm.prank(mockHeart);
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
        vm.prank(mockHeart);
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
    ///     [X]  reverts if variant is not LAST, CURRENT, or MOVINGAVERAGE
    ///     [X]  gets latest asset value if variant is LAST
    ///     [X]  gets current asset value if variant is CURRENT
    ///     [X]  gets moving average asset value if variant is MOVINGAVERAGE

    function testCorrectness_getAssetValueAddressVariantInvalid() public {
        // Cache current asset value and timestamp
        vm.prank(mockHeart);
        appraiser.storeAssetValue(address(reserve));

        // Directly call getAssetValue with invalid variant
        (bool success, ) = address(appraiser).call(
            abi.encodeWithSignature("getAssetValue(address,uint8)", address(reserve), 3)
        );

        // Assert call reverts
        assertEq(success, false);
    }

    function testCorrectness_getAssetValueAddressVariantLast() public {
        uint48 timestampBefore = uint48(block.timestamp);

        // Cache current asset value and timestamp
        vm.prank(mockHeart);
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
        vm.prank(mockHeart);
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

    function testCorrectness_getAssetValueAddressVariantMovingAverage() public {
        uint256[] memory values = new uint256[](90);
        for (uint256 i = 0; i < 90; i++) {
            if (i < 30) {
                values[i] = 9e17;
            } else if (i < 60) {
                values[i] = 1e18;
            } else {
                values[i] = 11e17;
            }
        }

        // Store asset values
        appraiser.updateAssetMovingAverage(
            address(reserve),
            30 days,
            uint48(block.timestamp),
            values
        );

        // Directly call getAssetValue with variant MOVINGAVERAGE
        (bool success, bytes memory data) = address(appraiser).call(
            abi.encodeWithSignature("getAssetValue(address,uint8)", address(reserve), 2)
        );

        // Assert call succeeded
        assertEq(success, true);

        // Decode return data to value
        (uint256 value, uint48 time) = abi.decode(data, (uint256, uint48));

        // Assert response is correct
        assertEq(value, 1e18);
        assertEq(time, uint48(block.timestamp));
    }

    /// [X]  getCategoryValue(Category category_)
    ///     [X]  if latest value was captured at the current timestamp, return that value
    ///     [X]  if latest value was captured at a previous timestamp, fetch and return the current value

    function testCorrectness_getCategoryValueCategoryCurrentTimestamp() public {
        // Cache current category value and timestamp
        vm.startPrank(mockHeart);
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
        appraiser.storeCategoryValue(AssetCategory.wrap("stable"));
        appraiser.storeCategoryValue(AssetCategory.wrap("reserves"));
        vm.stopPrank();

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
        vm.startPrank(mockHeart);
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
        appraiser.storeCategoryValue(AssetCategory.wrap("stable"));
        appraiser.storeCategoryValue(AssetCategory.wrap("reserves"));
        vm.stopPrank();

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
        vm.startPrank(mockHeart);
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
        appraiser.storeCategoryValue(AssetCategory.wrap("stable"));
        appraiser.storeCategoryValue(AssetCategory.wrap("reserves"));
        vm.stopPrank();

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
        vm.startPrank(mockHeart);
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
        appraiser.storeCategoryValue(AssetCategory.wrap("stable"));
        appraiser.storeCategoryValue(AssetCategory.wrap("reserves"));
        vm.stopPrank();

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
    ///     [X]  gets moving average category value if variant is MOVINGAVERAGE

    function testCorrectness_getCategoryValueCategoryVariantInvalid() public {
        // Cache current category value and timestamp
        vm.startPrank(mockHeart);
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
        appraiser.storeCategoryValue(AssetCategory.wrap("stable"));
        appraiser.storeCategoryValue(AssetCategory.wrap("reserves"));
        vm.stopPrank();

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
        vm.startPrank(mockHeart);
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
        appraiser.storeCategoryValue(AssetCategory.wrap("stable"));
        appraiser.storeCategoryValue(AssetCategory.wrap("reserves"));
        vm.stopPrank();

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
        vm.startPrank(mockHeart);
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
        appraiser.storeCategoryValue(AssetCategory.wrap("stable"));
        appraiser.storeCategoryValue(AssetCategory.wrap("reserves"));
        vm.stopPrank();

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

    function testCorrectness_getCategoryValueCategoryVariantMovingAverage() public {
        // Create moving average observations
        uint256[] memory values = new uint256[](90);
        for (uint256 i = 0; i < 90; i++) {
            if (i < 30) {
                values[i] = 1_000_000e18;
            } else if (i < 60) {
                values[i] = 2_000_000e18;
            } else {
                values[i] = 3_000_000e18;
            }
        }
        appraiser.updateCategoryMovingAverage(
            AssetCategory.wrap("liquid"),
            30 days,
            uint48(block.timestamp),
            values
        );

        // Directly call getCategoryValue with valid variant
        (bool liquidSuccess, bytes memory liquidData) = address(appraiser).call(
            abi.encodeWithSignature(
                "getCategoryValue(bytes32,uint8)",
                AssetCategory.wrap("liquid"),
                2
            )
        );

        // Assert calls succeeded
        assertEq(liquidSuccess, true);

        // Decode return data to values and timestamps
        (uint256 liquidValue, uint48 liquidTimestamp) = abi.decode(liquidData, (uint256, uint48));

        // Assert category values and timestamps are correct
        assertEq(liquidValue, 2_000_000e18);
        assertEq(liquidTimestamp, uint48(block.timestamp));
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
        vm.prank(mockHeart);
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Get metric value
        uint256 value = appraiser.getMetric(IAppraiser.Metric.BACKING);

        // Assert that metric value is correct
        assertEq(value, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_BACKING_AT_1);
    }

    function testCorrectness_getMetric_backing_incurDebt() public {
        // Set up the incurDebt submodule, which will return a single-length reserves array
        uint256 TOTAL_DEBT = 1000e9;
        MockIncurDebt incurDebt = new MockIncurDebt(TOTAL_DEBT);
        IncurDebtSupply submoduleIncurDebtSupply = new IncurDebtSupply(SPPLY, address(incurDebt));
        supplyConfig.installSubmodule(submoduleIncurDebtSupply);

        // Cache current metric value and timestamp
        vm.prank(mockHeart);
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Get metric value
        uint256 value = appraiser.getMetric(IAppraiser.Metric.BACKING);

        // Assert that metric value is correct
        assertEq(value, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_BACKING_AT_1);
    }

    function testCorrectness_getMetric_backing_blVault() public {
        // Set up the BLVault submodule with no vault managers
        address[] memory vaultManagers = new address[](0);
        BLVaultSupply submoduleBLVaultSupply = new BLVaultSupply(
            SPPLY,
            balancerVaultAddress,
            vaultManagers
        );
        supplyConfig.installSubmodule(submoduleBLVaultSupply);

        // Cache current metric value and timestamp
        vm.prank(mockHeart);
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Get metric value
        uint256 value = appraiser.getMetric(IAppraiser.Metric.BACKING);

        // Assert that metric value is correct
        assertEq(value, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_BACKING_AT_1);
    }

    function testCorrectness_getMetric_backing_silo() public {
        // Set up the SiloSupply submodule
        SiloSupply submoduleSiloSupply = new SiloSupply(SPPLY, address(0), address(0), address(0));
        supplyConfig.installSubmodule(submoduleSiloSupply);

        // Cache current metric value and timestamp
        vm.prank(mockHeart);
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Get metric value
        uint256 value = appraiser.getMetric(IAppraiser.Metric.BACKING);

        // Assert that metric value is correct
        assertEq(value, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_BACKING_AT_1);
    }

    function testCorrectness_getMetricPreviousTimestamp() public {
        // Cache current metric value and timestamp
        vm.prank(mockHeart);
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
        vm.prank(mockHeart);
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Get metric value
        uint256 value = appraiser.getMetric(IAppraiser.Metric.BACKING);
        // Assert that metric value is correct
        assertEq(value, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_BACKING_AT_1);
    }

    function testCorrectness_getMetricPreviousTimestamp_backing_POL() public {
        // Cache current metric value and timestamp
        vm.prank(mockHeart);
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
        vm.prank(mockHeart);
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
        vm.prank(mockHeart);
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
    ///     [X]  gets moving average metric value if variant is MOVINGAVERAGE
    ///     [X]  handles all valid metrics
    ///     [X]  handles volatility metric

    function testCorrectness_getMetricVariantInvalid() public {
        // Cache current metric value and timestamp
        vm.prank(mockHeart);
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
        vm.prank(mockHeart);
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
        vm.prank(mockHeart);
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
        vm.prank(mockHeart);
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

    function testCorrectness_getMetricVariantMovingAverage() public {
        // Create moving average observations
        uint256[] memory values = new uint256[](90);
        for (uint256 i = 0; i < 90; i++) {
            if (i < 30) {
                values[i] = 10e18;
            } else if (i < 60) {
                values[i] = 11e18;
            } else {
                values[i] = 12e18;
            }
        }
        appraiser.updateMetricMovingAverage(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
            30 days,
            uint48(block.timestamp),
            values
        );

        // Directly call getMetric with variant MOVINGAVERAGE
        (bool success, bytes memory data) = address(appraiser).call(
            abi.encodeWithSignature("getMetric(uint8,uint8)", 2, 2)
        );

        // Assert call succeeded
        assertEq(success, true);

        // Decode return data to value and timestamp
        (uint256 value, uint48 variantTimestamp) = abi.decode(data, (uint256, uint48));

        // Assert value is from moving average and cache is unchanged
        assertEq(value, 11e18);
        assertEq(variantTimestamp, uint48(block.timestamp));
    }

    function testCorrectness_getMetricCurrentForAllMetrics() public {
        // Categorize assets
        treasuryConfig.categorizeAsset(address(weth), AssetCategory.wrap("illiquid"));

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
        vm.prank(mockHeart);
        appraiser.storeAssetValue(address(reserve));

        // Assert value is in cache
        (cacheValue, timestamp) = appraiser.assetValueCache(address(reserve));
        assertEq(cacheValue, RESERVE_VALUE_AT_1);
        assertEq(timestamp, uint48(block.timestamp));
    }

    function testReverts_storeAssetValue_unauthorized() public {
        // Call storeAssetValue with unauthorized user
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("appraiser_store")
        );
        vm.expectRevert(err);

        appraiser.storeAssetValue(address(reserve));
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
        vm.prank(mockHeart);
        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));

        // Assert value is in cache
        (cacheValue, timestamp) = appraiser.categoryValueCache(AssetCategory.wrap("liquid"));
        assertEq(cacheValue, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000);
        assertEq(timestamp, uint48(block.timestamp));
    }

    function testReverts_storeCategoryValue_unauthorized() public {
        // Call storeCategoryValue with unauthorized user
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("appraiser_store")
        );
        vm.expectRevert(err);

        appraiser.storeCategoryValue(AssetCategory.wrap("liquid"));
    }

    /// [X]  storeMetric(Metric metric_)
    ///     [X]  stores current metric value

    function testCorrectness_storeMetric() public {
        // Assert nothing is cached
        (uint256 cacheValue, uint48 timestamp) = appraiser.metricCache(IAppraiser.Metric.BACKING);
        assertEq(cacheValue, 0);
        assertEq(timestamp, 0);

        // Cache current metric value and timestamp
        vm.prank(mockHeart);
        appraiser.storeMetric(IAppraiser.Metric.BACKING);

        // Assert value is in cache
        (cacheValue, timestamp) = appraiser.metricCache(IAppraiser.Metric.BACKING);
        assertEq(cacheValue, RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_BACKING_AT_1);
        assertEq(timestamp, uint48(block.timestamp));
    }

    function testReverts_storeMetric_unauthorized() public {
        // Call storeMetric with unauthorized user
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("appraiser_store")
        );
        vm.expectRevert(err);

        appraiser.storeMetric(IAppraiser.Metric.BACKING);
    }

    //============================================================================================//
    //                                       MOVING AVERAGES                                      //
    //============================================================================================//

    /// [X]  updateAssetMovingAverage
    ///     [X]  can only be called by appraiser_admin
    ///     [X]  reverts if passed observation time is in the future
    ///     [X]  reverts if moving average duration is 0
    ///     [X]  reverts if moving average duration is not divisible by observation frequency
    ///     [X]  reverts if moving average duration is not long enough
    ///     [X]  reverts if passed observations is incorrect length
    ///     [X]  reverts if any passed observations are 0
    ///     [X]  sets moving average observations
    ///     [X]  overrides previous moving average observations if they existed

    function testCorrectness_updateAssetMovingAverageOnlyCallableByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        // Call updateAssetMovingAverage with non-admin user
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("appraiser_admin")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        appraiser.updateAssetMovingAverage(
            address(reserve),
            30 days,
            uint48(block.timestamp),
            new uint256[](90)
        );
    }

    function testCorrectness_updateAssetMovingAverageRevertsIfObsTimeInFuture(
        uint48 obsTime_
    ) public {
        vm.assume(obsTime_ > block.timestamp + 1 days);

        // Call updateAssetMovingAverage with observation time in the future
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsLastObservationTimeInvalid_Asset(address,uint48,uint48)",
            address(reserve),
            obsTime_,
            uint48(block.timestamp)
        );
        vm.expectRevert(err);
        appraiser.updateAssetMovingAverage(address(reserve), 30 days, obsTime_, new uint256[](90));
    }

    function testCorrectness_updateAssetMovingAverageRevertsIfDurationIsZero() public {
        // Call updateAssetMovingAverage with duration 0
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsMovingAverageDurationInvalid_Asset(address,uint32,uint32)",
            address(reserve),
            0,
            8 hours
        );
        vm.expectRevert(err);
        appraiser.updateAssetMovingAverage(
            address(reserve),
            0,
            uint48(block.timestamp),
            new uint256[](90)
        );
    }

    function testCorrectness_updateAssetMovingAverageRevertsIfDurationNotDivisibleByFrequency()
        public
    {
        // Call updateAssetMovingAverage with duration not divisible by frequency
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsMovingAverageDurationInvalid_Asset(address,uint32,uint32)",
            address(reserve),
            26 hours,
            8 hours
        );
        vm.expectRevert(err);
        appraiser.updateAssetMovingAverage(
            address(reserve),
            26 hours,
            uint48(block.timestamp),
            new uint256[](90)
        );
    }

    function testCorrectness_updateAssetMovingAverageRevertsIfDurationNotLongEnough() public {
        // Call updateAssetMovingAverage with duration not long enough
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsInvalidObservationCount_Asset(address,uint256,uint256)",
            address(reserve),
            1,
            1
        );
        vm.expectRevert(err);
        appraiser.updateAssetMovingAverage(
            address(reserve),
            8 hours,
            uint48(block.timestamp),
            new uint256[](1)
        );
    }

    function testCorrectness_updateAssetMovingAverageRevertsIfObservationsIncorrectLength() public {
        // Call updateAssetMovingAverage with incorrect length observations
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsInvalidObservationCount_Asset(address,uint256,uint256)",
            address(reserve),
            1,
            90
        );
        vm.expectRevert(err);
        appraiser.updateAssetMovingAverage(
            address(reserve),
            30 days,
            uint48(block.timestamp),
            new uint256[](1)
        );
    }

    function testCorrectness_updateAssetMovingAverageRevertsIfAnyObservationsZero() public {
        // Call updateAssetMovingAverage with 0 observations
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsObservationZero_Asset(address,uint256)",
            address(reserve),
            0
        );
        vm.expectRevert(err);
        appraiser.updateAssetMovingAverage(
            address(reserve),
            30 days,
            uint48(block.timestamp),
            new uint256[](90)
        );
    }

    function testCorrectness_updateAssetMovingAverageSetsObservations() public {
        Appraiser.MovingAverage memory ma = appraiser.getAssetMovingAverageData(address(reserve));
        assertEq(ma.obs.length, 0);

        // Create observations
        uint256[] memory observations = new uint256[](90);
        for (uint256 i; i < 90; i++) {
            observations[i] = 10e18;
        }

        // Call updateAssetMovingAverage
        appraiser.updateAssetMovingAverage(
            address(reserve),
            30 days,
            uint48(block.timestamp),
            observations
        );

        // Assert observations are set
        ma = appraiser.getAssetMovingAverageData(address(reserve));
        assertEq(ma.obs.length, 90);
        for (uint256 i; i < 90; i++) {
            assertEq(ma.obs[i], 10e18);
        }
    }

    function testCorrectness_updateAssetMovingAverageOverridesPreviousObservations() public {
        // Create observations
        uint256[] memory observations = new uint256[](90);
        for (uint256 i; i < 90; i++) {
            observations[i] = 10e18;
        }

        // Call updateAssetMovingAverage
        appraiser.updateAssetMovingAverage(
            address(reserve),
            30 days,
            uint48(block.timestamp),
            observations
        );

        // Assert observations are set
        Appraiser.MovingAverage memory ma = appraiser.getAssetMovingAverageData(address(reserve));
        assertEq(ma.obs.length, 90);
        for (uint256 i; i < 90; i++) {
            assertEq(ma.obs[i], 10e18);
        }

        // Create new observations
        uint256[] memory newObservations = new uint256[](90);
        for (uint256 i; i < 90; i++) {
            newObservations[i] = 11e18;
        }

        // Call updateAssetMovingAverage again
        appraiser.updateAssetMovingAverage(
            address(reserve),
            30 days,
            uint48(block.timestamp),
            newObservations
        );

        // Assert new observations are set
        ma = appraiser.getAssetMovingAverageData(address(reserve));
        assertEq(ma.obs.length, 90);
        for (uint256 i; i < 90; i++) {
            assertEq(ma.obs[i], 11e18);
        }
    }

    /// [X]  storeAssetObservation
    ///     [X]  can only be called by appraiser_store
    ///     [X]  reverts if not enough time has passed since last observation
    ///     [X]  updates the moving average data

    function testCorrectness_storeAssetObservationOnlyCallableByStore(address user_) public {
        vm.assume(user_ != address(mockHeart));

        // Call storeAssetObservation with non-store user
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("appraiser_store")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        appraiser.storeAssetObservation(address(reserve));
    }

    function testCorrectness_storeAssetObservationRevertsIfNotEnoughTimePassed() public {
        // Set up moving average observations
        uint256[] memory values = new uint256[](90);
        for (uint256 i = 0; i < 90; i++) {
            values[i] = 10e18;
        }
        appraiser.updateAssetMovingAverage(
            address(reserve),
            30 days,
            uint48(block.timestamp),
            values
        );

        // Call storeAssetObservation with not enough time passed
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_InsufficientTimeElapsed_Asset(address,uint48)",
            address(reserve),
            uint48(block.timestamp)
        );
        vm.expectRevert(err);
        vm.prank(mockHeart);
        appraiser.storeAssetObservation(address(reserve));
    }

    function testCorrectness_storeAssetObservationUpdatesMovingAverageData() public {
        // Set up moving average observations
        uint256[] memory values = new uint256[](90);
        for (uint256 i = 0; i < 90; i++) {
            values[i] = 10e18;
        }
        appraiser.updateAssetMovingAverage(
            address(reserve),
            30 days,
            uint48(block.timestamp),
            values
        );

        // Change price and store
        vm.warp(block.timestamp + 8 hours + 1);
        PRICE.setPrice(address(reserve), 2e18);
        vm.prank(mockHeart);
        appraiser.storeAssetObservation(address(reserve));

        // Assert moving average data is updated
        Appraiser.MovingAverage memory ma = appraiser.getAssetMovingAverageData(address(reserve));
        assertEq(ma.obs[0], RESERVE_VALUE_AT_2);
        assertEq(ma.obs[1], 10e18);
        assertEq(ma.nextObsIndex, 1);
        assertEq(ma.lastObservationTime, uint48(block.timestamp));
        assertEq(ma.cumulativeObs, 10e18 * 89 + RESERVE_VALUE_AT_2);
    }

    /// [X]  updateCategoryMovingAverage
    ///     [X]  can only be called by appraiser_admin
    ///     [X]  reverts if passed observation time is in the future
    ///     [X]  reverts if moving average duration is 0
    ///     [X]  reverts if moving average duration is not divisible by observation frequency
    ///     [X]  reverts if moving average duration is not long enough
    ///     [X]  reverts if passed observations is incorrect length
    ///     [X]  reverts if any passed observations are 0
    ///     [X]  sets moving average observations
    ///     [X]  overrides previous moving average observations if they existed

    function testCorrectness_updateCategoryMovingAverageOnlyCallableByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        // Call updateCategoryMovingAverage with non-admin user
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("appraiser_admin")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        appraiser.updateCategoryMovingAverage(
            AssetCategory.wrap("liquid"),
            30 days,
            uint48(block.timestamp),
            new uint256[](90)
        );
    }

    function testCorrectness_updateCategoryMovingAverageRevertsIfObsTimeInFuture(
        uint48 obsTime_
    ) public {
        vm.assume(obsTime_ > block.timestamp + 1 days);

        // Call updateCategoryMovingAverage with observation time in the future
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsLastObservationTimeInvalid_Category(bytes32,uint48,uint48)",
            AssetCategory.wrap("liquid"),
            obsTime_,
            uint48(block.timestamp)
        );
        vm.expectRevert(err);
        appraiser.updateCategoryMovingAverage(
            AssetCategory.wrap("liquid"),
            30 days,
            obsTime_,
            new uint256[](90)
        );
    }

    function testCorrectness_updateCategoryMovingAverageRevertsIfDurationIsZero() public {
        // Call updateCategoryMovingAverage with duration 0
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsMovingAverageDurationInvalid_Category(bytes32,uint32,uint32)",
            AssetCategory.wrap("liquid"),
            0,
            8 hours
        );
        vm.expectRevert(err);
        appraiser.updateCategoryMovingAverage(
            AssetCategory.wrap("liquid"),
            0,
            uint48(block.timestamp),
            new uint256[](90)
        );
    }

    function testCorrectness_updateCategoryMovingAverageRevertsIfDurationNotDivisibleByFrequency()
        public
    {
        // Call updateCategoryMovingAverage with duration not divisible by frequency
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsMovingAverageDurationInvalid_Category(bytes32,uint32,uint32)",
            AssetCategory.wrap("liquid"),
            26 hours,
            8 hours
        );
        vm.expectRevert(err);
        appraiser.updateCategoryMovingAverage(
            AssetCategory.wrap("liquid"),
            26 hours,
            uint48(block.timestamp),
            new uint256[](90)
        );
    }

    function testCorrectness_updateCategoryMovingAverageRevertsIfDurationNotLongEnough() public {
        // Call updateCategoryMovingAverage with duration not long enough
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsInvalidObservationCount_Category(bytes32,uint256,uint256)",
            AssetCategory.wrap("liquid"),
            1,
            1
        );
        vm.expectRevert(err);
        appraiser.updateCategoryMovingAverage(
            AssetCategory.wrap("liquid"),
            8 hours,
            uint48(block.timestamp),
            new uint256[](1)
        );
    }

    function testCorrectness_updateCategoryMovingAverageRevertsIfObservationsIncorrectLength()
        public
    {
        // Call updateCategoryMovingAverage with incorrect length observations
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsInvalidObservationCount_Category(bytes32,uint256,uint256)",
            AssetCategory.wrap("liquid"),
            1,
            90
        );
        vm.expectRevert(err);
        appraiser.updateCategoryMovingAverage(
            AssetCategory.wrap("liquid"),
            30 days,
            uint48(block.timestamp),
            new uint256[](1)
        );
    }

    function testCorrectness_updateCategoryMovingAverageRevertsIfAnyObservationsZero() public {
        // Call updateCategoryMovingAverage with 0 observations
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsObservationZero_Category(bytes32,uint256)",
            AssetCategory.wrap("liquid"),
            0
        );
        vm.expectRevert(err);
        appraiser.updateCategoryMovingAverage(
            AssetCategory.wrap("liquid"),
            30 days,
            uint48(block.timestamp),
            new uint256[](90)
        );
    }

    function testCorrectness_updateCategoryMovingAverageSetsObservations() public {
        Appraiser.MovingAverage memory ma = appraiser.getCategoryMovingAverageData(
            AssetCategory.wrap("liquid")
        );
        assertEq(ma.obs.length, 0);

        // Create observations
        uint256[] memory observations = new uint256[](90);
        for (uint256 i; i < 90; i++) {
            observations[i] = 10e18;
        }

        // Call updateCategoryMovingAverage
        appraiser.updateCategoryMovingAverage(
            AssetCategory.wrap("liquid"),
            30 days,
            uint48(block.timestamp),
            observations
        );

        // Assert observations are set
        ma = appraiser.getCategoryMovingAverageData(AssetCategory.wrap("liquid"));
        assertEq(ma.obs.length, 90);
        for (uint256 i; i < 90; i++) {
            assertEq(ma.obs[i], 10e18);
        }
    }

    function testCorrectness_updateCategoryMovingAverageOverridesPreviousObservations() public {
        // Create observations
        uint256[] memory observations = new uint256[](90);
        for (uint256 i; i < 90; i++) {
            observations[i] = 10e18;
        }

        // Call updateCategoryMovingAverage
        appraiser.updateCategoryMovingAverage(
            AssetCategory.wrap("liquid"),
            30 days,
            uint48(block.timestamp),
            observations
        );

        // Assert observations are set
        Appraiser.MovingAverage memory ma = appraiser.getCategoryMovingAverageData(
            AssetCategory.wrap("liquid")
        );
        assertEq(ma.obs.length, 90);
        for (uint256 i; i < 90; i++) {
            assertEq(ma.obs[i], 10e18);
        }

        // Create new observations
        uint256[] memory newObservations = new uint256[](90);
        for (uint256 i; i < 90; i++) {
            newObservations[i] = 11e18;
        }

        // Call updateCategoryMovingAverage again
        appraiser.updateCategoryMovingAverage(
            AssetCategory.wrap("liquid"),
            30 days,
            uint48(block.timestamp),
            newObservations
        );

        // Assert new observations are set
        ma = appraiser.getCategoryMovingAverageData(AssetCategory.wrap("liquid"));
        assertEq(ma.obs.length, 90);
        for (uint256 i; i < 90; i++) {
            assertEq(ma.obs[i], 11e18);
        }
    }

    /// [X]  storeCategoryObservation
    ///     [X]  can only be called by appraiser_store
    ///     [X]  reverts if not enough time has passed since last observation
    ///     [X]  updates the moving average data

    function testCorrectness_storeCategoryObservationOnlyCallableByStore(address user_) public {
        vm.assume(user_ != address(mockHeart));

        // Call storeCategoryObservation with non-store user
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("appraiser_store")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        appraiser.storeCategoryObservation(AssetCategory.wrap("liquid"));
    }

    function testCorrectness_storeCategoryObservationRevertsIfNotEnoughTimePassed() public {
        // Set up moving average observations
        uint256[] memory values = new uint256[](90);
        for (uint256 i = 0; i < 90; i++) {
            values[i] = 10e18;
        }
        appraiser.updateCategoryMovingAverage(
            AssetCategory.wrap("liquid"),
            30 days,
            uint48(block.timestamp),
            values
        );

        // Call storeCategoryObservation with not enough time passed
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_InsufficientTimeElapsed_Category(bytes32,uint48)",
            AssetCategory.wrap("liquid"),
            uint48(block.timestamp)
        );
        vm.expectRevert(err);
        vm.prank(mockHeart);
        appraiser.storeCategoryObservation(AssetCategory.wrap("liquid"));
    }

    function testCorrectness_storeCategoryObservationUpdatesMovingAverageData() public {
        // Set up moving average observations
        uint256[] memory values = new uint256[](90);
        for (uint256 i = 0; i < 90; i++) {
            values[i] = 10e18;
        }
        appraiser.updateCategoryMovingAverage(
            AssetCategory.wrap("liquid"),
            30 days,
            uint48(block.timestamp),
            values
        );

        // Change price and store
        vm.warp(block.timestamp + 8 hours + 1);
        vm.prank(mockHeart);
        appraiser.storeCategoryObservation(AssetCategory.wrap("liquid"));

        // Assert moving average data is updated
        Appraiser.MovingAverage memory ma = appraiser.getCategoryMovingAverageData(
            AssetCategory.wrap("liquid")
        );
        assertEq(ma.obs[0], RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000);
        assertEq(ma.obs[1], 10e18);
        assertEq(ma.nextObsIndex, 1);
        assertEq(ma.lastObservationTime, uint48(block.timestamp));
        assertEq(ma.cumulativeObs, 10e18 * 89 + RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000);
    }

    /// [X]  updateMetricMovingAverage
    ///     [X]  can only be called by appraiser_admin
    ///     [X]  reverts if passed observation time is in the future
    ///     [X]  reverts if moving average duration is 0
    ///     [X]  reverts if moving average duration is not divisible by observation frequency
    ///     [X]  reverts if moving average duration is not long enough
    ///     [X]  reverts if passed observations is incorrect length
    ///     [X]  reverts if any passed observations are 0
    ///     [X]  sets moving average observations
    ///     [X]  overrides previous moving average observations if they existed

    function testCorrectness_updateMetricMovingAverageOnlyCallableByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        // Call updateMetricMovingAverage with non-admin user
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("appraiser_admin")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        appraiser.updateMetricMovingAverage(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
            30 days,
            uint48(block.timestamp),
            new uint256[](90)
        );
    }

    function testCorrectness_updateMetricMovingAverageRevertsIfObsTimeInFuture(
        uint48 obsTime_
    ) public {
        vm.assume(obsTime_ > block.timestamp + 1 days);

        // Call updateMetricMovingAverage with observation time in the future
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsLastObservationTimeInvalid_Metric(uint8,uint48,uint48)",
            2,
            obsTime_,
            uint48(block.timestamp)
        );
        vm.expectRevert(err);
        appraiser.updateMetricMovingAverage(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
            30 days,
            obsTime_,
            new uint256[](90)
        );
    }

    function testCorrectness_updateMetricMovingAverageRevertsIfDurationIsZero() public {
        // Call updateMetricMovingAverage with duration 0
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsMovingAverageDurationInvalid_Metric(uint8,uint32,uint32)",
            2,
            0,
            8 hours
        );
        vm.expectRevert(err);
        appraiser.updateMetricMovingAverage(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
            0,
            uint48(block.timestamp),
            new uint256[](90)
        );
    }

    function testCorrectness_updateMetricMovingAverageRevertsIfDurationNotDivisibleByFrequency()
        public
    {
        // Call updateMetricMovingAverage with duration not divisible by frequency
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsMovingAverageDurationInvalid_Metric(uint8,uint32,uint32)",
            2,
            26 hours,
            8 hours
        );
        vm.expectRevert(err);
        appraiser.updateMetricMovingAverage(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
            26 hours,
            uint48(block.timestamp),
            new uint256[](90)
        );
    }

    function testCorrectness_updateMetricMovingAverageRevertsIfDurationNotLongEnough() public {
        // Call updateMetricMovingAverage with duration not long enough
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsInvalidObservationCount_Metric(uint8,uint256,uint256)",
            2,
            1,
            1
        );
        vm.expectRevert(err);
        appraiser.updateMetricMovingAverage(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
            8 hours,
            uint48(block.timestamp),
            new uint256[](1)
        );
    }

    function testCorrectness_updateMetricMovingAverageRevertsIfObservationsIncorrectLength()
        public
    {
        // Call updateMetricMovingAverage with incorrect length observations
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsInvalidObservationCount_Metric(uint8,uint256,uint256)",
            2,
            1,
            90
        );
        vm.expectRevert(err);
        appraiser.updateMetricMovingAverage(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
            30 days,
            uint48(block.timestamp),
            new uint256[](1)
        );
    }

    function testCorrectness_updateMetricMovingAverageRevertsIfAnyObservationsZero() public {
        // Call updateMetricMovingAverage with 0 observations
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_ParamsObservationZero_Metric(uint8,uint256)",
            2,
            0
        );
        vm.expectRevert(err);
        appraiser.updateMetricMovingAverage(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
            30 days,
            uint48(block.timestamp),
            new uint256[](90)
        );
    }

    function testCorrectness_updateMetricMovingAverageSetsObservations() public {
        Appraiser.MovingAverage memory ma = appraiser.getMetricMovingAverageData(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM
        );
        assertEq(ma.obs.length, 90); // Already set in setUp()

        // Create observations
        uint256[] memory observations = new uint256[](90);
        for (uint256 i; i < 90; i++) {
            observations[i] = 10e18;
        }

        // Call updateMetricMovingAverage
        appraiser.updateMetricMovingAverage(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
            30 days,
            uint48(block.timestamp),
            observations
        );

        // Assert observations are set
        ma = appraiser.getMetricMovingAverageData(IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM);
        assertEq(ma.obs.length, 90);
        for (uint256 i; i < 90; i++) {
            assertEq(ma.obs[i], 10e18);
        }
    }

    function testCorrectness_updateMetricMovingAverageOverridesPreviousObservations() public {
        // Create observations
        uint256[] memory observations = new uint256[](90);
        for (uint256 i; i < 90; i++) {
            observations[i] = 10e18;
        }

        // Call updateMetricMovingAverage
        appraiser.updateMetricMovingAverage(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
            30 days,
            uint48(block.timestamp),
            observations
        );

        // Assert observations are set
        Appraiser.MovingAverage memory ma = appraiser.getMetricMovingAverageData(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM
        );
        assertEq(ma.obs.length, 90);
        for (uint256 i; i < 90; i++) {
            assertEq(ma.obs[i], 10e18);
        }

        // Create new observations
        uint256[] memory newObservations = new uint256[](90);
        for (uint256 i; i < 90; i++) {
            newObservations[i] = 11e18;
        }

        // Call updateMetricMovingAverage again
        appraiser.updateMetricMovingAverage(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
            30 days,
            uint48(block.timestamp),
            newObservations
        );

        // Assert new observations are set
        ma = appraiser.getMetricMovingAverageData(IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM);
        assertEq(ma.obs.length, 90);
        for (uint256 i; i < 90; i++) {
            assertEq(ma.obs[i], 11e18);
        }
    }

    /// [X]  storeMetricObservation
    ///     [X]  can only be called by appraiser_store
    ///     [X]  reverts if not enough time has passed since last observation
    ///     [X]  updates the moving average data

    function testCorrectness_storeMetricObservationOnlyCallableByStore(address user_) public {
        vm.assume(user_ != address(mockHeart));

        // Call storeMetricObservation with non-store user
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("appraiser_store")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        appraiser.storeMetricObservation(IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM);
    }

    function testCorrectness_storeMetricObservationRevertsIfNotEnoughTimePassed() public {
        // Set up moving average observations
        uint256[] memory values = new uint256[](90);
        for (uint256 i = 0; i < 90; i++) {
            values[i] = 10e18;
        }
        appraiser.updateMetricMovingAverage(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
            30 days,
            uint48(block.timestamp),
            values
        );

        // Call storeMetricObservation with not enough time passed
        bytes memory err = abi.encodeWithSignature(
            "Appraiser_InsufficientTimeElapsed_Metric(uint8,uint48)",
            2,
            uint48(block.timestamp)
        );
        vm.expectRevert(err);
        vm.prank(mockHeart);
        appraiser.storeMetricObservation(IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM);
    }

    function testCorrectness_storeMetricObservationUpdatesMovingAverageData() public {
        // Set up moving average observations
        uint256[] memory values = new uint256[](90);
        for (uint256 i = 0; i < 90; i++) {
            values[i] = 10e18;
        }
        appraiser.updateMetricMovingAverage(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
            30 days,
            uint48(block.timestamp),
            values
        );

        // Change price and store
        vm.warp(block.timestamp + 8 hours + 1);
        vm.prank(mockHeart);
        appraiser.storeMetricObservation(IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM);

        // Assert moving average data is updated
        // Backed OHM = Floating OHM = All minted OHM - OHM in Protocol Owned Liq
        uint256 expectedBackedSupply = OHM_MINT_BALANCE +
            BALANCER_POOL_OHM_BALANCE -
            BALANCER_POOL_OHM_BALANCE.mulDiv(BPT_BALANCE, BALANCER_POOL_TOTAL_SUPPLY);
        Appraiser.MovingAverage memory ma = appraiser.getMetricMovingAverageData(
            IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM
        );
        assertEq(
            ma.obs[0],
            ((RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_BACKING_AT_1) * 1e9) /
                expectedBackedSupply
        );
        assertEq(ma.obs[1], 10e18);
        assertEq(ma.nextObsIndex, 1);
        assertEq(ma.lastObservationTime, uint48(block.timestamp));
        assertEq(
            ma.cumulativeObs,
            10e18 *
                89 +
                (((RESERVE_VALUE_AT_1 + WETH_VALUE_AT_2000 + POL_BACKING_AT_1) * 1e9) /
                    expectedBackedSupply)
        );
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
