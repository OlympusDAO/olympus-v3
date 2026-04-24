// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-variable,mixed-case-function)
pragma solidity >=0.8.0;

import {PriceV2BaseTest} from "./PriceV2BaseTest.sol";

import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

contract PriceV2RegisterNonContractAssetTest is PriceV2BaseTest {
    function testRevert_registerNonContractAsset_notPermissioned() public {
        address nonContract = makeAddr("NON_CONTRACT");

        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        price.registerNonContractAsset(nonContract);
    }

    function test_registerNonContractAsset() public {
        address nonContract = makeAddr("NON_CONTRACT");

        vm.prank(priceWriter);
        price.registerNonContractAsset(nonContract);

        assertEq(
            price.isNonContractAsset(nonContract),
            true,
            "Non-contract asset should be registered"
        );
    }

    function testRevert_registerNonContractAsset_zeroAddress() public {
        vm.prank(priceWriter);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_InvalidAsset.selector, address(0)));
        price.registerNonContractAsset(address(0));
    }

    function testRevert_registerNonContractAsset_unitOfAccount() public {
        vm.prank(priceWriter);
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_InvalidAsset.selector, _UNIT_OF_ACCOUNT)
        );
        price.registerNonContractAsset(_UNIT_OF_ACCOUNT);
    }

    function testRevert_registerNonContractAsset_contractAddress() public {
        vm.prank(priceWriter);
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_InvalidAsset.selector, address(weth))
        );
        price.registerNonContractAsset(address(weth));
    }

    function testRevert_registerNonContractAsset_alreadyRegistered() public {
        address nonContract = makeAddr("NON_CONTRACT");

        vm.startPrank(priceWriter);
        price.registerNonContractAsset(nonContract);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_InvalidAsset.selector, nonContract));
        price.registerNonContractAsset(nonContract);
        vm.stopPrank();
    }
}
/// forge-lint: disable-end(mixed-case-variable,mixed-case-function)
