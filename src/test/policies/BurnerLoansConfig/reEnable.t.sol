// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigReEnableTest is BurnerLoansTest {
    // reEnable
    // given the config was disabled at a fuzzed timestamp
    //  and a fuzzed elapsed time is within its grace period
    //  when burner_loans_admin re-enables it
    //   then the config returns to the enabled state
    function test_givenBurnerLoansAdminWithinGracePeriod_reenables(
        uint48 disabledAt_,
        uint32 elapsed_
    ) public {
        uint48 disabledAt = uint48(
            bound(
                disabledAt_,
                1,
                uint256(type(uint48).max) - BurnerLoansConstants.REENABLE_GRACE_PERIOD
            )
        );
        uint32 elapsed = uint32(bound(elapsed_, 0, BurnerLoansConstants.REENABLE_GRACE_PERIOD));

        vm.warp(disabledAt);
        vm.prank(emergency);
        burnerLoansConfig.disable("");

        vm.warp(uint256(disabledAt) + elapsed);
        vm.prank(burnerLoansAdmin);
        burnerLoansConfig.reEnable();

        assertTrue(burnerLoansConfig.isEnabled(), "config enabled");
        assertEq(burnerLoansConfig.lastTransitionAt(), uint48(block.timestamp), "last transition");
    }

    // reEnable
    // given the config was disabled at a fuzzed timestamp
    //  and a fuzzed elapsed time is after its grace period
    //  when burner_loans_admin attempts to re-enable it
    //   then it reverts
    function test_givenGracePeriodElapsed_reverts(
        uint48 disabledAt_,
        uint48 elapsedAfterDeadline_
    ) public {
        uint48 elapsedAfterDeadline = uint48(bound(elapsedAfterDeadline_, 1, 365 days));
        uint48 disabledAt = uint48(
            bound(
                disabledAt_,
                1,
                uint256(type(uint48).max) -
                    BurnerLoansConstants.REENABLE_GRACE_PERIOD -
                    elapsedAfterDeadline
            )
        );

        vm.warp(disabledAt);
        vm.prank(emergency);
        burnerLoansConfig.disable("");

        uint48 deadline = disabledAt + BurnerLoansConstants.REENABLE_GRACE_PERIOD;
        vm.warp(uint256(deadline) + elapsedAfterDeadline);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        burnerLoansConfig.reEnable();
    }
}
