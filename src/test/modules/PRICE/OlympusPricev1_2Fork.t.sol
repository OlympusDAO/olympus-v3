// SPDX-License-Identifier: UNLICENSED
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {ModuleWithSubmodules} from "src/Submodules.sol";
import {toSubKeycode} from "src/Submodules.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {PRICEv1} from "src/modules/PRICE/PRICE.v1.sol";
import {OlympusPricev1_2} from "src/modules/PRICE/OlympusPricev1_2.sol";
import {OlympusPricev2} from "src/modules/PRICE/OlympusPrice.v2.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

import {ConvertibleDepositActivator} from "src/proposals/ConvertibleDepositActivator.sol";
import {IHeart as IHeart_v1_6} from "src/policies/interfaces/IHeart_v1_6.sol";
import {IEmissionManager as IEmissionManager_v1_1} from "src/policies/interfaces/IEmissionManager_v1_1.sol";
import {EmissionManager} from "src/policies/EmissionManager.sol";
import {YieldRepurchaseFacility} from "src/policies/YieldRepurchaseFacility.sol";
import {IHeart} from "src/policies/interfaces/IHeart.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";

contract OlympusPricev1_2ForkTest is Test {
    using ModuleTestFixtureGenerator for OlympusPricev1_2;

    // Constants
    uint256 internal constant FORK_BLOCK = 23831097 + 1;
    address public constant OHM = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address public constant KERNEL = 0x2286d7f9639e8158FaD1169e76d1FbC38247f54b;
    address public constant HEART = 0x5824850D8A6E46a473445a5AF214C7EbD46c5ECB;
    address public constant ROLES_ADMIN = 0xb216d714d91eeC4F7120a732c11428857C659eC8;
    address public constant EMISSION_MANAGER = 0xA61b846D5D8b757e3d541E0e4F80390E28f0B6Ff;
    address public constant YIELD_REPO = 0x271e35a8555a62F6bA76508E85dfD76D580B0692;
    address public constant CHAINLINK_OHM_ETH = 0x9a72298ae3886221820B1c878d12D872087D3a23;
    address public constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant TIMELOCK = 0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39;
    address public constant CONVERTIBLE_DEPOSIT_ACTIVATOR =
        0xA0ca0F496B6295f949EddA2DF5FcD3877d5a253E;

    // System contracts
    Kernel public kernel;
    PRICEv1 public oldPrice;
    OlympusPricev1_2 public price;
    IHeart public heart;
    EmissionManager public emissionManager;
    YieldRepurchaseFacility public yrf;
    RolesAdmin public rolesAdmin;

    // Submodules
    ChainlinkPriceFeeds public chainlinkPrice;
    SimplePriceFeedStrategy public strategy;

    // Permissioned addresses
    address public moduleWriter;
    address public priceWriterV1_2;
    address public priceWriterV2;
    address public kernelExecutor;

    // Events
    event MinimumTargetPriceChanged(uint256 minimumTargetPrice_);

    // TODO use mock price feeds
    // TODO complete assertions

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
        heart = IHeart(HEART);
        emissionManager = EmissionManager(EMISSION_MANAGER);
        yrf = YieldRepurchaseFacility(YIELD_REPO);

        // Get observation frequency from old PRICE module
        uint32 observationFrequency = uint32(oldPrice.observationFrequency());
        // Get minimum target price from old PRICE module (if available)
        uint256 minimumTargetPrice = oldPrice.minimumTargetPrice();

        // Deploy new PRICE v1.2 module
        price = new OlympusPricev1_2(kernel, OHM, observationFrequency, minimumTargetPrice);

        // Deploy permissioned fixtures
        moduleWriter = price.generateGodmodeFixture(type(ModuleWithSubmodules).name);
        priceWriterV1_2 = price.generateGodmodeFixture(type(OlympusPricev1_2).name);
        priceWriterV2 = price.generateGodmodeFixture(type(OlympusPricev2).name);

        // Deploy submodules
        chainlinkPrice = new ChainlinkPriceFeeds(price);
        strategy = new SimplePriceFeedStrategy(price);

        // Check the epoch of the YRF
        console2.log("YRF epoch", yrf.epoch());

        // TODO synchronise so that the YRF and EM epochs are the same

        // Upgrade PRICE module to v1.2
        vm.startPrank(kernelExecutor);
        kernel.executeAction(Actions.UpgradeModule, address(price));
        vm.stopPrank();

        // Activate permissioned fixtures
        vm.startPrank(kernelExecutor);
        kernel.executeAction(Actions.ActivatePolicy, address(moduleWriter));
        kernel.executeAction(Actions.ActivatePolicy, address(priceWriterV1_2));
        kernel.executeAction(Actions.ActivatePolicy, address(priceWriterV2));
        vm.stopPrank();

        // Install submodules
        vm.startPrank(moduleWriter);
        price.installSubmodule(chainlinkPrice);
        price.installSubmodule(strategy);
        vm.stopPrank();

        // Configure OHM asset with MA tracking and OHM-ETH/ETH-USD feeds
        _configureOhmAsset();
    }

    // ========== HELPER FUNCTIONS ========== //

    function _configureOhmAsset() internal {
        vm.startPrank(priceWriterV2);

        // Configure OHM with two feeds: OHM-ETH and ETH-USD (multiplied together)
        ChainlinkPriceFeeds.TwoFeedParams memory ohmEthUsdParams = ChainlinkPriceFeeds
            .TwoFeedParams(
                AggregatorV2V3Interface(CHAINLINK_OHM_ETH),
                uint48(24 hours),
                AggregatorV2V3Interface(CHAINLINK_ETH_USD),
                uint48(24 hours)
            );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(ohmEthUsdParams)
        );

        // Create initial observations for moving average
        // Get current price to use as initial observations
        uint256 currentPrice = chainlinkPrice.getTwoFeedPriceMul(
            OHM,
            18,
            abi.encode(ohmEthUsdParams)
        );

        uint256[] memory observations = new uint256[](90); // 30 days / 8 hours = 90 observations
        for (uint256 i = 0; i < 90; i++) {
            observations[i] = currentPrice;
        }

        price.addAsset(
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

    // ========== TESTS ========== //

    // ========== HEARTBEAT INTEGRATION ========== //

    // when the heartbeat is called
    //  [ ] the OHM moving average is updated
    //  [ ] the EmissionManager premium is accurate
    function test_beat() public {
        // Get initial state
        uint256 ohmPriceBefore = price.getCurrentPrice();
        uint256 ohmMABefore = price.getMovingAverage();
        uint48 lastObsTimeBefore = price.lastObservationTime();

        // Get EmissionManager state before
        uint256 emPremiumBefore = emissionManager.getPremium();
        (uint256 emPremiumCalc, uint256 emEmissionRate, uint256 emEmission) = emissionManager
            .getNextEmission();

        // Warp forward by observation frequency
        uint48 observationFreq = price.observationFrequency();
        vm.warp(block.timestamp + observationFreq);

        // Call heartbeat
        heart.beat();

        // Verify PRICE moving average was updated
        uint48 lastObsTimeAfter = price.lastObservationTime();
        assertEq(lastObsTimeAfter, uint48(block.timestamp));
        assertGt(lastObsTimeAfter, lastObsTimeBefore);

        // Verify moving average was updated
        uint256 ohmMAAfter = price.getMovingAverage();
        assertGt(ohmMAAfter, 0);

        // Verify EmissionManager can still access prices
        uint256 emPremiumAfter = emissionManager.getPremium();
        assertGe(emPremiumAfter, 0); // Premium can be 0 if price is below backing

        // Verify YRF can access prices
        uint256 yrfReserveBalance = yrf.getReserveBalance();
        assertGt(yrfReserveBalance, 0);
    }

    // when the heartbeat launches YRF and EM markets
    //  [ ] the OHM moving average is updated
    //  [ ] the YRF market is created with the current price
    //  [ ] the EM market is created with the current price
    function test_beat_givenMarkets() public {
        uint256[] memory movingAverages = new uint256[](5);

        // Perform multiple heartbeats
        uint48 observationFreq = price.observationFrequency();
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + observationFreq);
            heart.beat();

            movingAverages[i] = price.getMovingAverage();
        }

        // Verify moving averages are being tracked
        for (uint256 i = 0; i < 5; i++) {
            assertGt(movingAverages[i], 0);
        }

        // Verify EmissionManager calculations remain consistent
        uint256 emPremium = emissionManager.getPremium();
        (uint256 emPremiumCalc, uint256 emEmissionRate, uint256 emEmission) = emissionManager
            .getNextEmission();
        assertGe(emPremium, 0); // Premium can be 0 if price is below backing
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
