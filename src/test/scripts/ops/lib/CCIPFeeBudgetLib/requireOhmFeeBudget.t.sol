// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {CCIPFeeBudgetLibTest} from "src/test/scripts/ops/lib/CCIPFeeBudgetLib/CCIPFeeBudgetLibTest.sol";

contract CCIPFeeBudgetLibTests_requireOhmFeeBudget is CCIPFeeBudgetLibTest {
    // given an OnRamp lane without a token entry
    //   [X] it reverts naming the chain default, even when the default covers the minimum
    function test_givenOnRamp20Lane_givenNoTokenEntry_reverts() public givenOnRamp20Lane {
        _setNoTokenEntry20();
        _setDestConfig20(EVM_FAMILY_WORD, MIN_BUDGET);

        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: the OHM delivery gas budget of the lane ",
                LANE,
                " has no enabled OHM token entry (the applicable value is the chain default ",
                vm.toString(uint256(MIN_BUDGET)),
                "; chain default, FeeQuoter 2.0.0 via OnRamp 2.0.0 (no OHM entry)); request an enabled OHM fee entry of at least ",
                vm.toString(uint256(MIN_BUDGET)),
                " from Chainlink before opening the route"
            )
        );
        _requireBudget();
    }

    // given a legacy lane without a token entry
    //   [X] it reverts naming the lane default
    function test_givenLegacyLane_givenNoTokenEntry_reverts()
        public
        givenLegacyLane
        givenLegacyNoTokenEntry
    {
        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: the OHM delivery gas budget of the lane ",
                LANE,
                " has no enabled OHM token entry (the applicable value is the chain default ",
                vm.toString(uint256(CHAIN_DEFAULT)),
                "; chain default, EVM2EVMOnRamp 1.5.0 (no OHM entry)); request an enabled OHM fee entry of at least ",
                vm.toString(uint256(MIN_BUDGET)),
                " from Chainlink before opening the route"
            )
        );
        _requireBudget();
    }

    // given an OnRamp lane with a token entry one below the minimum
    //   [X] it reverts naming the value
    function test_givenOnRamp20Lane_givenTokenEntryBelowMinimum_reverts()
        public
        givenOnRamp20Lane
        givenTokenEntry(MIN_BUDGET - 1)
    {
        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: the OHM delivery gas budget of the lane ",
                LANE,
                " is ",
                vm.toString(uint256(MIN_BUDGET - 1)),
                " (OHM token entry, FeeQuoter 2.0.0 via OnRamp 2.0.0), below the required ",
                vm.toString(uint256(MIN_BUDGET)),
                "; request an enabled OHM fee entry from Chainlink before opening the route"
            )
        );
        _requireBudget();
    }

    // given an OnRamp lane with a token entry of zero
    //   [X] it reverts
    function test_givenOnRamp20Lane_givenTokenEntryZero_reverts()
        public
        givenOnRamp20Lane
        givenTokenEntry(0)
    {
        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: the OHM delivery gas budget of the lane ",
                LANE,
                " is 0 (OHM token entry, FeeQuoter 2.0.0 via OnRamp 2.0.0), below the required ",
                vm.toString(uint256(MIN_BUDGET)),
                "; request an enabled OHM fee entry from Chainlink before opening the route"
            )
        );
        _requireBudget();
    }

    // given an OnRamp lane with a token entry anywhere below the minimum
    //   [X] it reverts
    function test_givenOnRamp20Lane_givenTokenEntryInInvalidInterval_reverts(
        uint32 budget_
    ) public givenOnRamp20Lane {
        // The invalid interval is [0, MIN_BUDGET - 1]
        uint32 boundedBudget = uint32(bound(budget_, 0, MIN_BUDGET - 1));
        _setTokenEntry20(boundedBudget);

        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: the OHM delivery gas budget of the lane ",
                LANE,
                " is ",
                vm.toString(uint256(boundedBudget)),
                " (OHM token entry, FeeQuoter 2.0.0 via OnRamp 2.0.0), below the required ",
                vm.toString(uint256(MIN_BUDGET)),
                "; request an enabled OHM fee entry from Chainlink before opening the route"
            )
        );
        _requireBudget();
    }

    // given an OnRamp lane with a token entry exactly at the minimum
    //   [X] it passes
    function test_givenOnRamp20Lane_givenTokenEntryAtMinimum()
        public
        givenOnRamp20Lane
        givenTokenEntry(MIN_BUDGET)
    {
        _requireBudget();
    }

    // given an OnRamp lane with the maximum representable token entry
    //   [X] it passes
    function test_givenOnRamp20Lane_givenTokenEntryMax()
        public
        givenOnRamp20Lane
        givenTokenEntry(type(uint32).max)
    {
        _requireBudget();
    }

    // given an OnRamp lane with a token entry anywhere at or above the minimum
    //   [X] it passes
    function test_givenOnRamp20Lane_givenTokenEntryInValidInterval(
        uint32 budget_
    ) public givenOnRamp20Lane {
        // The valid interval is [MIN_BUDGET, type(uint32).max]
        uint32 boundedBudget = uint32(bound(budget_, MIN_BUDGET, type(uint32).max));
        _setTokenEntry20(boundedBudget);

        _requireBudget();
    }

    // given a legacy lane with a token entry at the minimum
    //   [X] it passes
    function test_givenLegacyLane_givenTokenEntryAtMinimum()
        public
        givenLegacyLane
        givenLegacyTokenEntry(MIN_BUDGET)
    {
        _requireBudget();
    }

    // given a legacy lane with a token entry one below the minimum
    //   [X] it reverts
    function test_givenLegacyLane_givenTokenEntryBelowMinimum_reverts()
        public
        givenLegacyLane
        givenLegacyTokenEntry(MIN_BUDGET - 1)
    {
        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: the OHM delivery gas budget of the lane ",
                LANE,
                " is ",
                vm.toString(uint256(MIN_BUDGET - 1)),
                " (OHM token entry, EVM2EVMOnRamp 1.5.0), below the required ",
                vm.toString(uint256(MIN_BUDGET)),
                "; request an enabled OHM fee entry from Chainlink before opening the route"
            )
        );
        _requireBudget();
    }
}
