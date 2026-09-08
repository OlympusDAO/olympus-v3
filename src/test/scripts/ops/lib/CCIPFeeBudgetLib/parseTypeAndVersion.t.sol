// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

import {CCIPFeeBudgetLibTest} from "src/test/scripts/ops/lib/CCIPFeeBudgetLib/CCIPFeeBudgetLibTest.sol";

contract CCIPFeeBudgetLibTests_parseTypeAndVersion is CCIPFeeBudgetLibTest {
    // when the string has no space
    //   [X] it does not parse
    function test_whenNoSpace() public view {
        _assertNotParsed("OnRamp");
        _assertNotParsed("OnRamp2.0.0");
        _assertNotParsed("");
    }

    // when the family is empty
    //   [X] it does not parse
    function test_whenFamilyIsEmpty() public view {
        _assertNotParsed(" 2.0.0");
    }

    // when the version has no major digits
    //   [X] it does not parse
    function test_whenMajorIsNotDigits() public view {
        _assertNotParsed("OnRamp x.0.0");
        _assertNotParsed("OnRamp .0.0");
        _assertNotParsed("OnRamp -dev");
    }

    // when the version has no dot after the major
    //   [X] it does not parse
    function test_whenNoDotAfterMajor() public view {
        _assertNotParsed("OnRamp 2");
        _assertNotParsed("OnRamp 2-dev");
    }

    // when the version has no minor digits
    //   [X] it does not parse
    function test_whenMinorIsNotDigits() public view {
        _assertNotParsed("OnRamp 2.");
        _assertNotParsed("OnRamp 2.x");
        _assertNotParsed("OnRamp 2.-dev");
    }

    // when the string ends with a space
    //   [X] it does not parse, since the version part is empty
    function test_whenTrailingSpace() public view {
        _assertNotParsed("OnRamp 2.0.0 ");
    }

    // when a version component has eleven digits
    //   [X] it does not parse
    function test_whenMajorHasElevenDigits() public view {
        _assertNotParsed("OnRamp 12345678901.0");
        _assertNotParsed("OnRamp 1.12345678901");
    }

    // when a version component has ten digits, the width of a uint32
    //   [X] it parses to that value
    function test_whenMajorHasTenDigits() public view {
        _assertParsed("OnRamp 4294967295.0", "OnRamp", 4_294_967_295, 0);
        _assertParsed("OnRamp 0.4294967295", "OnRamp", 0, 4_294_967_295);
    }

    // when the string is a live ramp or quoter version
    //   [X] it parses the family, the major and the minor
    function test_whenLiveVersionStrings() public view {
        _assertParsed("OnRamp 2.0.0", "OnRamp", 2, 0);
        _assertParsed("OnRamp 1.6.0", "OnRamp", 1, 6);
        _assertParsed("EVM2EVMOnRamp 1.5.0", "EVM2EVMOnRamp", 1, 5);
        _assertParsed("FeeQuoter 2.0.0", "FeeQuoter", 2, 0);
        _assertParsed("FeeQuoter 1.6.3", "FeeQuoter", 1, 6);
        _assertParsed("PriceRegistry 1.2.0", "PriceRegistry", 1, 2);
        _assertParsed("LockReleaseTokenPool 1.5.1", "LockReleaseTokenPool", 1, 5);
        _assertParsed("RMN 2.1.0", "RMN", 2, 1);
    }

    // when the version carries a suffix after the patch
    //   [X] it parses the major and the minor and ignores the rest
    function test_whenVersionHasSuffix() public view {
        _assertParsed("FeeQuoter 1.6.1-dev", "FeeQuoter", 1, 6);
        _assertParsed("OnRamp 2.1.0-rc.1", "OnRamp", 2, 1);
    }

    // when the version has no patch
    //   [X] it parses the major and the minor
    function test_whenVersionHasNoPatch() public view {
        _assertParsed("OnRamp 2.1", "OnRamp", 2, 1);
    }

    // when the family contains spaces
    //   [X] the family is everything before the last space
    function test_whenFamilyContainsSpaces() public view {
        _assertParsed("Burn Mint Token Pool 1.5.1", "Burn Mint Token Pool", 1, 5);
    }

    // when the major, the minor and the patch are any values
    //   [X] it parses the major and the minor back
    function test_whenAnyVersionNumbers(uint32 major_, uint32 minor_, uint32 patch_) public view {
        string memory raw = string.concat(
            "OnRamp ",
            vm.toString(uint256(major_)),
            ".",
            vm.toString(uint256(minor_)),
            ".",
            vm.toString(uint256(patch_))
        );
        _assertParsed(raw, "OnRamp", major_, minor_);
    }
}
