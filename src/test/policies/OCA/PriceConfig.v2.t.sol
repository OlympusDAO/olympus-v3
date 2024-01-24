// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {MockVaultManager} from "test/mocks/MockBLVaultManager.sol";
import {MockBalancerVault} from "test/mocks/MockBalancerVault.sol";

import "src/Submodules.sol";
import {PriceConfigV2} from "policies/OCA/PriceConfig.v2.sol";
import {OlympusPricev2, PRICEv2, PriceSubmodule} from "modules/PRICE/OlympusPrice.v2.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

// Tests for PriceConfig v1.0.0
//
// PriceConfig Setup and Permissions
// [X] configureDependencies
// [X] requestPermissions
//
// PRICEv2 Configuration
// [X] addAssetPrice
//     [X] only "priceconfig_policy" role can call
//     [X] inputs to PRICEv2.addAsset are correct
// [X] removeAssetPrice
//     [X] only "priceconfig_policy" role can call
//     [X] inputs to PRICEv2.removeAsset are correct
// [X] updateAssetPriceFeeds
//     [X] only "priceconfig_policy" role can call
//     [X] inputs to PRICEv2.updateAssetPriceFeeds are correct
// [X] updateAssetPriceStrategy
//     [X] only "priceconfig_policy" role can call
//     [X] inputs to PRICEv2.updateAssetPriceStrategy are correct
// [X] updateAssetMovingAverage
//     [X] only "priceconfig_policy" role can call
//     [X] inputs to PRICEv2.updateAssetMovingAverage are correct
//
// PRICEv2 Submodule Installation/Upgrade
// [X] installSubmodule
//     [X] only "priceconfig_admin" role can call
//     [X] inputs to PRICEv2.installSubmodule are correct
// [X] upgradeSubmodule
//     [X] only "priceconfig_admin" role can call
//     [X] inputs to PRICEv2.upgradeSubmodule are correct

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

contract PriceConfigTest is Test {
    MockPriceFeed internal ohmUsdPriceFeed;
    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal reserveUsdPriceFeed;
    MockPriceFeed internal reserveEthPriceFeed;
    MockPriceFeed internal ethUsdPriceFeed;

    MockERC20 internal ohm;

    Kernel internal kernel;
    PriceConfigV2 internal priceConfig;
    OlympusPricev2 internal PRICE;
    RolesAdmin internal rolesAdmin;
    OlympusRoles internal ROLES;
    ChainlinkPriceFeeds internal chainlinkPrice;
    SimplePriceFeedStrategy internal strategy;

    MockBalancerVault internal balancerVault;

    address internal admin;
    address internal policy;

    int256 internal constant CHANGE_DECIMALS = 1e4;
    uint32 internal constant OBSERVATION_FREQUENCY = 8 hours;
    uint8 internal constant DECIMALS = 18;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Create accounts
        UserFactory userFactory = new UserFactory();
        address[] memory users = userFactory.create(2);
        admin = users[0];
        policy = users[1];

        // Tokens
        ohm = new MockERC20("Olympus", "OHM", 9);

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
        priceConfig = new PriceConfigV2(kernel);
        rolesAdmin = new RolesAdmin(kernel);

        balancerVault = new MockBalancerVault();

        // Deploy submodules for PRICE
        chainlinkPrice = new ChainlinkPriceFeeds(PRICE);
        strategy = new SimplePriceFeedStrategy(PRICE);

        // Install contracts on kernel
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.InstallModule, address(PRICE));
        kernel.executeAction(Actions.ActivatePolicy, address(priceConfig));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Configure permissioned roles
        rolesAdmin.grantRole("priceconfig_admin", admin);
        rolesAdmin.grantRole("priceconfig_policy", policy);

        // Install base submodules on PRICE
        vm.startPrank(admin);
        priceConfig.installSubmodule(chainlinkPrice);
        priceConfig.installSubmodule(strategy);
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
        priceConfig.addAssetPrice(
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

    /* ========== PriceConfig Setup and Permissions ========== */

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](2);
        expectedDeps[0] = toKeycode("ROLES");
        expectedDeps[1] = toKeycode("PRICE");

        Keycode[] memory deps = priceConfig.configureDependencies();
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](8);
        Keycode PRICE_KEYCODE = toKeycode("PRICE");

        // PRICE Permissions
        expectedPerms[0] = Permissions(PRICE_KEYCODE, PRICE.addAsset.selector);
        expectedPerms[1] = Permissions(PRICE_KEYCODE, PRICE.removeAsset.selector);
        expectedPerms[2] = Permissions(PRICE_KEYCODE, PRICE.updateAssetPriceFeeds.selector);
        expectedPerms[3] = Permissions(PRICE_KEYCODE, PRICE.updateAssetPriceStrategy.selector);
        expectedPerms[4] = Permissions(PRICE_KEYCODE, PRICE.updateAssetMovingAverage.selector);
        expectedPerms[5] = Permissions(PRICE_KEYCODE, PRICE.installSubmodule.selector);
        expectedPerms[6] = Permissions(PRICE_KEYCODE, PRICE.upgradeSubmodule.selector);
        expectedPerms[7] = Permissions(PRICE_KEYCODE, PRICE.execOnSubmodule.selector);

        Permissions[] memory perms = priceConfig.requestPermissions();
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
            bytes32("priceconfig_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        priceConfig.addAssetPrice(
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
        priceConfig.addAssetPrice(
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
        priceConfig.addAssetPrice(
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
            bytes32("priceconfig_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        priceConfig.removeAssetPrice(address(ohm));

        // Confirm asset was not removed
        asset = PRICE.getAssetData(address(ohm));
        assertEq(asset.approved, true);

        // Try to remove asset from PRICEv2 with policy account, expect success
        vm.prank(policy);
        priceConfig.removeAssetPrice(address(ohm));

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
        priceConfig.removeAssetPrice(address(ohm));

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
            bytes32("priceconfig_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        priceConfig.updateAssetPriceFeeds(address(ohm), newFeeds);

        // Confirm feeds were not updated
        asset = PRICE.getAssetData(address(ohm));
        feeds = abi.decode(asset.feeds, (PRICEv2.Component[]));
        assertEq(feeds.length, 2);

        // Try to update feeds for asset on PRICEv2 with policy account, expect success
        vm.prank(policy);
        priceConfig.updateAssetPriceFeeds(address(ohm), newFeeds);

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
        priceConfig.updateAssetPriceFeeds(address(ohm), newFeeds);

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
        priceConfig.installSubmodule(newStrategy);

        // Try to update strategy for asset on PRICEv2 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("priceconfig_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        priceConfig.updateAssetPriceStrategy(address(ohm), newStrat, false);

        // Confirm strategy was not updated
        asset = PRICE.getAssetData(address(ohm));
        strat = abi.decode(asset.strategy, (PRICEv2.Component));
        assertEq(fromSubKeycode(strat.target), bytes20("PRICE.SIMPLESTRATEGY"));
        assertEq(strat.selector, SimplePriceFeedStrategy.getFirstNonZeroPrice.selector);
        assertEq(strat.params, abi.encode(0));
        assertEq(asset.useMovingAverage, true);

        // Try to update strategy for asset on PRICEv2 with policy account, expect success
        vm.prank(policy);
        priceConfig.updateAssetPriceStrategy(address(ohm), newStrat, false);

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
        priceConfig.installSubmodule(newStrategy);

        // Update strategy for asset on PRICEv2 with policy account
        vm.prank(policy);
        priceConfig.updateAssetPriceStrategy(address(ohm), newStrat, false);

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
        priceConfig.updateAssetPriceStrategy(
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
            bytes32("priceconfig_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        priceConfig.updateAssetMovingAverage(
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
        priceConfig.updateAssetMovingAverage(
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
        priceConfig.addAssetPrice(
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
        priceConfig.updateAssetMovingAverage(
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
            bytes32("priceconfig_admin")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        priceConfig.installSubmodule(newStrategy);

        // Confirm submodule was not installed
        submodule = address(PRICE.getSubmoduleForKeycode(newStrategy.SUBKEYCODE()));
        assertEq(submodule, address(0));

        // Try to install submodule with admin account, expect success
        vm.prank(admin);
        priceConfig.installSubmodule(newStrategy);

        // Confirm submodule was installed
        submodule = address(PRICE.getSubmoduleForKeycode(newStrategy.SUBKEYCODE()));
        assertEq(submodule, address(newStrategy));
    }

    function test_installSubmodule() public {
        // Create new submodule to install
        MockStrategy newStrategy = new MockStrategy(PRICE);

        // Confirm submodule is not installed on PRICE
        address submodule = address(PRICE.getSubmoduleForKeycode(newStrategy.SUBKEYCODE()));
        assertEq(submodule, address(0));

        // Install new submodule with admin account
        vm.prank(admin);
        priceConfig.installSubmodule(newStrategy);

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
        BLVaultSupply supplyBLV = new BLVaultSupply(
            SPPLY,
            address(balancerVault),
            vaultManagerAddresses
        );

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
            bytes32("priceconfig_admin")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        priceConfig.upgradeSubmodule(newChainlink);

        // Confirm chainlink submodule was not upgraded
        chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(chainlinkPrice));
        (major, minor) = Submodule(chainlink).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        // Try to upgrade chainlink submodule with admin account, expect success
        vm.prank(admin);
        priceConfig.upgradeSubmodule(newChainlink);

        // Confirm chainlink submodule was upgraded
        chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(newChainlink));
        (major, minor) = Submodule(chainlink).VERSION();
        assertEq(major, 2);
        assertEq(minor, 0);
    }

    function test_upgradeSubmodule() public {
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
        priceConfig.upgradeSubmodule(newChainlink);

        // Confirm chainlink submodule was upgraded
        chainlink = address(PRICE.getSubmoduleForKeycode(toSubKeycode("PRICE.CHAINLINK")));
        assertEq(chainlink, address(newChainlink));
        (major, minor) = Submodule(chainlink).VERSION();
        assertEq(major, 2);
        assertEq(minor, 0);
    }

    function test_execOnSubmodule() public {
        // Perform an action on the submodule
        uint256[] memory samplePrices = new uint256[](1);
        samplePrices[0] = 11e18;

        vm.prank(policy);
        priceConfig.execOnSubmodule(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            abi.encodeWithSelector(
                SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
                samplePrices,
                bytes("")
            )
        );

        // No error
    }

    function test_execOnSubmodule_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Perform an action on the submodule
        uint256[] memory samplePrices = new uint256[](1);
        samplePrices[0] = 11e18;

        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("priceconfig_policy")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        priceConfig.execOnSubmodule(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            abi.encodeWithSelector(
                SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
                samplePrices,
                bytes("")
            )
        );
    }
}
