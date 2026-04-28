// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {PriceV2BaseTest} from "src/test/modules/PRICE.v2/PriceV2BaseTest.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

contract PriceV2GasTest is PriceV2BaseTest {
    function setUp() public override {
        super.setUp();
        _addBaseAssets(0);
    }

    function test_gasSnapshot_getPrice_last() public {
        vm.warp(block.timestamp + 1);
        vm.prank(priceWriter);
        price.storeObservation(address(onema));

        vm.startSnapshotGas("OlympusPricev2.getPrice.last");
        (uint256 price_, uint48 timestamp_) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        uint256 gasUsed = vm.stopSnapshotGas();
        assertEq(price_, 5e18, "onema LAST price mismatch");
        assertEq(timestamp_, uint48(block.timestamp), "onema LAST timestamp mismatch");
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

    function test_gasSnapshot_getPriceIn_last() public {
        vm.warp(block.timestamp + 1);
        vm.startPrank(priceWriter);
        price.storeObservation(address(onema));
        price.storeObservation(address(twoma));
        vm.stopPrank();

        vm.startSnapshotGas("OlympusPricev2.getPriceIn.last");
        (uint256 price_, uint48 timestamp_) = price.getPriceIn(
            address(onema),
            address(twoma),
            IPRICEv2.Variant.LAST
        );
        uint256 gasUsed = vm.stopSnapshotGas();
        (uint256 onemaLast, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        (uint256 twomaLast, ) = price.getPrice(address(twoma), IPRICEv2.Variant.LAST);
        assertEq(
            price_,
            (onemaLast * (10 ** price.decimals())) / twomaLast,
            "onema/twoma LAST price mismatch"
        );
        assertEq(timestamp_, uint48(block.timestamp), "onema/twoma LAST timestamp mismatch");
        assertGt(gasUsed, 0, "gas snapshot should record gas");
    }

    function test_gasSnapshot_storeObservation() public {
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY);

        vm.startPrank(priceWriter);
        vm.startSnapshotGas("OlympusPricev2.storeObservation");
        price.storeObservation(address(onema));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        (uint256 lastPrice, uint48 lastAt) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        assertEq(lastPrice, 5e18, "onema observation LAST price mismatch");
        assertEq(lastAt, uint48(block.timestamp), "onema observation LAST timestamp mismatch");
        assertGt(gasUsed, 0, "gas snapshot should record gas");
    }
}
