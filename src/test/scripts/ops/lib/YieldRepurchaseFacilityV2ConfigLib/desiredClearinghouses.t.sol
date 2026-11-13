// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";
import {YieldRepurchaseFacilityV2ConfigLibTest} from "src/test/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib/YieldRepurchaseFacilityV2ConfigLibTest.sol";

contract YieldRepurchaseFacilityV2ConfigLibTests_desiredClearinghouses is
    YieldRepurchaseFacilityV2ConfigLibTest
{
    // ========== HELPERS ========== //

    function _read(
        string memory config_
    ) internal view returns (YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[] memory) {
        return harness.desiredClearinghouses(_envWithConfig(config_), CHAIN);
    }

    /// @notice A Clearinghouse entry built from two of its three members.
    function _partialEntry(
        string memory first_,
        string memory second_
    ) internal pure returns (string memory entry) {
        return string.concat("{", first_, ",", second_, "}");
    }

    function _indexedPath(uint256 index_) internal pure returns (string memory path) {
        return string.concat(CLEARINGHOUSES_PATH, "[", vm.toString(index_), "]");
    }

    // ========== MALFORMED ARRAY ========== //

    // when the clearinghouses key is missing
    //   [X] it reverts naming the key
    function test_whenClearinghousesAreMissing_reverts() public {
        _expectRevertMissingKey(CLEARINGHOUSES_PATH);
        _read(_validParameterMembers());
    }

    // when the clearinghouses value is an object
    //   [X] it reverts naming the key and the expected shape
    function test_whenClearinghousesAreAnObject_reverts() public {
        string memory member = _member(
            "clearinghouses",
            string.concat("{", _member("first", _clearinghouse(clearinghouseA, true, 0)), "}")
        );

        _expectRevertMessage(
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: ",
                CLEARINGHOUSES_PATH,
                " is an object, expected an array of {address, included, offset} entries"
            )
        );
        _read(member);
    }

    // ========== MALFORMED ENTRIES ========== //

    // when an entry lacks the address
    //   [X] it reverts naming the indexed key
    function test_whenAddressIsMissing_reverts() public {
        string memory entries = _join(
            _clearinghouse(clearinghouseA, true, 0),
            _partialEntry(_member("included", "true"), _member("offset", _quoted(uint256(7))))
        );

        _expectRevertMissingKey(string.concat(_indexedPath(1), ".address"));
        _read(_clearinghouseMember(entries));
    }

    // when an entry lacks the included flag
    //   [X] it reverts naming the indexed key
    function test_whenIncludedIsMissing_reverts() public {
        string memory entries = _join(
            _clearinghouse(clearinghouseA, true, 0),
            _partialEntry(
                _member("address", _quoted(clearinghouseB)),
                _member("offset", _quoted(uint256(7)))
            )
        );

        _expectRevertMissingKey(string.concat(_indexedPath(1), ".included"));
        _read(_clearinghouseMember(entries));
    }

    // when an entry lacks the offset
    //   [X] it reverts naming the indexed key, rather than shifting the offsets that follow
    function test_whenOffsetIsMissing_reverts() public {
        string memory entries = _partialEntry(
            _member("address", _quoted(clearinghouseA)),
            _member("included", "true")
        );
        entries = _join(entries, _clearinghouse(clearinghouseB, true, 7));

        _expectRevertMissingKey(string.concat(_indexedPath(0), ".offset"));
        _read(_clearinghouseMember(entries));
    }

    // when an entry carries the zero address
    //   [X] it reverts naming the indexed key
    function test_whenAddressIsZero_reverts() public {
        _expectRevertZeroAddress(string.concat(_indexedPath(0), ".address"));
        _read(_clearinghouseMember(_clearinghouse(address(0), false, 0)));
    }

    // when two adjacent entries carry one address
    //   [X] it reverts naming both entries and the address
    function test_whenAdjacentEntriesRepeatAddress_reverts() public {
        string memory entries = _join(
            _clearinghouse(clearinghouseA, true, 0),
            _clearinghouse(clearinghouseA, false, 5)
        );

        _expectRevertMessage(
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: ",
                _indexedPath(1),
                " repeats the Clearinghouse ",
                vm.toString(clearinghouseA),
                " of ",
                _indexedPath(0)
            )
        );
        _read(_clearinghouseMember(entries));
    }

    // when the first and the last entry carry one address
    //   [X] it reverts naming both entries and the address
    function test_whenDistantEntriesRepeatAddress_reverts() public {
        string memory entries = _clearinghouse(clearinghouseA, true, 0);
        entries = _join(entries, _clearinghouse(clearinghouseB, true, 0));
        entries = _join(entries, _clearinghouse(clearinghouseA, true, 0));

        _expectRevertMessage(
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: ",
                _indexedPath(2),
                " repeats the Clearinghouse ",
                vm.toString(clearinghouseA),
                " of ",
                _indexedPath(0)
            )
        );
        _read(_clearinghouseMember(entries));
    }

    // ========== SUCCESS ========== //

    // when the array is empty
    //   [X] it returns no entry
    function test_whenArrayIsEmpty() public view {
        assertEq(_read(_clearinghouseMember("")).length, 0, "clearinghouses.length");
    }

    // when the array holds one entry
    //   [X] it reads the entry
    function test_whenOneEntry() public view {
        YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[] memory clearinghouses = _read(
            _clearinghouseMember(_clearinghouse(clearinghouseA, true, 42))
        );

        assertEq(clearinghouses.length, 1, "clearinghouses.length");
        _assertClearinghouse(clearinghouses[0], clearinghouseA, true, 42, "clearinghouses[0]");
    }

    // when the array holds three entries
    //   [X] it reads them in the order of the array, each with its own fields
    function test_whenThreeEntries() public view {
        YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[] memory clearinghouses = _read(
            _validClearinghouseMember()
        );

        assertEq(clearinghouses.length, 3, "clearinghouses.length");
        _assertClearinghouse(clearinghouses[0], clearinghouseA, true, 0, "clearinghouses[0]");
        _assertClearinghouse(
            clearinghouses[1],
            clearinghouseB,
            true,
            2_000_000e18,
            "clearinghouses[1]"
        );
        _assertClearinghouse(clearinghouses[2], clearinghouseC, false, 5, "clearinghouses[2]");
    }

    // when an offset is written as a JSON number
    //   [X] it reads the offset
    function test_whenOffsetIsJsonNumber() public view {
        string memory entry = string.concat(
            "{",
            _member("address", _quoted(clearinghouseA)),
            ",",
            _member("included", "false"),
            ",",
            _member("offset", "123456"),
            "}"
        );

        YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[] memory clearinghouses = _read(
            _clearinghouseMember(entry)
        );

        _assertClearinghouse(clearinghouses[0], clearinghouseA, false, 123456, "clearinghouses[0]");
    }

    // when an offset is any uint256
    //   [X] it reads the offset unchanged: the library applies no bound to it
    function test_whenOffsetIsAnyValue(uint256 offset_) public view {
        YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[] memory clearinghouses = _read(
            _clearinghouseMember(_clearinghouse(clearinghouseA, true, offset_))
        );

        assertEq(clearinghouses[0].offset, offset_, "clearinghouses[0].offset");
    }

    // when an offset is the largest uint256
    //   [X] it reads the offset
    function test_whenOffsetIsMaxUint256() public view {
        YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse[] memory clearinghouses = _read(
            _clearinghouseMember(_clearinghouse(clearinghouseA, true, type(uint256).max))
        );

        assertEq(clearinghouses[0].offset, type(uint256).max, "clearinghouses[0].offset");
    }
}
