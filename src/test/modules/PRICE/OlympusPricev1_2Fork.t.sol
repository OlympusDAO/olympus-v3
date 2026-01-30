// SPDX-License-Identifier: UNLICENSED
// solhint-disable contract-name-camelcase
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
pragma solidity ^0.8.20;

// Test
import {Test} from "@forge-std-1.9.6/Test.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

// Mocks
import {MockPriceFeed} from "src/test/mocks/MockPriceFeed.sol";

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IHeart as IHeart_v1_6} from "src/policies/interfaces/IHeart_v1_6.sol";
import {IEmissionManager as IEmissionManager_v1_1} from "src/policies/interfaces/IEmissionManager_v1_1.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {toSubKeycode} from "src/Submodules.sol";
import {PRICEv1} from "src/modules/PRICE/PRICE.v1.sol";
import {OlympusPricev1_2} from "src/modules/PRICE/OlympusPrice.v1_2.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {PythPriceFeeds} from "modules/PRICE/submodules/feeds/PythPriceFeeds.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {PriceConfigv2} from "src/policies/price/PriceConfig.v2.sol";

import {ConvertibleDepositActivator} from "src/proposals/ConvertibleDepositActivator.sol";
import {EmissionManager} from "src/policies/EmissionManager.sol";
import {YieldRepurchaseFacility} from "src/policies/YieldRepurchaseFacility.sol";
import {OlympusHeart} from "src/policies/Heart.sol";
import {ConvertibleDepositAuctioneer} from "src/policies/deposits/ConvertibleDepositAuctioneer.sol";

contract OlympusPricev1_2ForkTest is Test {
    using FullMath for uint256;

    // Constants
    uint256 internal constant FORK_BLOCK = 23831097 + 1;
    address public constant OHM = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address public constant KERNEL = 0x2286d7f9639e8158FaD1169e76d1FbC38247f54b;
    address public constant HEART = 0x5824850D8A6E46a473445a5AF214C7EbD46c5ECB;
    address public constant ROLES_ADMIN = 0xb216d714d91eeC4F7120a732c11428857C659eC8;
    address public constant EMISSION_MANAGER = 0xA61b846D5D8b757e3d541E0e4F80390E28f0B6Ff;
    address public constant YIELD_REPO = 0x271e35a8555a62F6bA76508E85dfD76D580B0692;
    address public constant CONVERTIBLE_DEPOSIT_AUCTIONEER =
        0xF35193DA8C10e44aF10853Ba5a3a1a6F7529E39a;
    address public constant TIMELOCK = 0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39;
    address public constant CONVERTIBLE_DEPOSIT_ACTIVATOR =
        0xA0ca0F496B6295f949EddA2DF5FcD3877d5a253E;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant PYTH = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    address public constant DAO_MS = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;

    uint256 internal constant OHM_USD_PRICE = 20e18;
    bytes32 internal constant ETH_USD_FEED_ID =
        0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;

    // System contracts
    Kernel public kernel;
    PRICEv1 public oldPrice;
    OlympusPricev1_2 public price;
    OlympusHeart public heart;
    EmissionManager public emissionManager;
    YieldRepurchaseFacility public yrf;
    ConvertibleDepositAuctioneer public cdAuctioneer;
    RolesAdmin public rolesAdmin;
    PriceConfigv2 public priceConfig;
    MockPriceFeed public ohmUsdPriceFeed;

    // Submodules
    ChainlinkPriceFeeds public chainlinkPrice;
    PythPriceFeeds public pythPrice;
    SimplePriceFeedStrategy public strategy;

    // Permissioned addresses
    address public kernelExecutor;

    event MarketCreated(
        uint256 indexed id,
        address indexed payoutToken,
        address indexed quoteToken,
        uint48 vesting,
        uint256 initialPrice
    );

    function setUp() public {
        // Fork mainnet at block 23831097
        vm.createSelectFork("mainnet", FORK_BLOCK);

        // Get system contracts
        kernel = Kernel(KERNEL);
        kernelExecutor = kernel.executor();
        oldPrice = PRICEv1(address(kernel.getModuleForKeycode(toKeycode("PRICE"))));
        rolesAdmin = RolesAdmin(ROLES_ADMIN);

        // Enable the Heart, EmissionManager and YRF
        // This would be done by the ConvertibleDepositProposal
        vm.startPrank(TIMELOCK);
        {
            // Revoke heart from old Heart policy (v1.6)
            address OLD_HEART = 0xf7602C0421c283A2fc113172EBDf64C30F21654D;
            /// forge-lint: disable-next-line(unsafe-typecast)
            rolesAdmin.revokeRole(bytes32("heart"), OLD_HEART);

            // Disable the old Heart policy
            IHeart_v1_6(OLD_HEART).deactivate();

            // Disable the old EmissionManager policy
            address OLD_EMISSION_MANAGER = 0x50f441a3387625bDA8B8081cE3fd6C04CC48C0A2;
            IEmissionManager_v1_1(OLD_EMISSION_MANAGER).shutdown();
        }

        // Grant cd_emissionmanager role to EmissionManager
        /// forge-lint: disable-next-line(unsafe-typecast)
        rolesAdmin.grantRole(bytes32("cd_emissionmanager"), EMISSION_MANAGER);

        // Grant heart role to Heart contract
        /// forge-lint: disable-next-line(unsafe-typecast)
        rolesAdmin.grantRole(bytes32("heart"), HEART);

        // Grant admin role to ConvertibleDepositActivator contract
        /// forge-lint: disable-next-line(unsafe-typecast)
        rolesAdmin.grantRole(bytes32("admin"), CONVERTIBLE_DEPOSIT_ACTIVATOR);

        // Run the activator contract
        ConvertibleDepositActivator(CONVERTIBLE_DEPOSIT_ACTIVATOR).activate();

        // Revoke admin role from ConvertibleDepositActivator contract
        /// forge-lint: disable-next-line(unsafe-typecast)
        rolesAdmin.revokeRole(bytes32("admin"), CONVERTIBLE_DEPOSIT_ACTIVATOR);
        vm.stopPrank();

        // Get Heart, EmissionManager, YRF
        heart = OlympusHeart(HEART);
        emissionManager = EmissionManager(EMISSION_MANAGER);
        cdAuctioneer = ConvertibleDepositAuctioneer(CONVERTIBLE_DEPOSIT_AUCTIONEER);
        yrf = YieldRepurchaseFacility(YIELD_REPO);

        // Approve the EmissionManager as callback on BondFixedTermAuctioneer
        vm.startPrank(0x007BD11FCa0dAaeaDD455b51826F9a015f2f0969);
        emissionManager.bondAuctioneer().setCallbackAuthStatus(EMISSION_MANAGER, true);
        vm.stopPrank();

        // Get observation frequency from old PRICE module
        uint32 observationFrequency = uint32(oldPrice.observationFrequency());
        // Get minimum target price from old PRICE module (if available)
        uint256 minimumTargetPrice = oldPrice.minimumTargetPrice();

        // Deploy new PRICE v1.2 module
        price = new OlympusPricev1_2(kernel, OHM, observationFrequency, minimumTargetPrice);

        // Deploy PriceConfigv2 policy
        priceConfig = new PriceConfigv2(kernel);

        // Deploy submodules
        chainlinkPrice = new ChainlinkPriceFeeds(price);
        pythPrice = new PythPriceFeeds(price);
        strategy = new SimplePriceFeedStrategy(price);

        // Deploy mock price feed
        ohmUsdPriceFeed = new MockPriceFeed();
        ohmUsdPriceFeed.setDecimals(8);

        // ========== SAME-BATCH PRICE v1.2 UPGRADE ==========
        // All operations happen in the same transaction (via kernelExecutor),
        // ensuring no Heart heartbeat occurs between upgrade and configuration.
        // This is the production pattern for zero-downtime upgrades.
        vm.startPrank(kernelExecutor);
        {
            // Step 1: Upgrade PRICE module to v1.2
            kernel.executeAction(Actions.UpgradeModule, address(price));

            // Step 2: Activate PriceConfigv2 policy
            kernel.executeAction(Actions.ActivatePolicy, address(priceConfig));
        }
        vm.stopPrank();

        // Install submodules (requires price_admin role)
        vm.startPrank(DAO_MS);
        priceConfig.installSubmodule(address(chainlinkPrice));
        priceConfig.installSubmodule(address(pythPrice));
        priceConfig.installSubmodule(address(strategy));
        vm.stopPrank();

        // ========== CONFIGURE ASSETS (Same Batch Pattern) ==========
        // In production, this would be done by DAO MS in the same batch.
        _configureOhmAsset();

        _configureWethAsset();
    }

    // ========== HELPER FUNCTIONS ========== //

    function _configureOhmAsset() internal {
        // Configure the OHM price feed
        ohmUsdPriceFeed.setLatestAnswer(int256(OHM_USD_PRICE.mulDiv(1e8, 1e18))); // Convert to 8 decimals
        ohmUsdPriceFeed.setTimestamp(block.timestamp);
        ohmUsdPriceFeed.setRoundId(1);
        ohmUsdPriceFeed.setAnsweredInRound(1);

        vm.startPrank(DAO_MS); // DAO_MS has price_admin permissions

        // Configure OHM with one feed
        ChainlinkPriceFeeds.OneFeedParams memory ohmUsdParams = ChainlinkPriceFeeds.OneFeedParams(
            ohmUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ohmUsdParams)
        );

        uint256[] memory observations = new uint256[](90); // 30 days / 8 hours = 90 observations
        for (uint256 i = 0; i < 90; i++) {
            observations[i] = OHM_USD_PRICE;
        }

        priceConfig.addAssetPrice(
            address(OHM),
            true, // storeMovingAverage
            false, // useMovingAverage
            uint32(30 days), // movingAverageDuration
            uint48(block.timestamp), // lastObservationTime
            observations,
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // strategy
            feeds
        );

        vm.stopPrank();
    }

    function _configureWethAsset() internal {
        // Configure WETH with real Pyth price feed for ETH/USD
        uint48 updateThreshold = 24 hours;
        // Max confidence in absolute price terms (output decimals, 18)
        // This value allows for $10 difference
        uint256 maxConfidence = 10e18;

        vm.startPrank(DAO_MS); // DAO_MS has price_admin permissions

        // Configure WETH with Pyth feed
        PythPriceFeeds.OneFeedParams memory ethUsdParams = PythPriceFeeds.OneFeedParams(
            PYTH,
            ETH_USD_FEED_ID,
            updateThreshold,
            maxConfidence
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.PYTH"),
            PythPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ethUsdParams)
        );

        // This will revert if calling the Pyth feed fails
        priceConfig.addAssetPrice(
            address(WETH),
            false, // storeMovingAverage
            false, // useMovingAverage
            uint32(0), // movingAverageDuration
            uint48(0), // lastObservationTime
            new uint256[](0), // observations
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // strategy
            feeds
        );

        vm.stopPrank();
    }

    function _warpToNextHeartbeat() internal {
        // Warp to the next heartbeat timestamp
        vm.warp(heart.lastBeat() + heart.frequency());
    }

    modifier warpToNextHeartbeat() {
        _warpToNextHeartbeat();
        _;
    }

    modifier beat() {
        heart.beat();

        console2.log("EM epoch", emissionManager.beatCounter());
        console2.log("YRF epoch", yrf.epoch());
        console2.log("CDA auctionResultsNextIndex", cdAuctioneer.getAuctionResultsNextIndex());
        _;
    }

    modifier givenOhmPrice(uint256 price_) {
        /// forge-lint: disable-next-line(unsafe-typecast)
        ohmUsdPriceFeed.setLatestAnswer(int256(price_));
        ohmUsdPriceFeed.setTimestamp(block.timestamp);
        _;
    }

    modifier givenAuctionTrackingPeriod(uint8 period_) {
        vm.prank(TIMELOCK);
        cdAuctioneer.setAuctionTrackingPeriod(period_);
        _;
    }

    modifier givenBondMarketCapacityScalar(uint256 scalar_) {
        vm.prank(TIMELOCK);
        emissionManager.setBondMarketCapacityScalar(scalar_);
        _;
    }

    // ========== TESTS ========== //

    // ========== HEARTBEAT INTEGRATION ========== //

    // when the heartbeat is called
    //  [X] the OHM moving average is updated
    //  [X] the EmissionManager premium is uses the price feed
    function test_beat() public givenOhmPrice(24e8) {
        // Get initial state
        uint48 lastObsTimeBefore = price.lastObservationTime();
        uint256 ohmMABefore = price.getMovingAverage();

        // Warp forward by observation frequency
        _warpToNextHeartbeat();

        // Call heartbeat
        // YRF epoch: 5
        // EM epoch: 1
        heart.beat();

        // Verify PRICE moving average was updated
        uint48 lastObsTimeAfter = price.lastObservationTime();
        assertEq(
            lastObsTimeAfter,
            uint48(block.timestamp),
            "Last observation time should be updated"
        );
        assertGt(lastObsTimeAfter, lastObsTimeBefore, "Last observation time should be updated");

        // Verify moving average was updated
        // Higher as the OHM price is higher
        uint256 ohmMAAfter = price.getMovingAverage();
        assertGt(ohmMAAfter, ohmMABefore, "Moving average should be updated");

        // Verify that the EmissionManager premium is accurate
        // Price is set to 24e18 (PRICE returns 18 decimals)
        // Backing is set to 11690000000000000000 by the ConvertibleDepositActivator
        //
        // Premium = price * 10^18 / backing (rounded down) - 1e18
        //         = 24e18 * 10^18 / 11690000000000000000 - 1e18
        //         = 2053036783575705731 - 1e18
        //         = 1053036783575705731
        uint256 emPremium = emissionManager.getPremium();

        assertEq(emPremium, 1053036783575705731, "Premium incorrect");
    }

    // when the EM reaches the 0 epoch
    //  when the price in the current block is below 50% premium
    //   [X] the CD auction is disabled

    function test_emissionManager_givenEpochZero_belowPremium()
        public
        givenOhmPrice(24e8) // Above 50% premium
        warpToNextHeartbeat
        beat // Epoch 1
        warpToNextHeartbeat
        beat // Epoch 2
        givenOhmPrice(17e8) // Below 50% premium
        warpToNextHeartbeat
        beat // Epoch 0
    {
        // Verify that the CD auction target is 0 (disabled)
        assertEq(cdAuctioneer.getAuctionParameters().target, 0, "CD auction target should be 0");
    }

    //  when the price in the current block is above 50% premium
    //   [X] the CD auction min price uses the current price

    function test_emissionManager_givenEpochZero_abovePremium()
        public
        givenOhmPrice(24e8) // Above 50% premium
        warpToNextHeartbeat
        beat // Epoch 1
        warpToNextHeartbeat
        beat // Epoch 2
        givenOhmPrice(24e8) // Above 50% premium
        warpToNextHeartbeat
        beat // Epoch 0
    {
        // Calculate the expected min price
        uint256 expectedMinPrice = emissionManager.getMinPriceFor(24e18);

        assertEq(
            cdAuctioneer.getAuctionParameters().minPrice,
            expectedMinPrice,
            "CD auction min price should be the expected min price"
        );
        // No need to test the target, as the premium has already been tested
    }

    //  when the end of the auction tracking period is reached
    //   [X] the EM market is created with the current price

    function test_emissionManager_endOfAuctionTrackingPeriod()
        public
        givenAuctionTrackingPeriod(2)
        givenBondMarketCapacityScalar(1e18)
        givenOhmPrice(24e8)
        warpToNextHeartbeat
        beat // Epoch 1
        warpToNextHeartbeat
        beat // Epoch 2
        givenOhmPrice(24e8)
        warpToNextHeartbeat
        beat // Epoch 0, auction results next index is 1
        warpToNextHeartbeat
        beat // Epoch 1
        warpToNextHeartbeat
        beat // Epoch 2
        givenOhmPrice(24e8)
        warpToNextHeartbeat
    {
        uint256 expectedInitialPrice = 24e36; // Bond market scaling
        uint256 expectedMarketId = 625 + 1;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit MarketCreated(
            expectedMarketId,
            address(OHM),
            address(emissionManager.reserve()),
            uint48(0),
            expectedInitialPrice
        );

        // Beat
        // Epoch 0, auction results next index is 0
        heart.beat();

        // Verify
        assertEq(
            emissionManager.activeMarketId(),
            expectedMarketId,
            "Active market ID should be the expected market ID"
        );
    }

    // when the heartbeat launches a YRF market
    //  [X] the YRF market is created with the price from the price feed

    function test_yieldRepurchaseFacility()
        public
        givenOhmPrice(24e8) // Above 50% premium
        warpToNextHeartbeat
        beat // YRF epoch 5
        warpToNextHeartbeat
    {
        // Calculate the expected initial price
        // From YRF._createMarket()
        // 10 ** (18 * 2) / ((24e18 * 97) / 100)
        // = 42955326460481099
        // Adjusted by 1e17 for bond market scaling
        uint256 expectedInitialPrice = 42955326460481099 * 1e17;
        uint256 expectedMarketId = 623 + 1;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit MarketCreated(
            expectedMarketId,
            address(emissionManager.reserve()),
            address(OHM),
            uint48(0),
            expectedInitialPrice
        );

        // Beat
        // Epoch 6
        heart.beat();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
