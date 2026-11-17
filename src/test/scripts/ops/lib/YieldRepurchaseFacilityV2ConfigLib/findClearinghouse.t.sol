// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";
import {YieldRepurchaseFacilityV2ConfigLibTest} from "src/test/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib/YieldRepurchaseFacilityV2ConfigLibTest.sol";

contract YieldRepurchaseFacilityV2ConfigLibTests_findClearinghouse is
    YieldRepurchaseFacilityV2ConfigLibTest
{
    // ========== HELPERS ========== //

    function _clearinghouses()
        internal
        view
        returns (YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[] memory)
    {
        return harness.desiredClearinghouses(_validEnv(), CHAIN);
    }

    // ========== TESTS ========== //

    // when no Clearinghouse is declared
    //   [X] it reports the address as not declared
    function test_whenClearinghousesAreEmpty(address clearinghouse_) public view {
        (
            bool declared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse memory entry
        ) = harness.findClearinghouse(
                new YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[](0),
                clearinghouse_
            );

        assertFalse(declared, "declared");
        assertEq(entry.clearinghouse, address(0), "entry.clearinghouse");
    }

    // when the address is not a declared Clearinghouse
    //   [X] it reports the address as not declared
    //   [X] it returns an empty entry
    function test_whenClearinghouseIsNotDeclared(address clearinghouse_) public view {
        vm.assume(clearinghouse_ != clearinghouseA);
        vm.assume(clearinghouse_ != clearinghouseB);
        vm.assume(clearinghouse_ != clearinghouseC);

        (
            bool declared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse memory entry
        ) = harness.findClearinghouse(_clearinghouses(), clearinghouse_);

        assertFalse(declared, "declared");
        _assertClearinghouse(entry, address(0), false, 0, "entry");
    }

    // when the address is the first declared Clearinghouse
    //   [X] it returns that entry
    function test_whenClearinghouseIsFirstEntry() public view {
        (
            bool declared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse memory entry
        ) = harness.findClearinghouse(_clearinghouses(), clearinghouseA);

        assertTrue(declared, "declared");
        _assertClearinghouse(entry, clearinghouseA, true, 0, "entry");
    }

    // when the address is a declared Clearinghouse in the middle of the array
    //   [X] it returns that entry
    function test_whenClearinghouseIsMiddleEntry() public view {
        (
            bool declared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse memory entry
        ) = harness.findClearinghouse(_clearinghouses(), clearinghouseB);

        assertTrue(declared, "declared");
        _assertClearinghouse(entry, clearinghouseB, true, 2_000_000e18, "entry");
    }

    // when the address is the last declared Clearinghouse
    //   [X] it returns that entry
    function test_whenClearinghouseIsLastEntry() public view {
        (
            bool declared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse memory entry
        ) = harness.findClearinghouse(_clearinghouses(), clearinghouseC);

        assertTrue(declared, "declared");
        _assertClearinghouse(entry, clearinghouseC, false, 5, "entry");
    }
}
