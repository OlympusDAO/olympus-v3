// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {CompoundedInterest} from "libraries/CompoundedInterest.sol";

contract CompoundedInterestTest is Test {
    using CompoundedInterest for uint256;

    uint96 public constant ONE_YEAR = 365 days;

    uint96 public constant ZERO_PCT_INTEREST = 0e18;
    uint96 public constant ZERO_PCT_1DAY = 100e18;
    uint96 public constant ZERO_PCT_30DAY = 100e18;
    uint96 public constant ZERO_PCT_1YEAR = 100e18;

    uint96 public constant ONE_PCT_INTEREST = 0.01e18 / ONE_YEAR;
    uint96 public constant ONE_PCT_1DAY = 100_002739763550996000;
    uint96 public constant ONE_PCT_30DAY = 100_082225567304790900;
    uint96 public constant ONE_PCT_1YEAR = 101_005016705748657200;

    uint96 public constant FIVE_PCT_INTEREST = 0.05e18 / ONE_YEAR;
    uint96 public constant FIVE_PCT_1DAY = 100_013699568440542400;
    uint96 public constant FIVE_PCT_30DAY = 100_411804498116151900;
    uint96 public constant FIVE_PCT_1YEAR = 105_127109636978369400;

    uint96 public constant TEN_PCT_INTEREST = 0.10e18 / ONE_YEAR;
    uint96 public constant TEN_PCT_1DAY = 100_027401013662839400;
    uint96 public constant TEN_PCT_30DAY = 100_825304825678990900;
    uint96 public constant TEN_PCT_1YEAR = 110_517091806252703500;

    uint256 public initialPrincipalAmount = 100e18;
    uint256 public zeroPrincipalAmount = 0e18;

    // Zero percent interest tests
    function test_compound_zeroPct_dayOne() public {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            1 days,
            ZERO_PCT_INTEREST
        );
        assertEq(newInterestRate, ZERO_PCT_1DAY);
    }

    function test_compound_zeroPct_dayThirty() public {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            30 days,
            ZERO_PCT_INTEREST
        );
        assertEq(newInterestRate, ZERO_PCT_30DAY);
    }

    function test_compound_zeroPct_yearOne() public {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            365 days,
            ZERO_PCT_INTEREST
        );
        assertEq(newInterestRate, ZERO_PCT_1YEAR);
    }

    // One percent interest tests
    function test_compound_onePct_dayOne() public {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            1 days,
            ONE_PCT_INTEREST
        );
        assertEq(newInterestRate, ONE_PCT_1DAY);
    }

    function test_compound_onePct_dayThirty() public {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            30 days,
            ONE_PCT_INTEREST
        );
        assertEq(newInterestRate, ONE_PCT_30DAY);
    }

    function test_compound_onePct_yearOne() public {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            365 days,
            ONE_PCT_INTEREST
        );
        assertEq(newInterestRate, ONE_PCT_1YEAR);
    }

    // Five percent interest tests
    function test_compound_fivePct_dayOne() public {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            1 days,
            FIVE_PCT_INTEREST
        );
        assertEq(newInterestRate, FIVE_PCT_1DAY);
    }

    function test_compound_fivePct_dayThirty() public {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            30 days,
            FIVE_PCT_INTEREST
        );
        assertEq(newInterestRate, FIVE_PCT_30DAY);
    }

    function test_compound_fivePct_yearOne() public {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            365 days,
            FIVE_PCT_INTEREST
        );
        assertEq(newInterestRate, FIVE_PCT_1YEAR);
    }

    // Ten percent interest tests
    function test_compound_yenPct_dayOne() public {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            1 days,
            TEN_PCT_INTEREST
        );
        assertEq(newInterestRate, TEN_PCT_1DAY);
    }

    function test_compound_yenPct_dayThirty() public {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            30 days,
            TEN_PCT_INTEREST
        );
        assertEq(newInterestRate, TEN_PCT_30DAY);
    }

    function test_compound_yenPct_yearOne() public {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            365 days,
            TEN_PCT_INTEREST
        );
        assertEq(newInterestRate, TEN_PCT_1YEAR);
    }

    function test_compound_zeroPrincipal() public {
        uint256 newInterestRate = zeroPrincipalAmount.continuouslyCompounded(
            1 days,
            FIVE_PCT_INTEREST
        );
        assertEq(newInterestRate, 0e18);
    }

    function test_compound_zeroDays() public {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            0 days,
            FIVE_PCT_INTEREST
        );
        assertEq(newInterestRate, initialPrincipalAmount);
    }

    // Revert tests
    function test_compute_maxPrincipal_expectOverflow() public {
        vm.expectRevert();
        type(uint256).max.continuouslyCompounded(1 days, TEN_PCT_INTEREST);
    }

    function test_compute_maxRate_expectInputTooBig() public {
        vm.expectRevert();
        initialPrincipalAmount.continuouslyCompounded(1 days, type(uint96).max);
    }

    function test_compute_maxDays_expectInputTooBig() public {
        vm.expectRevert();
        initialPrincipalAmount.continuouslyCompounded(
            type(uint96).max,
            TEN_PCT_INTEREST
        );
    }
}
