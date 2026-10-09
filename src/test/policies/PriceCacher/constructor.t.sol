// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Kernel} from "src/Kernel.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {PriceCacher} from "src/policies/PriceCacher.sol";
import {IPriceCacher} from "src/policies/interfaces/IPriceCacher.sol";

import {MockPriceCacherCache} from "./MockPriceCacherCache.sol";
import {PriceCacherTest} from "./PriceCacherTest.sol";

contract PriceCacherConstructorTest is PriceCacherTest {
    // when PriceCache is zero
    //  then the call reverts
    function test_whenPriceCacheIsZero_reverts() public {
        vm.expectRevert(IPriceCacher.PriceCacher_ZeroAddress.selector);
        new PriceCacher(kernel, IPriceCache(address(0)));
    }

    // when PriceCache is not a contract
    //  then the call reverts
    function test_whenPriceCacheIsNotContract_reverts() public {
        address candidate = makeAddr("candidate");
        vm.expectRevert(
            abi.encodeWithSelector(IPriceCacher.PriceCacher_InvalidPriceCache.selector, candidate)
        );
        new PriceCacher(kernel, IPriceCache(candidate));
    }

    // when PriceCache does not support required interface
    //  then the call reverts
    function test_whenPriceCacheDoesNotSupportRequiredInterface_reverts() public {
        MockPriceCacherCache candidate = new MockPriceCacherCache(kernel);
        candidate.setInterfaceSupport(true, false, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacher.PriceCacher_InvalidPriceCache.selector,
                address(candidate)
            )
        );
        new PriceCacher(kernel, candidate);
    }

    // when PriceCache version is 1.0
    //  then it accepts the configuration
    function test_whenPriceCacheVersionIsOneZero_accepts() public {
        MockPriceCacherCache candidate = new MockPriceCacherCache(kernel);
        candidate.setVersion(1, 0);

        PriceCacher deployed = new PriceCacher(kernel, candidate);

        assertEq(deployed.priceCache(), address(candidate), "price cache");
    }

    // when the PriceCache version is 1.x maximum minor
    //  then it accepts the configuration
    function test_whenPriceCacheVersionIsOneMax_accepts() public {
        MockPriceCacherCache candidate = new MockPriceCacherCache(kernel);
        candidate.setVersion(1, type(uint8).max);

        PriceCacher deployed = new PriceCacher(kernel, candidate);

        assertEq(deployed.priceCache(), address(candidate), "price cache");
    }

    // when PriceCache major version is zero
    //  then the call reverts
    function test_whenPriceCacheMajorVersionIsZero_reverts() public {
        MockPriceCacherCache candidate = new MockPriceCacherCache(kernel);
        candidate.setVersion(0, type(uint8).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacher.PriceCacher_UnsupportedPriceCacheVersion.selector,
                address(candidate),
                0,
                type(uint8).max
            )
        );
        new PriceCacher(kernel, candidate);
    }

    // when PriceCache major version is unsupported
    //  then the call reverts
    function test_whenPriceCacheMajorVersionIsUnsupported_reverts() public {
        MockPriceCacherCache candidate = new MockPriceCacherCache(kernel);
        candidate.setVersion(2, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacher.PriceCacher_UnsupportedPriceCacheVersion.selector,
                address(candidate),
                2,
                0
            )
        );
        new PriceCacher(kernel, candidate);
    }

    // when PriceCache belongs to a different Kernel
    //  then the call reverts
    function test_whenPriceCacheUsesDifferentKernel_reverts() public {
        Kernel otherKernel = new Kernel();
        MockPriceCacherCache candidate = new MockPriceCacherCache(otherKernel);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacher.PriceCacher_PriceCacheKernelMismatch.selector,
                address(kernel),
                address(otherKernel)
            )
        );
        new PriceCacher(kernel, candidate);
    }

    // when the configuration is valid
    //  then it starts with no asset pairs
    function test_whenConfigurationIsValid_startsWithNoAssetPairs() public {
        PriceCacher candidate = new PriceCacher(kernel, priceCache);

        assertEq(candidate.priceCache(), address(priceCache), "price cache");
        assertEq(candidate.getAssetPairs().length, 0, "pair count");
    }
}
