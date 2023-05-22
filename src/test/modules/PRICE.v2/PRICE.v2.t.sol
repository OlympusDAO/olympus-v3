// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FullMath} from "libraries/FullMath.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {MockVault, MockBalancerPool} from "test/mocks/BalancerMocks.sol";

import "modules/PRICE/OlympusPrice.v2.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {BalancerPoolTokenPrice, IVault, IWeightedPool} from "modules/PRICE/submodules/feeds/BalancerPoolTokenPrice.sol";

// Tests for OlympusPrice v2
// TODO
// Asset Information
// [ ] getAssets - returns all assets configured on the PRICE module
//      [ ] zero assets
//      [ ] one asset
//      [ ] many assets
// [ ] getAssetData - returns the price configuration data for a given asset
//
// Asset Prices
// [ ] getPrice(address, Variant) - returns the price of an asset in terms of the unit of account (USD)
//      [ ] current variant - dynamically calculates price from strategy and components
//           [ ] single price feed
//           [ ] multiple price feeds
//           [ ] single price feed with recursive calls
//           [ ] multiple price feeds with recursive calls
//           [ ] reverts if strategy fails
//           [ ] reverts if price is zero
//      [ ] last variant - loads price from cache
//           [ ] single observation stored
//           [ ] multiple observations stored
//           [ ] reverts if cached value is zero
//      [ ] moving average variant - returns the moving average from stored observations
//           [ ] single observation stored
//           [ ] multiple observations stored
//           [ ] reverts if moving average isn't stored
//           [ ] reverts if cached value is zero
//      [ ] reverts if invalid variant provided
//      [ ] reverts if asset not configured on PRICE module (not approved)
// [ ] getPrice(address) - convenience function for current price
//      [ ] returns cached value if updated this timestamp
//      [ ] calculates and returns current price if not updated this timestamp
// [ ] getPrice(address, uint48) - convenience function for price up to a certain age
//      [ ] returns cached value if updated within the provided age
//      [ ] calculates and returns current price if not updated within the provided age
// [ ] getPriceIn - returns the price of an asset in terms of another asset
//      [ ] current variant - dynamically calculates price from strategy and components
//      [ ] last variant - loads price from cache
//      [ ] moving average variant - returns the moving average from stored observations
//      [ ] reverts if invalid variant provided for either asset
//      [ ] reverts if either asset is not configured on PRICE module (not approved)
// [ ] getPriceIn(address) - returns cached value if updated this timestamp, otherwise calculates dynamically
//      [ ] returns cached value if both assets updated this timestamp
//      [ ] calculates and returns current price if either asset not updated this timestamp
// [ ] getPriceIn(address, uint48) - returns cached value if updated within the provided age, otherwise calculates dynamically
//      [ ] returns cached value if both assets updated within the provided age
//      [ ] calculates and returns current price if either asset not updated within the provided age
// [ ] storePrice - caches the price of an asset (stores a new observation if the asset uses a moving average)
//      [ ] reverts if asset not configured on PRICE module (not approved)
//      [ ] reverts if price is zero
//      [ ] reverts if caller is not permissioned
//      [ ] updates stored observations
//           [ ] single observation stored (no moving average)
//           [ ] multiple observations stored (moving average configured)
//      [ ] price stored event emitted
//
// Asset Management
// [ ] addAsset - add an asset to the PRICE module
//      [ ] reverts if asset already configured (approved)
//      [ ] reverts if asset address is not a contract
//      [ ] reverts if moving average is being used by strategy but not being stored on the contract
//      [ ] reverts if caller is not permissioned
//      [ ] all asset data is stored correctly
//      [ ] asset added to assets array
// [ ] removeAsset
//      [ ] reverts if asset not configured (not approved)
//      [ ] reverts if caller is not permissioned
//      [ ] all asset data is removed
//      [ ] asset removed from assets array
// [ ] updateAssetPriceFeeds
//      [ ] reverts if asset not configured (not approved)
//      [ ] reverts if caller is not permissioned
//      [ ] reverts if no feeds are provided
//      [ ] reverts if any feed is not installed as a submodule
//      [ ] stores new feeds in asset data as abi-encoded bytes of the feed address array
// [ ] updateAssetPriceStrategy
//      [ ] reverts if asset not configured (not approved)
//      [ ] reverts if caller is not permissioned
//      [ ] reverts if strategy is not installed as a submodule
//      [ ] reverts if uses moving average but moving average is not stored for asset
//      [ ] stores new strategy in asset data as abi-encoded bytes of the strategy component
// [ ] updateAssetMovingAverage
//      [ ] reverts if asset not configured (not approved)
//      [ ] reverts if caller is not permissioned
//      [ ] reverts if last observation time is in the future
//      [ ] previous configuratio and observations cleared
//      [ ] if storing moving average
//           [ ] reverts if moving average duration and observation frequency are invalid
//           [ ] reverts if implied observations does not equal the amount of observations provided
//           [ ] stores moving average data, including observations, in asset data
//      [ ] if not storing moving average
//           [ ] reverts if more than one observation is provided
//           [ ] one observation provided
//              [ ] stores observation and last observation time in asset data
//              [ ] emits price stored event
//           [ ] no observations provided
//              [ ] stores last observation time in asset data
contract PriceV2Test is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusPricev2;

    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal reserveEthPriceFeed;
    MockPriceFeed internal ethUsdPriceFeed;
    MockERC20 internal ohm;
    MockERC20 internal reserve;
    MockERC20 internal weth;
    MockBalancerPool internal bpt;
    MockVault internal balVault;

    Kernel internal kernel;
    OlympusPricev2 internal price;
    ChainlinkPriceFeeds internal chainlinkPrice;
    BalancerPoolTokenPrice internal bptPrice;

    address internal writer;

    int256 internal constant CHANGE_DECIMALS = 1e4;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        {
            /// Deploy protocol mocks external to guidance
            ohm = new MockERC20("Olympus", "OHM", 9);
            reserve = new MockERC20("Reserve", "RSV", 18);
            weth = new MockERC20("Wrapped ETH", "WETH", 18);
            bpt = new MockBalancerPool();

            balVault = new MockVault(address(bpt), address(ohm), address(reserve));

            ohmEthPriceFeed = new MockPriceFeed();
            ohmEthPriceFeed.setDecimals(18);

            reserveEthPriceFeed = new MockPriceFeed();
            reserveEthPriceFeed.setDecimals(18);
        }

        {
            /// Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            /// Deploy price module
            price = new OlympusPricev2(kernel, 18, uint32(8 hours));

            /// Deploy mock module writer
            writer = price.generateGodmodeFixture(type(OlympusPricev2).name);

            /// Deploy submodules
            chainlinkPrice = new ChainlinkPriceFeeds(price);
            bptPrice = new BalancerPoolTokenPrice(price, IVault(address(balVault)));
        }

        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(price));
            kernel.executeAction(Actions.ActivatePolicy, address(writer));

            // Install submodules on price module
            vm.startPrank(writer);
            price.installSubmodule(chainlinkPrice);
            price.installSubmodule(bptPrice);
            vm.stopPrank();
        }

        {
            /// Initialize timestamps on mock price feeds
            ohmEthPriceFeed.setTimestamp(block.timestamp);
            reserveEthPriceFeed.setTimestamp(block.timestamp);
        }
    }

    // =========  HELPER FUNCTIONS ========= //
    // function initializePrice(uint8 nonce) internal {
    //     /// Assume that the reserveEth price feed is fixed at 0.001 ETH = 1 Reserve
    //     reserveEthPriceFeed.setLatestAnswer(int256(1e15));
    //     uint256 reserveEthPrice = uint256(reserveEthPriceFeed.latestAnswer());

    //     /// Set ohmEth price to 0.01 ETH = 1 OHM initially
    //     /// This makes the price 10 reserves per OHM, which is the same as our minimum value.
    //     /// Random moves up and down will be above or below this.
    //     int256 ohmEthPrice = int256(1e16);

    //     /// Set scaling value for calculations
    //     uint256 scale = 10 **
    //         (price.priceDecimals() + reserveEthPriceFeed.decimals() - ohmEthPriceFeed.decimals());

    //     /// Calculate the number of observations and initialize the observation array
    //     uint48 observationFrequency = price.observationFrequency();
    //     uint48 movingAverageDuration = price.movingAverageDuration();
    //     uint256 numObservations = movingAverageDuration / observationFrequency;
    //     uint256[] memory observations = new uint256[](numObservations);

    //     /// Perform a random walk to initialize the observations
    //     int256 change; // percentage with two decimals
    //     for (uint256 i; i < numObservations; ++i) {
    //         /// Calculate a random percentage change from -10% to + 10% using the nonce and observation number
    //         change = int256(uint256(keccak256(abi.encodePacked(nonce, i)))) % int256(1000);

    //         /// Calculate the new ohmEth price
    //         ohmEthPrice = (ohmEthPrice * (CHANGE_DECIMALS + change)) / CHANGE_DECIMALS;

    //         /// Update price feed
    //         ohmEthPriceFeed.setLatestAnswer(ohmEthPrice);

    //         /// Get the current price from the price module and store in the observations array
    //         observations[i] = uint256(ohmEthPrice).mulDiv(scale, reserveEthPrice);
    //     }

    //     /// Initialize the price module with the observations
    //     vm.prank(writer);
    //     price.initialize(observations, uint48(block.timestamp));
    // }

    // function makeRandomObservations(
    //     uint8 nonce,
    //     uint256 observations
    // ) internal returns (uint48 timeIncrease) {
    //     /// Perform a random walk and update the moving average with the supplied number of observations
    //     int256 change; // percentage with two decimals
    //     int256 ohmEthPrice = ohmEthPriceFeed.latestAnswer();
    //     uint48 observationFrequency = price.observationFrequency();
    //     for (uint256 i; i < observations; ++i) {
    //         /// Calculate a random percentage change from -10% to + 10% using the nonce and observation number
    //         change = int256(uint256(keccak256(abi.encodePacked(nonce, i)))) % int256(1000);

    //         /// Calculate the new ohmEth price
    //         ohmEthPrice = (ohmEthPrice * (CHANGE_DECIMALS + change)) / CHANGE_DECIMALS;

    //         /// Update price feed
    //         ohmEthPriceFeed.setLatestAnswer(ohmEthPrice);
    //         ohmEthPriceFeed.setTimestamp(block.timestamp);
    //         reserveEthPriceFeed.setTimestamp(block.timestamp);

    //         /// Call update moving average on the price module
    //         vm.prank(writer);
    //         price.updateMovingAverage();

    //         /// Shift time forward by the observation frequency
    //         timeIncrease += observationFrequency;
    //         vm.warp(block.timestamp + observationFrequency);
    //     }
    // }

    function _addBaseAssets() internal {
        // Configure price feed data
        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            ethUsdPriceFeed,
            uint48(24 hours)
        );

        ChainlinkPriceFeeds.TwoFeedParams memory ohmParams = ChainlinkPriceFeeds.TwoFeedParams(
            ohmEthPriceFeed,
            uint48(24 hours),
            ethUsdPriceFeed,
            uint48(24 hours)
        );

        ChainlinkPriceFeeds.TwoFeedParams memory reserveParams = ChainlinkPriceFeeds.TwoFeedParams(
            reserveEthPriceFeed,
            uint48(24 hours),
            ethUsdPriceFeed,
            uint48(24 hours)
        );

        BalancerPoolTokenPrice.BalancerWeightedPoolParams memory bptParams = BalancerPoolTokenPrice
            .BalancerWeightedPoolParams(IWeightedPool(address(bpt)));

        // Add base assets to price module
        vm.startPrank(writer);

        // WETH
        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_
        );

        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_ // don't track WETH MA
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );

        // OHM
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector, // bytes4 functionSelector_
            abi.encode(ohmParams) // bytes memory params_
        );

        price.addAsset(
            address(ohm), // address asset_
            true, // bool storeMovingAverage_ // track OHM MA
            false, // bool useMovingAverage_
            uint32(30 days), // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            new uint256[](90), // uint256[] memory observations_ // TODO
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds // Component[] feeds_
        );

        // Reserve
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getTwoFeedPriceDiv.selector, // bytes4 functionSelector_
            abi.encode(reserveParams) // bytes memory params_
        );

        price.addAsset(
            address(reserve), // address asset_
            true, // bool storeMovingAverage_ // track reserve MA
            false, // bool useMovingAverage_
            uint32(30 days), // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            new uint256[](90), // uint256[] memory observations_ // TODO
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds // Component[] feeds_
        );

        // BPT
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.BPT"), // SubKeycode subKeycode_
            BalancerPoolTokenPrice.getWeightedPoolTokenPrice.selector, // bytes4 functionSelector_
            abi.encode(bptParams) // bytes memory params_
        );

        price.addAsset(
            address(bpt), // address asset_
            false, // bool storeMovingAverage_ // no moving average for BPT
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds // Component[] feeds_
        );

        vm.stopPrank();
    }

    // =========  TESTS ========= //

    function test_getAssets_zero() public {
        // Get assets from price module and check that they match
        address[] memory assets = price.getAssets();
        assertEq(assets.length, 0);
    }

    function test_getAssets_one() public {
        // Add one asset to the price module
        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            ethUsdPriceFeed,
            uint48(24 hours)
        );

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_
        );

        vm.prank(writer);
        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_ // don't track WETH MA
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );

        // Get assets from price module and check that they match
        address[] memory assets = price.getAssets();
        assertEq(assets[0], address(weth));
        assertEq(assets.length, 1);
    }

    function test_getAssets_many() public {
        // Add base assets to price module
        _addBaseAssets();

        // Get assets from price module and check that they match
        address[] memory assets = price.getAssets();
        assertEq(assets[0], address(weth));
        assertEq(assets[1], address(ohm));
        assertEq(assets[2], address(reserve));
        assertEq(assets[3], address(bpt));
        assertEq(assets.length, 4);
    }
}
