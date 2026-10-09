// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IPriceCacher} from "src/policies/interfaces/IPriceCacher.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {MockPriceCacherCache} from "./MockPriceCacherCache.sol";
import {PriceCacherTest} from "./PriceCacherTest.sol";

contract PriceCacherSetPriceCacheTest is PriceCacherTest {
    // when caller is not admin
    //  then the call reverts
    function test_whenCallerIsNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        cacher.setPriceCache(address(priceCache));
    }

    // given PriceCacher is enabled
    //  when admin rotates PriceCache
    //   then the cache dependency is rotated
    function test_givenEnabled_whenAdminRotatesPriceCache() public {
        MockPriceCacherCache replacement = _deployActiveCache(kernel);

        vm.expectEmit(true, false, false, true, address(cacher));
        emit IPriceCacher.PriceCacheSet(address(replacement));
        vm.prank(admin);
        cacher.setPriceCache(address(replacement));

        assertEq(cacher.priceCache(), address(replacement), "price cache");

        vm.prank(heart);
        cacher.execute();

        assertEq(replacement.callCount(), 2, "replacement cache calls");
        assertEq(priceCache.callCount(), 0, "old cache calls");
    }

    // given PriceCacher is disabled
    //  when admin rotates PriceCache
    //   then the cache dependency is rotated
    function test_givenDisabled_whenAdminRotatesPriceCache() public {
        MockPriceCacherCache replacement = _deployActiveCache(kernel);
        vm.prank(emergency);
        cacher.disable("");

        vm.prank(admin);
        cacher.setPriceCache(address(replacement));

        assertEq(cacher.priceCache(), address(replacement), "price cache");
    }

    // when candidate is zero
    //  then it reverts and preserves the cache
    function test_whenCandidateIsZero_revertsAndPreservesCache() public {
        vm.expectRevert(IPriceCacher.PriceCacher_ZeroAddress.selector);
        vm.prank(admin);
        cacher.setPriceCache(address(0));

        assertEq(cacher.priceCache(), address(priceCache), "price cache");
    }

    // when candidate version is unsupported
    //  then it reverts and preserves the cache
    function test_whenCandidateVersionIsUnsupported_revertsAndPreservesCache() public {
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
        vm.prank(admin);
        cacher.setPriceCache(address(candidate));

        assertEq(cacher.priceCache(), address(priceCache), "price cache");
    }

    // when candidate uses different kernel
    //  then it reverts and preserves the cache
    function test_whenCandidateUsesDifferentKernel_revertsAndPreservesCache() public {
        Kernel otherKernel = new Kernel();
        MockPriceCacherCache candidate = new MockPriceCacherCache(otherKernel);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacher.PriceCacher_PriceCacheKernelMismatch.selector,
                address(kernel),
                address(otherKernel)
            )
        );
        vm.prank(admin);
        cacher.setPriceCache(address(candidate));

        assertEq(cacher.priceCache(), address(priceCache), "price cache");
    }

    // when candidate does not support an existing pair
    //  then it reverts and preserves the cache
    function test_whenCandidateDoesNotSupportAnExistingPair_revertsAndPreservesCache() public {
        MockPriceCacherCache candidate = new MockPriceCacherCache(kernel);
        candidate.setUnsupportedPair(ohm, usde);

        vm.expectRevert(
            abi.encodeWithSelector(MockPriceCacherCache.PairUnsupported.selector, ohm, usde)
        );
        vm.prank(admin);
        cacher.setPriceCache(address(candidate));

        assertEq(cacher.priceCache(), address(priceCache), "price cache");
    }

    function _deployActiveCache(Kernel kernel_) internal returns (MockPriceCacherCache cache_) {
        cache_ = new MockPriceCacherCache(kernel_);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(cache_));
        cache_.enable("");
    }
}
