// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-variable,mixed-case-function)
pragma solidity ^0.8.15;

import {PriceV2BaseTest} from "./PriceV2BaseTest.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {Module} from "src/Kernel.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

import {toSubKeycode} from "src/Submodules.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";

contract PriceV2UnregisterNonContractAssetTest is PriceV2BaseTest {
    function testRevert_unregisterNonContractAsset_notPermissioned() public {
        address nonContract = makeAddr("NON_CONTRACT");

        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        price.unregisterNonContractAsset(nonContract);
    }

    function test_unregisterNonContractAsset() public {
        address nonContract = makeAddr("NON_CONTRACT");

        vm.startPrank(priceWriter);
        price.registerNonContractAsset(nonContract);
        price.unregisterNonContractAsset(nonContract);
        vm.stopPrank();

        assertEq(
            price.isNonContractAsset(nonContract),
            false,
            "Non-contract asset should be unregistered"
        );
    }

    function test_unregisterNonContractAsset_afterContractDeploymentAndAssetRemoval() public {
        address nonContract = makeAddr("NON_CONTRACT");

        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            ethUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ethParams)
        );

        vm.startPrank(priceWriter);
        price.registerNonContractAsset(nonContract);
        price.addAsset(
            nonContract,
            false,
            false,
            uint32(0),
            uint48(0),
            new uint256[](0),
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)),
            feeds
        );
        vm.stopPrank();

        MockERC20 replacement = new MockERC20("Replacement", "RPL", 6);
        vm.etch(nonContract, address(replacement).code);

        vm.startPrank(priceWriter);
        price.removeAsset(nonContract);
        price.unregisterNonContractAsset(nonContract);
        vm.stopPrank();

        assertEq(
            price.isNonContractAsset(nonContract),
            false,
            "Non-contract asset should be unregistered after removal"
        );
    }

    function testRevert_unregisterNonContractAsset_unitOfAccount() public {
        vm.prank(priceWriter);
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetReserved.selector, _UNIT_OF_ACCOUNT)
        );
        price.unregisterNonContractAsset(_UNIT_OF_ACCOUNT);
    }

    function testRevert_unregisterNonContractAsset_zeroAddress() public {
        vm.prank(priceWriter);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_InvalidAsset.selector, address(0)));
        price.unregisterNonContractAsset(address(0));
    }

    function testRevert_unregisterNonContractAsset_notRegistered() public {
        address nonContract = makeAddr("NON_CONTRACT");

        vm.prank(priceWriter);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_InvalidAsset.selector, nonContract));
        price.unregisterNonContractAsset(nonContract);
    }

    function testRevert_unregisterNonContractAsset_approved() public {
        address nonContract = makeAddr("NON_CONTRACT");

        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            ethUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ethParams)
        );

        vm.startPrank(priceWriter);
        price.registerNonContractAsset(nonContract);
        price.addAsset(
            nonContract,
            false,
            false,
            uint32(0),
            uint48(0),
            new uint256[](0),
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)),
            feeds
        );
        vm.stopPrank();
        vm.prank(priceWriter);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_InvalidAsset.selector, nonContract));
        price.unregisterNonContractAsset(nonContract);
    }
}
/// forge-lint: disable-end(mixed-case-variable,mixed-case-function)
