// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";
import {ModulePermissions} from "test/lib/generated/ModulePermissions.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";

import {Actions} from "src/Kernel.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {OlympusPricev2} from "src/modules/PRICE/OlympusPrice.v2.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ModuleWithSubmodules, toSubKeycode} from "src/Submodules.sol";

import {BurnerLoansBorrowTestBase} from "./BurnerLoansBorrowTestBase.sol";

abstract contract BurnerLoansPriceIntegrationTestBase is BurnerLoansBorrowTestBase {
    using ModuleTestFixtureGenerator for OlympusPricev2;

    OlympusPricev2 internal _productionPrice;
    MockPriceFeed internal _ohmUsdFeed;
    MockPriceFeed internal _usdsUsdFeed;

    address internal _moduleWriter;
    address internal _priceWriter;

    uint128 internal constant _BORROW_AMOUNT = 100e9;
    uint48 internal constant _FEED_UPDATE_THRESHOLD = 24 hours;

    function _feeReserve() internal pure virtual returns (uint256) {
        return 100e6;
    }

    function setUp() public virtual override {
        super.setUp();
        vm.warp(30 days);

        _productionPrice = new OlympusPricev2(kernel, PRICE_DECIMALS, uint32(8 hours));
        _moduleWriter = _productionPrice.generateMultiFunctionFixture(
            ModulePermissions.moduleWithSubmodules()
        );
        _priceWriter = _productionPrice.generateMultiFunctionFixture(
            ModulePermissions.olympusPricev2()
        );

        ChainlinkPriceFeeds chainlinkPrice = new ChainlinkPriceFeeds(_productionPrice);
        _ohmUsdFeed = _newPriceFeed(10e8);
        _usdsUsdFeed = _newPriceFeed(1e8);

        vm.startPrank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(_productionPrice));
        kernel.executeAction(Actions.ActivatePolicy, _moduleWriter);
        kernel.executeAction(Actions.ActivatePolicy, _priceWriter);
        vm.stopPrank();

        vm.prank(_moduleWriter);
        _productionPrice.installSubmodule(chainlinkPrice);

        _addPriceAsset(address(ohm), _ohmUsdFeed);
        _addPriceAsset(address(usds), _usdsUsdFeed);
    }

    function _newPriceFeed(int256 price_) internal returns (MockPriceFeed feed) {
        feed = new MockPriceFeed();
        feed.setDecimals(8);
        feed.setLatestAnswer(price_);
        feed.setTimestamp(block.timestamp);
        feed.setRoundId(1);
        feed.setAnsweredInRound(1);
    }

    function _addPriceAsset(address asset_, MockPriceFeed feed_) internal {
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component({
            target: toSubKeycode("PRICE.CHAINLINK"),
            selector: ChainlinkPriceFeeds.getOneFeedPrice.selector,
            params: abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: feed_,
                    updateThreshold: _FEED_UPDATE_THRESHOLD
                })
            )
        });

        vm.prank(_priceWriter);
        _productionPrice.addAsset(
            asset_,
            false,
            false,
            0,
            0,
            new uint256[](0),
            IPRICEv2.Component({target: toSubKeycode(bytes20(0)), selector: bytes4(0), params: ""}),
            feeds
        );
    }

    function _depositCollateral(uint128 amount_) internal {
        usds.mint(alice, uint256(amount_) + _feeReserve());
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), amount_, alice);
        vm.stopPrank();
    }
}
