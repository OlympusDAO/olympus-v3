// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {MockVaultManager} from "test/mocks/MockBLVaultManager.sol";

import "src/Submodules.sol";
import {Bookkeeper} from "policies/OCA/Bookkeeper.sol";
import {OlympusPricev2, PRICEv2, PriceSubmodule} from "modules/PRICE/OlympusPrice.v2.sol";
import {OlympusSupply, SPPLYv1, Category as SupplyCategory, SupplySubmodule} from "modules/SPPLY/OlympusSupply.sol";
import {OlympusTreasury, TRSRYv1_1, CategoryGroup as AssetCategoryGroup, Category as AssetCategory} from "modules/TRSRY/OlympusTreasury.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {BLVaultSupply} from "src/modules/SPPLY/submodules/BLVaultSupply.sol";

// Tests for Bookkeeper v1.0.0
//
// Bookkeeper Setup and Permissions
// [X] configureDependencies
// [X] requestPermissions
//
// PRICEv2 Configuration
// [X] addAssetPrice
//     [X] only "bookkeeper_policy" role can call
//     [X] inputs to PRICEv2.addAsset are correct
// [X] removeAssetPrice
//     [X] only "bookkeeper_policy" role can call
//     [X] inputs to PRICEv2.removeAsset are correct
// [X] updateAssetPriceFeeds
//     [X] only "bookkeeper_policy" role can call
//     [X] inputs to PRICEv2.updateAssetPriceFeeds are correct
// [X] updateAssetPriceStrategy
//     [X] only "bookkeeper_policy" role can call
//     [X] inputs to PRICEv2.updateAssetPriceStrategy are correct
// [X] updateAssetMovingAverage
//     [X] only "bookkeeper_policy" role can call
//     [X] inputs to PRICEv2.updateAssetMovingAverage are correct
//
// PRICEv2 Submodule Installation/Upgrade
// [X] installSubmodule
//     [X] only "bookkeeper_admin" role can call
//     [X] inputs to PRICEv2.installSubmodule are correct
//     [X] inputs to SPPLYv1.installSubmodule are correct
// [X] upgradeSubmodule
//     [X] only "bookkeeper_admin" role can call
//     [X] inputs to PRICEv2.upgradeSubmodule are correct
//     [X] inputs to SPPLYv1.upgradeSubmodule are correct
//
// SPPLYv1 Configuration
// [X] addAsset
//     [X] only "bookkeeper_policy" role can call
//     [X] inputs to TRSRY.addAsset are correct
// [X] addAssetLocation
//     [X] only "bookkeeper_policy" role can call
//     [X] inputs to TRSRY.addAssetLocation are correct
// [X] removeAssetLocation
//     [X] only "bookkeeper_policy" role can call
//     [X] inputs to TRSRY.removeAssetLocation are correct
// [X] addAssetCategoryGroup
//     [X] only "bookkeeper_policy" role can call
//     [X] inputs to TRSRY.addAssetCategoryGroup are correct
// [X] addAssetCategory
//     [X] only "bookkeeper_policy" role can call
//     [X] inputs to TRSRY.addAssetCategory are correct
// [X] categorize
//     [X] only "bookkeeper_policy" role can call
//     [X] inputs to TRSRY.categorize are correct
//
// TRSRYv1.1 Configuration
// [X] addSupplyCategory
//     [X] only "bookkeeper_policy" role can call
//     [X] inputs to SPPLY.addCategory are correct
// [X] removeSupplyCategory
//     [X] only "bookkeeper_policy" role can call
//     [X] inputs to SPPLY.removeCategory are correct
// [X] categorizeSupply
//     [X] only "bookkeeper_policy" role can call
//     [X] inputs to SPPLY.categorize are correct

type Category is bytes32;
type CategoryGroup is bytes32;

contract MockStrategy is PriceSubmodule {
    constructor(Module parent_) Submodule(parent_) {}

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.MOCKSTRATEGY");
    }

    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    function getOnePrice() external view returns (uint256) {
        return 1;
    }
}

contract MockUpgradedSubmodulePrice is PriceSubmodule {
    constructor(Module parent_) Submodule(parent_) {}

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.CHAINLINK");
    }

    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 2;
        minor = 0;
    }
}

contract MockUpgradedSubmoduleSupply is SupplySubmodule {
    constructor(Module parent_) Submodule(parent_) {}

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("SPPLY.BLV");
    }

    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 2;
        minor = 0;
    }

    function getCollateralizedOhm() external view override returns (uint256) {
        return 0;
    }

    function getProtocolOwnedBorrowableOhm() external view override returns (uint256) {
        return 0;
    }

    function getProtocolOwnedLiquidityOhm() external view override returns (uint256) {
        return 0;
    }

    function getProtocolOwnedTreasuryOhm() external view override returns (uint256) {
        return 0;
    }

    function getSourceCount() external view override returns (uint256) {
        return 0;
    }

    function getProtocolOwnedLiquidityReserves()
        external
        view
        override
        returns (SPPLYv1.Reserves[] memory)
    {
        return new SPPLYv1.Reserves[](0);
    }
}

contract BookkeeperTest is Test {
    MockPriceFeed internal ohmUsdPriceFeed;
    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal reserveUsdPriceFeed;
    MockPriceFeed internal reserveEthPriceFeed;
    MockPriceFeed internal ethUsdPriceFeed;

    MockERC20 internal ohm;
    MockGohm internal gohm;
    MockERC20 internal reserve;
    MockERC20 internal weth;

    Kernel internal kernel;
    Bookkeeper internal bookkeeper;
    OlympusPricev2 internal PRICE;
    OlympusSupply internal SPPLY;
    OlympusTreasury internal TRSRY;
    RolesAdmin internal rolesAdmin;
    OlympusRoles internal ROLES;
    ChainlinkPriceFeeds internal chainlinkPrice;
    SimplePriceFeedStrategy internal strategy;

    address internal admin;
    address internal policy;

    int256 internal constant CHANGE_DECIMALS = 1e4;
    uint32 internal constant OBSERVATION_FREQUENCY = 8 hours;
    uint256 internal constant GOHM_INDEX = 300000000000;
    uint8 internal constant DECIMALS = 18;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Create accounts
        UserFactory userFactory = new UserFactory();
        address[] memory users = userFactory.create(2);
        admin = users[0];
        policy = users[1];

        // Tokens
        gohm = new MockGohm(GOHM_INDEX);
        ohm = new MockERC20("Olympus", "OHM", 9);
        reserve = new MockERC20("Reserve", "RSV", 18);
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        address[2] memory olympusTokens = [address(ohm), address(gohm)];

        // Price Feeds
        ethUsdPriceFeed = new MockPriceFeed();
        ethUsdPriceFeed.setDecimals(8);
        ethUsdPriceFeed.setLatestAnswer(int256(2000e8));
        ethUsdPriceFeed.setTimestamp(block.timestamp);
        ethUsdPriceFeed.setRoundId(1);
        ethUsdPriceFeed.setAnsweredInRound(1);

        ohmUsdPriceFeed = new MockPriceFeed();
        ohmUsdPriceFeed.setDecimals(8);
        ohmUsdPriceFeed.setLatestAnswer(int256(10e8));
        ohmUsdPriceFeed.setTimestamp(block.timestamp);
        ohmUsdPriceFeed.setRoundId(1);
        ohmUsdPriceFeed.setAnsweredInRound(1);

        ohmEthPriceFeed = new MockPriceFeed();
        ohmEthPriceFeed.setDecimals(18);
        ohmEthPriceFeed.setLatestAnswer(int256(0.005e18));
        ohmEthPriceFeed.setTimestamp(block.timestamp);
        ohmEthPriceFeed.setRoundId(1);
        ohmEthPriceFeed.setAnsweredInRound(1);

        // Deploy system contracts
        kernel = new Kernel();
        PRICE = new OlympusPricev2(kernel, DECIMALS, OBSERVATION_FREQUENCY);
        ROLES = new OlympusRoles(kernel);
        SPPLY = new OlympusSupply(kernel, olympusTokens, 0);
        TRSRY = new OlympusTreasury(kernel);
        bookkeeper = new Bookkeeper(kernel);
        rolesAdmin = new RolesAdmin(kernel);

        // Deploy submodules for PRICE
        chainlinkPrice = new ChainlinkPriceFeeds(PRICE);
        strategy = new SimplePriceFeedStrategy(PRICE);

        // Install contracts on kernel
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.InstallModule, address(PRICE));
        kernel.executeAction(Actions.InstallModule, address(SPPLY));
        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.ActivatePolicy, address(bookkeeper));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Configure permissioned roles
        rolesAdmin.grantRole("bookkeeper_admin", admin);
        rolesAdmin.grantRole("bookkeeper_policy", policy);

        // Install base submodules on PRICE
        vm.startPrank(admin);
        bookkeeper.installSubmodule(toKeycode("PRICE"), chainlinkPrice);
        bookkeeper.installSubmodule(toKeycode("PRICE"), strategy);
        vm.stopPrank();
    }

    /* ========== Helper Functions ========== */

    function _makeObservations(
        MockERC20 asset,
        PRICEv2.Component memory feed,
        uint256 numObs
    ) internal view returns (uint256[] memory) {
        // Get current price from feed
        (bool success, bytes memory data) = address(PRICE.getSubmoduleForKeycode(feed.target))
            .staticcall(
                abi.encodeWithSelector(feed.selector, address(asset), PRICE.decimals(), feed.params)
            );

        require(success, "Price feed call failed");
        int256 fetchedPrice = int256(abi.decode(data, (uint256)));

        /// Perform a random walk and create observations array
        uint256[] memory obs = new uint256[](numObs);
        int256 change; // percentage with two decimals
        for (uint256 i = numObs; i > 0; --i) {
            // Add current price to obs array
            obs[i - 1] = uint256(fetchedPrice);

            /// Calculate a random percentage change from -10% to + 10% using the nonce and observation number
            change = int256(uint256(keccak256(abi.encodePacked(i)))) % int256(1000);

            /// Calculate the new ohmEth price
            fetchedPrice = (fetchedPrice * (CHANGE_DECIMALS + change)) / CHANGE_DECIMALS;
        }

        return obs;
    }

    function _addBaseAssets() internal {
        // OHM
        PRICEv2.Component memory strat = PRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0)
        );

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](2);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ChainlinkPriceFeeds.OneFeedParams(ohmUsdPriceFeed, uint48(24 hours)))
        );
        feeds[1] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(
                ChainlinkPriceFeeds.TwoFeedParams(
                    ohmEthPriceFeed,
                    uint48(24 hours),
                    ethUsdPriceFeed,
                    uint48(24 hours)
                )
            )
        );

        uint256[] memory obs = _makeObservations(ohm, feeds[0], 15);

        vm.prank(policy);
        bookkeeper.addAssetPrice(
            address(ohm),
            true,
            true,
            uint32(5 days),
            uint48(block.timestamp),
            obs,
            strat,
            feeds
        );
    }

    /* ========== Bookkeeper Setup and Permissions ========== */
    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](4);
        expectedDeps[0] = toKeycode("ROLES");
        expectedDeps[1] = toKeycode("PRICE");
        expectedDeps[2] = toKeycode("SPPLY");
        expectedDeps[3] = toKeycode("TRSRY");

        Keycode[] memory deps = bookkeeper.configureDependencies();
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
        assertEq(fromKeycode(deps[2]), fromKeycode(expectedDeps[2]));
        assertEq(fromKeycode(deps[3]), fromKeycode(expectedDeps[3]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](18);
        Keycode PRICE_KEYCODE = toKeycode("PRICE");
        Keycode SPPLY_KEYCODE = toKeycode("SPPLY");
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");
        // PRICE Permissions
        expectedPerms[0] = Permissions(PRICE_KEYCODE, PRICE.addAsset.selector);
        expectedPerms[1] = Permissions(PRICE_KEYCODE, PRICE.removeAsset.selector);
        expectedPerms[2] = Permissions(PRICE_KEYCODE, PRICE.updateAssetPriceFeeds.selector);
        expectedPerms[3] = Permissions(PRICE_KEYCODE, PRICE.updateAssetPriceStrategy.selector);
        expectedPerms[4] = Permissions(PRICE_KEYCODE, PRICE.updateAssetMovingAverage.selector);
        expectedPerms[5] = Permissions(PRICE_KEYCODE, PRICE.installSubmodule.selector);
        expectedPerms[6] = Permissions(PRICE_KEYCODE, PRICE.upgradeSubmodule.selector);
        // SPPLY Permissions
        expectedPerms[7] = Permissions(SPPLY_KEYCODE, SPPLY.addCategory.selector);
        expectedPerms[8] = Permissions(SPPLY_KEYCODE, SPPLY.removeCategory.selector);
        expectedPerms[9] = Permissions(SPPLY_KEYCODE, SPPLY.categorize.selector);
        expectedPerms[10] = Permissions(SPPLY_KEYCODE, SPPLY.installSubmodule.selector);
        expectedPerms[11] = Permissions(SPPLY_KEYCODE, SPPLY.upgradeSubmodule.selector);
        // TRSRY Permissions
        expectedPerms[12] = Permissions(TRSRY_KEYCODE, TRSRY.addAsset.selector);
        expectedPerms[13] = Permissions(TRSRY_KEYCODE, TRSRY.addAssetLocation.selector);
        expectedPerms[14] = Permissions(TRSRY_KEYCODE, TRSRY.removeAssetLocation.selector);
        expectedPerms[15] = Permissions(TRSRY_KEYCODE, TRSRY.addCategoryGroup.selector);
        expectedPerms[16] = Permissions(TRSRY_KEYCODE, TRSRY.addCategory.selector);
        expectedPerms[17] = Permissions(TRSRY_KEYCODE, TRSRY.categorize.selector);

        Permissions[] memory perms = bookkeeper.requestPermissions();
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    /* ========== PRICEv2 Configuration ========== */
    function testRevert_addAssetPrice_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Setup data to add asset
        PRICEv2.Component memory strategyComponent = PRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0)
        );

        PRICEv2.Component[] memory feedComponents = new PRICEv2.Component[](2);
        feedComponents[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ChainlinkPriceFeeds.OneFeedParams(ohmUsdPriceFeed, uint48(24 hours)))
        );
        feedComponents[1] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(
                ChainlinkPriceFeeds.TwoFeedParams(
                    ohmEthPriceFeed,
                    uint48(24 hours),
                    ethUsdPriceFeed,
                    uint48(24 hours)
                )
            )
        );

        // Get observation data to initialize moving average with
        uint256[] memory obs = _makeObservations(ohm, feedComponents[0], 15);

        // Try to add asset to PRICEv2 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.addAssetPrice(
            address(ohm),
            true,
            true,
            uint32(5 days),
            uint48(block.timestamp),
            obs,
            strategyComponent,
            feedComponents
        );

        // Confirm asset was not added
        PRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, false);

        // Try to add asset to PRICEv2 with policy account, expect success
        vm.prank(policy);
        bookkeeper.addAssetPrice(
            address(ohm),
            true,
            true,
            uint32(5 days),
            uint48(block.timestamp),
            obs,
            strategyComponent,
            feedComponents
        );
    }

    function test_addAssetPrice_correctData() public {
        // Setup data to add asset
        PRICEv2.Component memory strategyComponent = PRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0)
        );

        PRICEv2.Component[] memory feedComponents = new PRICEv2.Component[](2);
        feedComponents[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ChainlinkPriceFeeds.OneFeedParams(ohmUsdPriceFeed, uint48(24 hours)))
        );
        feedComponents[1] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(
                ChainlinkPriceFeeds.TwoFeedParams(
                    ohmEthPriceFeed,
                    uint48(24 hours),
                    ethUsdPriceFeed,
                    uint48(24 hours)
                )
            )
        );

        // Get observation data to initialize moving average with
        uint256[] memory obs = _makeObservations(ohm, feedComponents[0], 15);

        // Confirm asset is not approved yet and data is not set
        PRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, false);
        assertEq(asset.storeMovingAverage, false);
        assertEq(asset.useMovingAverage, false);
        assertEq(asset.movingAverageDuration, uint32(0));
        assertEq(asset.nextObsIndex, uint16(0));
        assertEq(asset.numObservations, uint16(0));
        assertEq(asset.lastObservationTime, uint48(0));
        assertEq(asset.cumulativeObs, uint256(0));
        assertEq(asset.obs.length, uint256(0));
        assertEq(asset.strategy, bytes(""));
        assertEq(asset.feeds, bytes(""));

        // Add asset to PRICEv2 using policy account
        vm.prank(policy);
        bookkeeper.addAssetPrice(
            address(ohm),
            true,
            true,
            uint32(5 days),
            uint48(block.timestamp),
            obs,
            strategyComponent,
            feedComponents
        );

        // Confirm asset is approved and data is correct
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, true);
        assertEq(asset.storeMovingAverage, true);
        assertEq(asset.useMovingAverage, true);
        assertEq(asset.movingAverageDuration, uint32(5 days));
        assertEq(asset.nextObsIndex, uint16(0));
        assertEq(asset.numObservations, uint16(15));
        assertEq(asset.lastObservationTime, uint48(block.timestamp));
        uint256 cumObs;
        for (uint256 i = 0; i < obs.length; i++) {
            cumObs += obs[i];
        }
        assertEq(asset.cumulativeObs, cumObs);
        assertEq(asset.obs.length, uint256(15));
        assertEq(asset.strategy, abi.encode(strategyComponent));
        assertEq(asset.feeds, abi.encode(feedComponents));
    }

    function testRevert_removeAssetPrice_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm asset is approved
        PRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, true);

        // Try to remove asset from PRICEv2 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.removeAssetPrice(address(ohm));

        // Confirm asset was not removed
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, true);

        // Try to remove asset from PRICEv2 with policy account, expect success
        vm.prank(policy);
        bookkeeper.removeAssetPrice(address(ohm));

        // Confirm asset was removed
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, false);
    }

    function test_removeAssetPrice() public {
        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm asset is approved
        PRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, true);

        // Remove asset from PRICEv2 using policy account
        vm.prank(policy);
        bookkeeper.removeAssetPrice(address(ohm));

        // Confirm asset is not approved and all data deleted
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, false);
        assertEq(asset.storeMovingAverage, false);
        assertEq(asset.useMovingAverage, false);
        assertEq(asset.movingAverageDuration, uint32(0));
        assertEq(asset.nextObsIndex, uint16(0));
        assertEq(asset.numObservations, uint16(0));
        assertEq(asset.lastObservationTime, uint48(0));
        assertEq(asset.cumulativeObs, uint256(0));
        assertEq(asset.obs.length, uint256(0));
        assertEq(asset.strategy, bytes(""));
        assertEq(asset.feeds, bytes(""));
    }

    function testRevert_updateAssetPriceFeeds_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm current has two feeds
        PRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        PRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (PRICEv2.Component[]));
        assertEq(feeds.length, 2);

        // Setup data to update feeds
        PRICEv2.Component[] memory newFeeds = new PRICEv2.Component[](1);
        newFeeds[0] = feeds[0];

        // Try to update feeds for asset on PRICEv2 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.updateAssetPriceFeeds(address(ohm), newFeeds);

        // Confirm feeds were not updated
        asset = PRICE.getAssetData(address(ohm));
        feeds = abi.decode(asset.feeds, (PRICEv2.Component[]));
        assertEq(feeds.length, 2);

        // Try to update feeds for asset on PRICEv2 with policy account, expect success
        vm.prank(policy);
        bookkeeper.updateAssetPriceFeeds(address(ohm), newFeeds);

        // Confirm feeds were updated
        asset = PRICE.getAssetData(address(ohm));
        feeds = abi.decode(asset.feeds, (PRICEv2.Component[]));
        assertEq(feeds.length, 1);
    }

    function test_updateAssetPriceFeeds() public {
        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm current has two feeds
        PRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        PRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (PRICEv2.Component[]));
        assertEq(feeds.length, 2);

        // Setup data to update feeds
        PRICEv2.Component[] memory newFeeds = new PRICEv2.Component[](1);
        newFeeds[0] = feeds[0];

        // Update feeds
        vm.prank(policy);
        bookkeeper.updateAssetPriceFeeds(address(ohm), newFeeds);

        // Confirm feeds were updated
        asset = PRICE.getAssetData(address(ohm));
        feeds = abi.decode(asset.feeds, (PRICEv2.Component[]));
        assertEq(feeds.length, 1);
        assertEq(fromSubKeycode(feeds[0].target), fromSubKeycode(newFeeds[0].target));
        assertEq(feeds[0].selector, newFeeds[0].selector);
        assertEq(feeds[0].params, newFeeds[0].params);
    }

    function testRevert_updateAssetPriceStrategy_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm currently uses the getFirstNonZeroPrice strategy
        PRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        PRICEv2.Component memory strat = abi.decode(asset.strategy, (PRICEv2.Component));
        assertEq(fromSubKeycode(strat.target), bytes20("PRICE.SIMPLESTRATEGY"));
        assertEq(strat.selector, SimplePriceFeedStrategy.getFirstNonZeroPrice.selector);
        assertEq(strat.params, abi.encode(0));

        // Setup data to update strategy
        MockStrategy newStrategy = new MockStrategy(PRICE);
        PRICEv2.Component memory newStrat = PRICEv2.Component(
            newStrategy.SUBKEYCODE(),
            newStrategy.getOnePrice.selector,
            abi.encode(1)
        );
        vm.prank(admin);
        bookkeeper.installSubmodule(toKeycode("PRICE"), newStrategy);

        // Try to update strategy for asset on PRICEv2 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.updateAssetPriceStrategy(address(ohm), newStrat, false);

        // Confirm strategy was not updated
        asset = PRICE.getAssetData(address(ohm));
        strat = abi.decode(asset.strategy, (PRICEv2.Component));
        assertEq(fromSubKeycode(strat.target), bytes20("PRICE.SIMPLESTRATEGY"));
        assertEq(strat.selector, SimplePriceFeedStrategy.getFirstNonZeroPrice.selector);
        assertEq(strat.params, abi.encode(0));
        assertEq(asset.useMovingAverage, true);

        // Try to update strategy for asset on PRICEv2 with policy account, expect success
        vm.prank(policy);
        bookkeeper.updateAssetPriceStrategy(address(ohm), newStrat, false);

        // Confirm feeds were updated
        asset = PRICE.getAssetData(address(ohm));
        strat = abi.decode(asset.strategy, (PRICEv2.Component));
        assertEq(fromSubKeycode(strat.target), fromSubKeycode(newStrat.target));
        assertEq(strat.selector, newStrat.selector);
        assertEq(strat.params, newStrat.params);
        assertEq(asset.useMovingAverage, false);
    }

    function test_updateAssetPriceStrategy() public {
        // Add base assets to PRICEv2
        _addBaseAssets();

        // Confirm that ohm currently uses the getFirstNonZeroPrice strategy
        PRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        PRICEv2.Component memory strat = abi.decode(asset.strategy, (PRICEv2.Component));
        assertEq(fromSubKeycode(strat.target), bytes20("PRICE.SIMPLESTRATEGY"));
        assertEq(strat.selector, SimplePriceFeedStrategy.getFirstNonZeroPrice.selector);
        assertEq(strat.params, abi.encode(0));
        assertEq(asset.useMovingAverage, true);

        // Setup data to update strategy
        MockStrategy newStrategy = new MockStrategy(PRICE);
        PRICEv2.Component memory newStrat = PRICEv2.Component(
            newStrategy.SUBKEYCODE(),
            newStrategy.getOnePrice.selector,
            abi.encode(1)
        );
        vm.prank(admin);
        bookkeeper.installSubmodule(toKeycode("PRICE"), newStrategy);

        // Update strategy for asset on PRICEv2 with policy account
        vm.prank(policy);
        bookkeeper.updateAssetPriceStrategy(address(ohm), newStrat, false);

        // Confirm strategy was updated
        asset = PRICE.getAssetData(address(ohm));
        strat = abi.decode(asset.strategy, (PRICEv2.Component));
        assertEq(fromSubKeycode(strat.target), fromSubKeycode(newStrat.target));
        assertEq(strat.selector, newStrat.selector);
        assertEq(strat.params, newStrat.params);
        assertEq(asset.useMovingAverage, false);
    }

    function testRevert_updateAssetMovingAverage_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Add base assets to PRICEv2
        _addBaseAssets();

        // Update ohm strategy to not use a moving average so we can remove it later
        vm.prank(policy);
        bookkeeper.updateAssetPriceStrategy(
            address(ohm),
            PRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
                abi.encode(0)
            ),
            false
        );

        // Confirm that ohm currently stores a moving average
        PRICEv2.Asset memory asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.storeMovingAverage, true);

        // Try to update moving average for asset on PRICEv2 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.updateAssetMovingAverage(
            address(ohm),
            false,
            uint32(0),
            uint16(0),
            new uint256[](0)
        );

        // Confirm moving average was not updated
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.storeMovingAverage, true);

        // Try to update moving average for asset on PRICEv2 with policy account, expect success
        vm.prank(policy);
        bookkeeper.updateAssetMovingAverage(
            address(ohm),
            false,
            uint32(0),
            uint16(0),
            new uint256[](0)
        );

        // Confirm moving average was updated
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.storeMovingAverage, false);
    }

    function test_updateAssetMovingAverage_correctData() public {
        // Add a new asset to PRICEv2 that doesn't have a moving average
        MockERC20 fohm = new MockERC20("Fake OHM", "FOHM", 9);

        PRICEv2.Component memory strategyComponent = PRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0)
        );

        PRICEv2.Component[] memory feedComponents = new PRICEv2.Component[](1);
        feedComponents[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ChainlinkPriceFeeds.OneFeedParams(ohmUsdPriceFeed, uint48(24 hours)))
        );

        vm.prank(policy);
        bookkeeper.addAssetPrice(
            address(fohm),
            false,
            false,
            uint32(0),
            uint48(0),
            new uint256[](0),
            strategyComponent,
            feedComponents
        );

        // Confirm that fohm currently does not store a moving average and other data is zero
        PRICEv2.Asset memory asset = PRICE.getAssetData(address(fohm));
        assertEq(asset.storeMovingAverage, false);
        assertEq(asset.movingAverageDuration, uint32(0));
        assertEq(asset.nextObsIndex, uint16(0));
        assertEq(asset.numObservations, uint16(1)); // 1 because of cached value
        assertEq(asset.lastObservationTime, uint48(block.timestamp)); // current timestamp because of cached value
        assertEq(asset.cumulativeObs, uint256(0));
        assertEq(asset.obs.length, uint256(1)); // cached value

        // Update moving average with policy account
        uint256[] memory obs = _makeObservations(fohm, feedComponents[0], 15);
        vm.prank(policy);
        bookkeeper.updateAssetMovingAverage(
            address(fohm),
            true,
            uint32(5 days),
            uint48(block.timestamp - 1),
            obs
        );

        // Confirm moving average was updated and other data is correct
        asset = PRICE.getAssetData(address(fohm));
        assertEq(asset.storeMovingAverage, true);
        assertEq(asset.movingAverageDuration, uint32(5 days));
        assertEq(asset.nextObsIndex, uint16(0));
        assertEq(asset.numObservations, uint16(15));
        assertEq(asset.lastObservationTime, uint48(block.timestamp - 1));
        uint256 cumObs;
        for (uint256 i = 0; i < obs.length; i++) {
            cumObs += obs[i];
        }
        assertEq(asset.cumulativeObs, cumObs);
        assertEq(asset.obs.length, uint256(15));
    }

    /* ========== PRICEv2 Submodule Installation/Upgrade ========== */

    function testRevert_installSubmodule_onlyAdmin(address user_) public {
        vm.assume(user_ != admin);

        // Create new submodule to install
        MockStrategy newStrategy = new MockStrategy(PRICE);

        // Confirm submodule is not installed on PRICE
        address submodule = address(PRICE.getSubmoduleForKeycode(newStrategy.SUBKEYCODE()));
        assertEq(submodule, address(0));

        // Try to install submodule with non-admin account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_admin")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.installSubmodule(toKeycode("PRICE"), newStrategy);

        // Confirm submodule was not installed
        submodule = address(PRICE.getSubmoduleForKeycode(newStrategy.SUBKEYCODE()));
        assertEq(submodule, address(0));

        // Try to install submodule with admin account, expect success
        vm.prank(admin);
        bookkeeper.installSubmodule(toKeycode("PRICE"), newStrategy);

        // Confirm submodule was installed
        submodule = address(PRICE.getSubmoduleForKeycode(newStrategy.SUBKEYCODE()));
        assertEq(submodule, address(newStrategy));
    }

    function test_installSubmodule_PRICE() public {
        // Create new submodule to install
        MockStrategy newStrategy = new MockStrategy(PRICE);

        // Confirm submodule is not installed on PRICE
        address submodule = address(PRICE.getSubmoduleForKeycode(newStrategy.SUBKEYCODE()));
        assertEq(submodule, address(0));

        // Install new submodule with admin account
        vm.prank(admin);
        bookkeeper.installSubmodule(toKeycode("PRICE"), newStrategy);

        // Confirm submodule was installed
        submodule = address(PRICE.getSubmoduleForKeycode(newStrategy.SUBKEYCODE()));
        assertEq(submodule, address(newStrategy));
    }

    function test_installSubmodule_SPPLY() public {
        // Create vault managers
        MockVaultManager vaultManager1 = new MockVaultManager(1000e9);
        MockVaultManager[] memory vaultManagers = new MockVaultManager[](1);
        address[] memory vaultManagerAddresses = new address[](1);
        vaultManagers[0] = vaultManager1;
        vaultManagerAddresses[0] = address(vaultManager1);

        // Create new submodule to install
        BLVaultSupply supplyBLV = new BLVaultSupply(SPPLY, vaultManagerAddresses);

        // Confirm submodule is not installed on SPPLY
        address submodule = address(SPPLY.getSubmoduleForKeycode(supplyBLV.SUBKEYCODE()));
        assertEq(submodule, address(0));

        // Install new submodule with admin account
        vm.prank(admin);
        bookkeeper.installSubmodule(toKeycode("SPPLY"), supplyBLV);

        // Confirm submodule was installed
        submodule = address(SPPLY.getSubmoduleForKeycode(supplyBLV.SUBKEYCODE()));
        assertEq(submodule, address(supplyBLV));
    }

    function testRevert_upgradeSubmodule_onlyAdmin(address user_) public {
        vm.assume(user_ != admin);

        // Create mock upgrade for chainlink submodule
        MockUpgradedSubmodulePrice newChainlink = new MockUpgradedSubmodulePrice(PRICE);

        // Confirm chainlink submodule is installed on PRICE and the version is 1.0
        address chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(chainlinkPrice));
        (uint8 major, uint8 minor) = Submodule(chainlink).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        // Try to upgrade chainlink submodule with non-admin account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_admin")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.upgradeSubmodule(toKeycode("PRICE"), newChainlink);

        // Confirm chainlink submodule was not upgraded
        chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(chainlinkPrice));
        (major, minor) = Submodule(chainlink).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        // Try to upgrade chainlink submodule with admin account, expect success
        vm.prank(admin);
        bookkeeper.upgradeSubmodule(toKeycode("PRICE"), newChainlink);

        // Confirm chainlink submodule was upgraded
        chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(newChainlink));
        (major, minor) = Submodule(chainlink).VERSION();
        assertEq(major, 2);
        assertEq(minor, 0);
    }

    function test_upgradeSubmodule_PRICE() public {
        // Create mock upgrade for chainlink submodule
        MockUpgradedSubmodulePrice newChainlink = new MockUpgradedSubmodulePrice(PRICE);

        // Confirm chainlink submodule is installed on PRICE and the version is 1.0
        address chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(chainlinkPrice));
        (uint8 major, uint8 minor) = Submodule(chainlink).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        // Upgrade chainlink submodule with admin account, expect success
        vm.prank(admin);
        bookkeeper.upgradeSubmodule(toKeycode("PRICE"), newChainlink);

        // Confirm chainlink submodule was upgraded
        chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(newChainlink));
        (major, minor) = Submodule(chainlink).VERSION();
        assertEq(major, 2);
        assertEq(minor, 0);
    }

    function test_upgradeSubmodule_SPPLY() public {
        // Create vault managers
        MockVaultManager vaultManager1 = new MockVaultManager(1000e9);
        MockVaultManager[] memory vaultManagers = new MockVaultManager[](1);
        address[] memory vaultManagerAddresses = new address[](1);
        vaultManagers[0] = vaultManager1;
        vaultManagerAddresses[0] = address(vaultManager1);

        // Create new submodule to install
        BLVaultSupply supplyBLV = new BLVaultSupply(SPPLY, vaultManagerAddresses);

        // Install new submodule with admin account
        vm.prank(admin);
        bookkeeper.installSubmodule(toKeycode("SPPLY"), supplyBLV);

        // Confirm BLV submodule is installed on SPPLY and the version is 1.0
        address submodule = address(SPPLY.getSubmoduleForKeycode(toSubKeycode("SPPLY.BLV")));
        assertEq(submodule, address(supplyBLV));
        (uint8 major, uint8 minor) = Submodule(submodule).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        // Create mock upgrade for BLV submodule
        MockUpgradedSubmoduleSupply newBLV = new MockUpgradedSubmoduleSupply(SPPLY);

        // Upgrade BLV submodule with admin account, expect success
        vm.prank(admin);
        bookkeeper.upgradeSubmodule(toKeycode("SPPLY"), newBLV);

        // Confirm BLV submodule was upgraded
        submodule = address(SPPLY.getSubmoduleForKeycode(toSubKeycode("SPPLY.BLV")));
        assertEq(submodule, address(newBLV));
        (major, minor) = Submodule(submodule).VERSION();
        assertEq(major, 2);
        assertEq(minor, 0);
    }

    /* ========== SPPLYv1 Configuration ========== */

    function testRevert_addSupplyCategory_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Try to add category to SPPLYv1 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.addSupplyCategory(
            SupplyCategory.wrap("test_supply_category"),
            false,
            bytes4(0),
            bytes4(0)
        );
    }

    function test_addSupplyCategory() public {
        SupplyCategory[] memory initCategories = SPPLY.getCategories();

        vm.prank(policy);
        bookkeeper.addSupplyCategory(
            SupplyCategory.wrap("test_supply_category"),
            false,
            bytes4(0),
            bytes4(0)
        );

        // Check SPPLY categories
        SupplyCategory[] memory postCategories = SPPLY.getCategories();
        assertEq(initCategories.length + 1, postCategories.length);
        assertEq(
            SupplyCategory.unwrap(postCategories[postCategories.length - 1]),
            bytes32("test_supply_category")
        );
    }

    function testRevert_removeSupplyCategory_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Try to remove category from SPPLYv1 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.removeSupplyCategory(SupplyCategory.wrap("test_supply_category"));
    }

    function test_removeSupplyCategory(address user_) public {
        SupplyCategory[] memory initCategories = SPPLY.getCategories();

        vm.startPrank(policy);
        bookkeeper.addSupplyCategory(
            SupplyCategory.wrap("test_supply_category"),
            false,
            bytes4(0),
            bytes4(0)
        );
        bookkeeper.removeSupplyCategory(SupplyCategory.wrap("test_supply_category"));

        // Check SPPLY categories
        SupplyCategory[] memory postCategories = SPPLY.getCategories();
        assertEq(initCategories.length, postCategories.length);
    }

    function testRevert_categorizeSupply_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Try to remove category from SPPLYv1 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.categorizeSupply(address(0), SupplyCategory.wrap("test_supply_category"));
    }

    function test_categorizeSupply(address user_) public {
        vm.startPrank(policy);
        bookkeeper.addSupplyCategory(
            SupplyCategory.wrap("test_supply_category"),
            false,
            bytes4(0),
            bytes4(0)
        );
        bookkeeper.categorizeSupply(address(1), SupplyCategory.wrap("test_supply_category"));

        // Check SPPLY category locations
        address[] memory locations = SPPLY.getLocationsByCategory(
            SupplyCategory.wrap("test_supply_category")
        );
        assertEq(locations.length, 1);
        assertEq(locations[0], address(1));
    }

    /* ========== TRSRYv1.1 Configuration ========== */

    function testRevert_addAsset_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);
        address[] memory locations = new address[](2);
        locations[0] = address(1);
        locations[1] = address(2);

        // Try to add category to SPPLYv1 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.addAsset(address(reserve), locations);
    }

    function test_addAsset() public {
        address[] memory locations = new address[](2);
        locations[0] = address(1);
        locations[1] = address(2);

        vm.prank(policy);
        bookkeeper.addAsset(address(reserve), locations);

        // Check TRSRY assets
        address[] memory assets = TRSRY.getAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(reserve));

        // Check TRSRY asset locations
        TRSRYv1_1.Asset memory assetData = TRSRY.getAssetData(address(reserve));
        assertEq(assetData.locations.length, 2);
        assertEq(assetData.locations[0], address(1));
        assertEq(assetData.locations[1], address(2));
        assertEq(assetData.approved, true);
        assertEq(assetData.updatedAt, uint48(block.timestamp));
    }

    function testRevert_addAssetLocation_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Try to remove category from SPPLYv1 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.addAssetLocation(address(reserve), address(2));
    }

    function test_addAssetLocation() public {
        address[] memory locations = new address[](1);
        locations[0] = address(1);

        vm.prank(policy);
        bookkeeper.addAsset(address(reserve), locations);

        // Cache TRSRY asset locations
        TRSRYv1_1.Asset memory initAssetData = TRSRY.getAssetData(address(reserve));

        vm.prank(policy);
        bookkeeper.addAssetLocation(address(reserve), address(2));

        // Check TRSRY asset locations
        TRSRYv1_1.Asset memory postAssetData = TRSRY.getAssetData(address(reserve));
        assertEq(initAssetData.locations.length + 1, postAssetData.locations.length);
        assertEq(postAssetData.locations[1], address(2));
    }

    function testRevert_removeAssetLocation_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Try to remove category from SPPLYv1 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.removeAssetLocation(address(reserve), address(0));
    }

    function test_removeAssetLocation() public {
        address[] memory locations = new address[](2);
        locations[0] = address(1);
        locations[1] = address(2);

        vm.prank(policy);
        bookkeeper.addAsset(address(reserve), locations);

        // Cache TRSRY asset locations
        TRSRYv1_1.Asset memory initAssetData = TRSRY.getAssetData(address(reserve));

        vm.prank(policy);
        bookkeeper.removeAssetLocation(address(reserve), address(2));

        // Check TRSRY asset locations
        TRSRYv1_1.Asset memory postAssetData = TRSRY.getAssetData(address(reserve));
        assertEq(initAssetData.locations.length - 1, postAssetData.locations.length);
    }

    function testRevert_addAssetCategoryGroup_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Try to remove category from SPPLYv1 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.addAssetCategoryGroup(AssetCategoryGroup.wrap("test-asset-category-group"));
    }

    function test_addAssetCategoryGroup(address user_) public {
        vm.prank(policy);
        bookkeeper.addAssetCategoryGroup(AssetCategoryGroup.wrap("test-asset-category-group"));

        // Check TRSRY asset category groups
        AssetCategoryGroup group0 = TRSRY.categoryGroups(0);
        assertEq(AssetCategoryGroup.unwrap(group0), bytes32("liquidity-preference"));
        AssetCategoryGroup group1 = TRSRY.categoryGroups(1);
        assertEq(AssetCategoryGroup.unwrap(group1), bytes32("value-baskets"));
        AssetCategoryGroup group2 = TRSRY.categoryGroups(2);
        assertEq(AssetCategoryGroup.unwrap(group2), bytes32("market-sensitivity"));
        AssetCategoryGroup group3 = TRSRY.categoryGroups(3);
        assertEq(AssetCategoryGroup.unwrap(group3), bytes32("test-asset-category-group"));
    }

    function testRevert_addAssetCategory_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Try to remove category from SPPLYv1 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.addAssetCategory(
            AssetCategory.wrap("test-asset-category"),
            AssetCategoryGroup.wrap("test-asset-category-group")
        );
    }

    function test_addAssetCategory(address user_) public {
        vm.startPrank(policy);
        bookkeeper.addAssetCategoryGroup(AssetCategoryGroup.wrap("test-asset-category-group"));
        bookkeeper.addAssetCategory(
            AssetCategory.wrap("test-asset-category"),
            AssetCategoryGroup.wrap("test-asset-category-group")
        );

        // Check TRSRY asset category for a given category group
        AssetCategoryGroup group = TRSRY.categoryToGroup(AssetCategory.wrap("test-asset-category"));
        assertEq(AssetCategoryGroup.unwrap(group), bytes32("test-asset-category-group"));
    }

    function testRevert_categorizeAsset_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Try to remove category from SPPLYv1 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("bookkeeper_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        bookkeeper.categorizeAsset(address(reserve), AssetCategory.wrap("test-asset-category"));
    }

    function test_categorizeAsset() public {
        address[] memory locations = new address[](2);
        locations[0] = address(1);
        locations[1] = address(2);

        vm.startPrank(policy);
        bookkeeper.addAssetCategoryGroup(AssetCategoryGroup.wrap("test-asset-category-group"));
        bookkeeper.addAssetCategory(
            AssetCategory.wrap("test-asset-category"),
            AssetCategoryGroup.wrap("test-asset-category-group")
        );
        bookkeeper.addAsset(address(reserve), locations);
        bookkeeper.categorizeAsset(address(reserve), AssetCategory.wrap("test-asset-category"));

        // Check TRSRY asset by category
        address[] memory assets = TRSRY.getAssetsByCategory(
            AssetCategory.wrap("test-asset-category")
        );
        assertEq(assets.length, 1);
        assertEq(assets[0], address(reserve));
    }
}
