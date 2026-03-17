// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {PriceV2BaseTest} from "src/test/modules/PRICE.v2/PriceV2BaseTest.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

contract PriceV2GasTest is PriceV2BaseTest {
    function setUp() public override {
        super.setUp();
        _addBaseAssets(0);
    }

    function test_gasSnapshot_getPrice_cached() public {
        vm.startSnapshotGas("OlympusPricev2.getPrice.cached");
        uint256 price_ = price.getPrice(address(weth));
        uint256 gasUsed = vm.stopSnapshotGas();
        assertEq(price_, 2000e18, "weth cached price mismatch");
        assertGt(gasUsed, 0, "gas snapshot should record gas");
    }

    function test_gasSnapshot_getPrice_current() public {
        vm.warp(block.timestamp + 1);

        vm.startSnapshotGas("OlympusPricev2.getPrice.current");
        uint256 price_ = price.getPrice(address(weth));
        uint256 gasUsed = vm.stopSnapshotGas();
        assertEq(price_, 2000e18, "weth current price mismatch");
        assertGt(gasUsed, 0, "gas snapshot should record gas");
    }

    function test_gasSnapshot_getPriceIn_cached() public {
        vm.startSnapshotGas("OlympusPricev2.getPriceIn.cached");
        uint256 price_ = price.getPriceIn(address(weth), address(alpha));
        uint256 gasUsed = vm.stopSnapshotGas();
        assertEq(price_, 40e18, "weth/alpha cached price mismatch");
        assertGt(gasUsed, 0, "gas snapshot should record gas");
    }

    function test_gasSnapshot_getPriceIn_maxAgeCached() public {
        vm.startSnapshotGas("OlympusPricev2.getPriceIn.maxAgeCached");
        uint256 price_ = price.getPriceIn(address(weth), address(alpha), uint48(60));
        uint256 gasUsed = vm.stopSnapshotGas();
        assertEq(price_, 40e18, "weth/alpha maxAge cached price mismatch");
        assertGt(gasUsed, 0, "gas snapshot should record gas");
    }

    function test_gasSnapshot_cachePrice() public {
        vm.startPrank(priceWriter);
        vm.startSnapshotGas("OlympusPricev2.cachePrice");
        price.cachePrice(address(onema));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        (uint256 cachedPrice, uint48 cachedAt) = price.getPrice(
            address(onema),
            IPRICEv2.Variant.LAST
        );
        assertEq(cachedPrice, 5e18, "onema cached price mismatch");
        assertEq(cachedAt, uint48(block.timestamp), "onema cached timestamp mismatch");
        assertGt(gasUsed, 0, "gas snapshot should record gas");
    }

    function test_gasSnapshot_storeObservation() public {
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY);

        vm.startPrank(priceWriter);
        vm.startSnapshotGas("OlympusPricev2.storeObservation");
        price.storeObservation(address(onema));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        (uint256 cachedPrice, uint48 cachedAt) = price.getPrice(
            address(onema),
            IPRICEv2.Variant.LAST
        );
        assertEq(cachedPrice, 5e18, "onema observation cached price mismatch");
        assertEq(cachedAt, uint48(block.timestamp), "onema observation cached timestamp mismatch");
        assertGt(gasUsed, 0, "gas snapshot should record gas");
    }
}
