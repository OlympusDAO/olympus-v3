// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {CompoundedInterest} from "libraries/CompoundedInterest.sol";

contract CompoundedInterestTest is Test {
    using CompoundedInterest for uint256;

    uint96 public constant ZERO_PCT_INTEREST = 0e18;
    uint96 public constant ZERO_PCT_1DAY = 100e18;
    uint96 public constant ZERO_PCT_30DAY = 100e18;
    uint96 public constant ZERO_PCT_1YEAR = 100e18;

    uint96 public constant ONE_PCT_INTEREST = 0.01e18;
    uint96 public constant ONE_PCT_1DAY = 100_002739763558233400;
    uint96 public constant ONE_PCT_30DAY = 100_082225567522087300;
    uint96 public constant ONE_PCT_1YEAR = 101_005016708416805700;

    uint96 public constant FIVE_PCT_INTEREST = 0.05e18;
    uint96 public constant FIVE_PCT_1DAY = 100_013699568442168900;
    uint96 public constant FIVE_PCT_30DAY = 100_411804498165141900;
    uint96 public constant FIVE_PCT_1YEAR = 105_127109637602403900;

    uint96 public constant TEN_PCT_INTEREST = 0.10e18;
    uint96 public constant TEN_PCT_1DAY = 100_027401013666092900;
    uint96 public constant TEN_PCT_30DAY = 100_825304825777374200;
    uint96 public constant TEN_PCT_1YEAR = 110_517091807564762400;

    uint256 public initialPrincipalAmount = 100e18;
    uint256 public zeroPrincipalAmount = 0e18;

    // Zero percent interest tests
    function test_compound_zeroPct_dayOne() public view {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            1 days,
            ZERO_PCT_INTEREST
        );
        assertEq(newInterestRate, ZERO_PCT_1DAY);
    }

    function test_compound_zeroPct_dayThirty() public view {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            30 days,
            ZERO_PCT_INTEREST
        );
        assertEq(newInterestRate, ZERO_PCT_30DAY);
    }

    function test_compound_zeroPct_yearOne() public view {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            365 days,
            ZERO_PCT_INTEREST
        );
        assertEq(newInterestRate, ZERO_PCT_1YEAR);
    }

    // One percent interest tests
    function test_compound_onePct_dayOne() public view {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            1 days,
            ONE_PCT_INTEREST
        );
        assertEq(newInterestRate, ONE_PCT_1DAY);
    }

    function test_compound_onePct_dayThirty() public view {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            30 days,
            ONE_PCT_INTEREST
        );
        assertEq(newInterestRate, ONE_PCT_30DAY);
    }

    function test_compound_onePct_yearOne() public view {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            365 days,
            ONE_PCT_INTEREST
        );
        assertEq(newInterestRate, ONE_PCT_1YEAR);
    }

    // Five percent interest tests
    function test_compound_fivePct_dayOne() public view {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            1 days,
            FIVE_PCT_INTEREST
        );
        assertEq(newInterestRate, FIVE_PCT_1DAY);
    }

    function test_compound_fivePct_dayThirty() public view {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            30 days,
            FIVE_PCT_INTEREST
        );
        assertEq(newInterestRate, FIVE_PCT_30DAY);
    }

    function test_compound_fivePct_yearOne() public view {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            365 days,
            FIVE_PCT_INTEREST
        );
        assertEq(newInterestRate, FIVE_PCT_1YEAR);
    }

    // Ten percent interest tests
    function test_compound_yenPct_dayOne() public view {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            1 days,
            TEN_PCT_INTEREST
        );
        assertEq(newInterestRate, TEN_PCT_1DAY);
    }

    function test_compound_yenPct_dayThirty() public view {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            30 days,
            TEN_PCT_INTEREST
        );
        assertEq(newInterestRate, TEN_PCT_30DAY);
    }

    function test_compound_yenPct_yearOne() public view {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            365 days,
            TEN_PCT_INTEREST
        );
        assertEq(newInterestRate, TEN_PCT_1YEAR);
    }

    function test_compound_zeroPrincipal() public view {
        uint256 newInterestRate = zeroPrincipalAmount.continuouslyCompounded(
            1 days,
            FIVE_PCT_INTEREST
        );
        assertEq(newInterestRate, 0e18);
    }

    function test_compound_zeroDays() public view {
        uint256 newInterestRate = initialPrincipalAmount.continuouslyCompounded(
            0 days,
            FIVE_PCT_INTEREST
        );
        assertEq(newInterestRate, initialPrincipalAmount);
    }

    // Revert tests
    /// forge-config: default.allow_internal_expect_revert = true
    function test_compute_maxPrincipal_expectOverflow() public {
        vm.expectRevert();
        type(uint256).max.continuouslyCompounded(1 days, TEN_PCT_INTEREST);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_compute_maxRate_expectInputTooBig() public {
        vm.expectRevert("EXP_OVERFLOW");
        initialPrincipalAmount.continuouslyCompounded(1 days, type(uint96).max);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_compute_maxDays_expectInputTooBig() public {
        vm.expectRevert("EXP_OVERFLOW");
        initialPrincipalAmount.continuouslyCompounded(type(uint96).max, TEN_PCT_INTEREST);
    }
}
