// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
pragma solidity ^0.8.15;

import {Test} from "@forge-std-1.16.2/Test.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockPriceFeed} from "src/test/mocks/MockPriceFeed.sol";

import {Actions, Kernel} from "src/Kernel.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {toSubKeycode} from "src/Submodules.sol";
import {OlympusPricev2} from "src/modules/PRICE/OlympusPrice.v2.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {IERC7726Oracle} from "src/policies/interfaces/price/IERC7726Oracle.sol";
import {ERC7726OracleFactory} from "src/policies/price/ERC7726OracleFactory.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {PriceConfigv2} from "src/policies/price/PriceConfig.v2.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract ERC7726OracleIntegrationTest is Test {
    uint8 internal constant PRICE_DECIMALS = 18;
    uint32 internal constant OBSERVATION_FREQUENCY = 8 hours;
    uint48 internal constant DEFAULT_MAX_AGE = 1 hours;
    uint16 internal constant PRICE_EXPECTATION_TOLERANCE_BPS = 1;
    address internal constant ETH_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    Kernel internal kernel;
    OlympusPricev2 internal price;
    OlympusRoles internal roles;
    RolesAdmin internal rolesAdmin;
    PriceConfigv2 internal priceConfig;
    PriceCache internal priceCache;
    ERC7726OracleFactory internal factory;
    ChainlinkPriceFeeds internal chainlinkPriceFeeds;
    IERC7726Oracle internal oracle;

    MockERC20 internal quoteToken;
    MockPriceFeed internal quoteTokenUsdPriceFeed;
    MockPriceFeed internal ethSentinelUsdPriceFeed;
    MockPriceFeed internal nonContractAssetUsdPriceFeed;

    address internal admin;
    address internal nonContractAsset;

    function setUp() public {
        admin = makeAddr("ADMIN");
        nonContractAsset = makeAddr("NON_CONTRACT_ASSET");

        vm.warp(51 * 365 days);

        kernel = new Kernel();
        price = new OlympusPricev2(kernel, PRICE_DECIMALS, OBSERVATION_FREQUENCY);
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        priceConfig = new PriceConfigv2(kernel);
        priceCache = new PriceCache(kernel, 18, "USD");
        factory = new ERC7726OracleFactory(kernel, address(priceCache));
        chainlinkPriceFeeds = new ChainlinkPriceFeeds(price);

        kernel.executeAction(Actions.InstallModule, address(price));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(priceConfig));
        kernel.executeAction(Actions.ActivatePolicy, address(priceCache));
        kernel.executeAction(Actions.ActivatePolicy, address(factory));

        rolesAdmin.grantRole(ADMIN_ROLE, admin);

        vm.startPrank(admin);
        priceCache.enable("");
        factory.enable("");
        priceConfig.installSubmodule(address(chainlinkPriceFeeds));
        vm.stopPrank();

        quoteToken = new MockERC20("Quote Token", "QTE", 18);

        quoteTokenUsdPriceFeed = _makePriceFeed(1e8);
        ethSentinelUsdPriceFeed = _makePriceFeed(2000e8);
        nonContractAssetUsdPriceFeed = _makePriceFeed(50e8);

        _addAssetWithOneFeed(address(quoteToken), quoteTokenUsdPriceFeed);

        vm.startPrank(admin);
        priceConfig.registerNonContractAsset(ETH_SENTINEL);
        priceConfig.registerNonContractAsset(nonContractAsset);
        priceCache.setNonContractAssetMetadata(ETH_SENTINEL, 18, "ETH");
        priceCache.setNonContractAssetMetadata(nonContractAsset, 8, "NCA");
        vm.stopPrank();

        _addAssetWithOneFeed(ETH_SENTINEL, ethSentinelUsdPriceFeed);
        _addAssetWithOneFeed(nonContractAsset, nonContractAssetUsdPriceFeed);

        vm.prank(admin);
        oracle = IERC7726Oracle(factory.createOracle(DEFAULT_MAX_AGE, bytes("")));
    }

    function test_givenBaseAssetIsEthSentinel_createsOracleCachesPriceAndReturnsQuote() public {
        priceCache.cachePrice(ETH_SENTINEL, address(quoteToken));

        uint48 cachedTimestamp = priceCache
            .getCachedPrice(ETH_SENTINEL, address(quoteToken))
            .updatedAt;
        assertNotEq(cachedTimestamp, 0, "ETH sentinel pair should be cached");
        assertEq(
            oracle.isStale(ETH_SENTINEL, address(quoteToken)),
            false,
            "ETH sentinel pair should be fresh"
        );

        // baseAmount = 1e18 (1 ETH, 18 decimals)
        // basePrice = 2000e18 (USD, 18 decimals)
        // quotePrice = 1e18 (USD, 18 decimals)
        // quoteScale = 1e18, baseScale = 1e18
        // quoteAmount = ((1e18 * 2000e18) / 1e18) * 1e18 / 1e18 = 2000e18
        uint256 quoteAmount = oracle.getQuote(1e18, ETH_SENTINEL, address(quoteToken));
        assertEq(quoteAmount, 2000e18, "ETH sentinel quote should resolve through real PRICE");
    }

    function test_givenBaseAssetIsRegisteredNonContractAsset_createsOracleCachesPriceAndReturnsQuote()
        public
    {
        priceCache.cachePrice(nonContractAsset, address(quoteToken));

        uint48 cachedTimestamp = priceCache
            .getCachedPrice(nonContractAsset, address(quoteToken))
            .updatedAt;
        assertNotEq(cachedTimestamp, 0, "Non-contract asset pair should be cached");
        assertEq(
            oracle.isStale(nonContractAsset, address(quoteToken)),
            false,
            "Non-contract asset pair should be fresh"
        );

        // baseAmount = 1e8 (1 NCA, 8 decimals)
        // basePrice = 50e18 (USD, 18 decimals)
        // quotePrice = 1e18 (USD, 18 decimals)
        // quoteScale = 1e18, baseScale = 1e8
        // quoteAmount = ((1e8 * 50e18) / 1e8) * 1e18 / 1e18 = 50e18
        uint256 quoteAmount = oracle.getQuote(1e8, nonContractAsset, address(quoteToken));
        assertEq(
            quoteAmount,
            50e18,
            "Registered non-contract asset quote should resolve through real PRICE"
        );
    }

    function _makePriceFeed(int256 answer_) internal returns (MockPriceFeed feed_) {
        feed_ = new MockPriceFeed();
        feed_.setDecimals(8);
        feed_.setLatestAnswer(answer_);
        feed_.setTimestamp(block.timestamp);
        feed_.setRoundId(1);
        feed_.setAnsweredInRound(1);
    }

    function _makeFeedExpectations(
        address asset_,
        IPRICEv2.Component[] memory feeds_,
        uint16 toleranceBps_
    ) internal view returns (IPriceConfigv2.PriceFeedExpectation[] memory expectations_) {
        expectations_ = new IPriceConfigv2.PriceFeedExpectation[](feeds_.length);

        uint8 priceDecimals = price.decimals();
        for (uint256 i; i < feeds_.length; i++) {
            (bool success, bytes memory data) = address(
                price.getSubmoduleForKeycode(feeds_[i].target)
            ).staticcall(
                    abi.encodeWithSelector(
                        feeds_[i].selector,
                        asset_,
                        priceDecimals,
                        feeds_[i].params
                    )
                );
            assertTrue(success, "Price feed expectation call should succeed");
            assertEq(data.length, 32, "Price feed expectation call should return one word");

            expectations_[i] = IPriceConfigv2.PriceFeedExpectation({
                expectedPrice: abi.decode(data, (uint256)),
                toleranceBps: toleranceBps_
            });
        }
    }

    function _addAssetWithOneFeed(address asset_, MockPriceFeed feed_) internal {
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ChainlinkPriceFeeds.OneFeedParams(feed_, uint48(24 hours)))
        );

        IPriceConfigv2.PriceFeedExpectation[] memory expectations = _makeFeedExpectations(
            asset_,
            feeds,
            PRICE_EXPECTATION_TOLERANCE_BPS
        );

        vm.prank(admin);
        priceConfig.addAsset(
            asset_,
            false,
            false,
            0,
            0,
            new uint256[](0),
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), bytes("")),
            feeds,
            expectations
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable, unwrapped-modifier-logic)
