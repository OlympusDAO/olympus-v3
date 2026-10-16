// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IPriceCacher} from "src/policies/interfaces/IPriceCacher.sol";

import {PriceCacherTest} from "./PriceCacherTest.sol";

contract PriceCacherLifecycleTest is PriceCacherTest {
    // given PriceCacher is disabled
    //  when admin enables
    //   then the policy becomes enabled
    function test_givenDisabled_whenAdminEnables() public {
        vm.prank(emergency);
        cacher.disable("");

        vm.prank(admin);
        cacher.enable("");

        assertTrue(cacher.isEnabled(), "enabled");
    }

    // given PriceCache version changed
    //  when enabled
    //   then the call reverts
    function test_givenPriceCacheVersionChanged_whenEnabled_reverts() public {
        vm.prank(emergency);
        cacher.disable("");
        priceCache.setVersion(2, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacher.PriceCacher_UnsupportedPriceCacheVersion.selector,
                address(priceCache),
                2,
                0
            )
        );
        vm.prank(admin);
        cacher.enable("");
    }

    // given PriceCacher is disabled within its grace period
    //  when admin re-enables it
    //   then the policy becomes re-enabled
    function test_givenDisabledWithinGrace_whenAdminReEnables() public {
        vm.prank(emergency);
        cacher.disable("");

        vm.prank(admin);
        cacher.reEnable();

        assertTrue(cacher.isEnabled(), "enabled");
    }

    // given PriceCache version changed
    //  when re-enabled
    //   then the call reverts
    function test_givenPriceCacheVersionChanged_whenReEnabled_reverts() public {
        vm.prank(emergency);
        cacher.disable("");
        priceCache.setVersion(2, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacher.PriceCacher_UnsupportedPriceCacheVersion.selector,
                address(priceCache),
                2,
                0
            )
        );
        vm.prank(admin);
        cacher.reEnable();
    }
}
