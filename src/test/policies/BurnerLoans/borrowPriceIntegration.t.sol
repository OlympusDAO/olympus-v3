// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";

import {Actions} from "src/Kernel.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {OlympusPricev2} from "src/modules/PRICE/OlympusPrice.v2.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ModuleWithSubmodules, toSubKeycode} from "src/Submodules.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";

contract BurnerLoansBorrowPriceIntegrationTest is BurnerLoansBorrowTestBase {
    using ModuleTestFixtureGenerator for OlympusPricev2;

    OlympusPricev2 internal _productionPrice;
    MockPriceFeed internal _ohmUsdFeed;
    MockPriceFeed internal _usdsUsdFeed;

    address internal _moduleWriter;
    address internal _priceWriter;

    uint128 internal constant _BORROW_AMOUNT = 100e9;
    uint128 internal constant _EXACT_BOUNDARY_COLLATERAL = 1_150e6;
    uint48 internal constant _FEED_UPDATE_THRESHOLD = 24 hours;

    function setUp() public override {
        super.setUp();
        vm.warp(30 days);

        _productionPrice = new OlympusPricev2(kernel, PRICE_DECIMALS, uint32(8 hours));
        _moduleWriter = _productionPrice.generateGodmodeFixture(type(ModuleWithSubmodules).name);
        _priceWriter = _productionPrice.generateGodmodeFixture(type(OlympusPricev2).name);

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

    // Condition tree:
    // - PRICE dependency: production OlympusPricev2 with ChainlinkPriceFeeds
    // - Prices: OHM = $10 and USDS = $1 from current 8-decimal feeds
    // - Collateral: exactly the 115% minimum collateral boundary
    // - Expected branch: preview and write agree and borrowing succeeds at exactly 1e18 health
    function test_givenProductionPriceAtExactHealthBoundary_borrowMatchesPreview() public {
        _depositExactBoundaryCollateral();

        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            _BORROW_AMOUNT,
            alice
        );
        uint256 treasuryBalanceBefore = usds.balanceOf(address(trsry));

        vm.prank(alice);
        (
            uint256 borrowedOhm,
            uint256 fee,
            uint256 totalDebtOhm,
            uint48 maturity,
            uint256 healthFactor
        ) = burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, preview.fee);

        assertTrue(preview.executable, "production PRICE preview executable");
        assertEq(preview.resultingHealthFactor, 1e18, "production PRICE preview boundary health");
        assertEq(borrowedOhm, _BORROW_AMOUNT, "production PRICE borrowed OHM");
        assertEq(fee, preview.fee, "production PRICE preview fee");
        assertEq(totalDebtOhm, preview.resultingDebtOhm, "production PRICE preview debt");
        assertEq(maturity, preview.maturity, "production PRICE preview maturity");
        assertEq(healthFactor, preview.resultingHealthFactor, "production PRICE preview health");
        assertEq(ohm.balanceOf(alice), _BORROW_AMOUNT, "production PRICE minted OHM");
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBalanceBefore + preview.fee,
            "production PRICE treasury fee"
        );
    }

    // Condition tree:
    // - PRICE dependency: production OlympusPricev2 with ChainlinkPriceFeeds
    // - OHM feed: older than its configured update threshold
    // - Expected branch: PRICE cannot resolve a nonzero current value and both quote and write revert
    function test_givenProductionPriceFeedIsStale_borrowReverts() public {
        _depositExactBoundaryCollateral();
        _ohmUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);

        bytes memory error = abi.encodeWithSelector(
            IPRICEv2.PRICE_PriceZero.selector,
            address(ohm)
        );
        vm.expectRevert(error);
        burnerLoans.previewBorrow(address(usds), _BORROW_AMOUNT, alice);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, type(uint256).max);
    }

    // Condition tree:
    // - PRICE dependency: production OlympusPricev2 with ChainlinkPriceFeeds
    // - OHM feed: zero answer
    // - Expected branch: PRICE cannot resolve a nonzero current value and both quote and write revert
    function test_givenProductionPriceFeedIsZero_borrowReverts() public {
        _depositExactBoundaryCollateral();
        _ohmUsdFeed.setLatestAnswer(0);

        bytes memory error = abi.encodeWithSelector(
            IPRICEv2.PRICE_PriceZero.selector,
            address(ohm)
        );
        vm.expectRevert(error);
        burnerLoans.previewBorrow(address(usds), _BORROW_AMOUNT, alice);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, type(uint256).max);
    }

    // Condition tree:
    // - PRICE dependency: production OlympusPricev2
    // - Collateral asset: removed from PRICE after Burner Loans configuration
    // - Expected branch: both quote and write propagate the unsupported-asset error
    function test_givenProductionPriceDoesNotSupportCollateral_borrowReverts() public {
        _depositExactBoundaryCollateral();
        vm.prank(_priceWriter);
        _productionPrice.removeAsset(address(usds));

        bytes memory error = abi.encodeWithSelector(
            IPRICEv2.PRICE_AssetNotApproved.selector,
            address(usds)
        );
        vm.expectRevert(error);
        burnerLoans.previewBorrow(address(usds), _BORROW_AMOUNT, alice);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, type(uint256).max);
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

    function _depositExactBoundaryCollateral() internal {
        usds.mint(alice, _EXACT_BOUNDARY_COLLATERAL + 10e6);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), _EXACT_BOUNDARY_COLLATERAL, alice);
        vm.stopPrank();
    }
}
