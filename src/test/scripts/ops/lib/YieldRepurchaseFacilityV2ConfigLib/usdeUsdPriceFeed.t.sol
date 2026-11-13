// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {YieldRepurchaseFacilityV2ConfigLibTest} from "src/test/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib/YieldRepurchaseFacilityV2ConfigLibTest.sol";

contract YieldRepurchaseFacilityV2ConfigLibTests_usdeUsdPriceFeed is
    YieldRepurchaseFacilityV2ConfigLibTest
{
    // when the feed key is missing
    //   [X] it reverts naming the key
    function test_whenFeedIsMissing_reverts() public {
        _expectRevertMissingKey(FEED_PATH);
        harness.usdeUsdPriceFeed(_env("", "", ""), CHAIN);
    }

    // when the feed key holds the zero address
    //   [X] it reverts naming the key
    function test_whenFeedIsZeroAddress_reverts() public {
        _expectRevertZeroAddress(FEED_PATH);
        harness.usdeUsdPriceFeed(
            _env("", "", _member("usdeUsdPriceFeed", _quoted(address(0)))),
            CHAIN
        );
    }

    // when the feed key holds an address
    //   [X] it reads the address
    function test_whenFeedIsSet() public view {
        assertEq(harness.usdeUsdPriceFeed(_validEnv(), CHAIN), usdeFeed, "usdeUsdPriceFeed");
    }

    // when the feed key holds any non-zero address
    //   [X] it reads the address
    function test_whenFeedIsAnyAddress(address feed_) public view {
        vm.assume(feed_ != address(0));

        assertEq(
            harness.usdeUsdPriceFeed(
                _env("", "", _member("usdeUsdPriceFeed", _quoted(feed_))),
                CHAIN
            ),
            feed_,
            "usdeUsdPriceFeed"
        );
    }
}
