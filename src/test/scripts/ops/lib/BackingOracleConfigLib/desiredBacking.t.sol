// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {BackingOracleConfigLibTest} from "src/test/scripts/ops/lib/BackingOracleConfigLib/BackingOracleConfigLibTest.sol";

contract BackingOracleConfigLibTests_desiredBacking is BackingOracleConfigLibTest {
    // ========== HELPERS ========== //

    function _expectRevertZeroBacking() internal {
        _expectRevertMessage(
            string.concat(
                "BackingOracleConfigLib: the value of ",
                BACKING_PATH,
                " is zero; the oracle rejects a zero backing"
            )
        );
    }

    // ========== REVERTS ========== //

    // when the backing key is missing
    //   [X] it reverts naming the key
    function test_whenBackingIsMissing_reverts() public {
        _expectRevertMessage(
            string.concat("BackingOracleConfigLib: missing env.json key ", BACKING_PATH)
        );
        harness.desiredBacking(_env(""), CHAIN);
    }

    // when the chain is another chain of the same file
    //   [X] it reverts naming the key under that chain
    function test_whenChainHasNoConfig_reverts() public {
        _expectRevertMessage(
            "BackingOracleConfigLib: missing env.json key .current.other.olympus.config.BackingOracle.backing"
        );
        harness.desiredBacking(_envWithBacking(_quoted(BACKING)), "other");
    }

    // when the backing is zero, written as a JSON string
    //   [X] it reverts naming the key
    function test_whenBackingIsZeroString_reverts() public {
        _expectRevertZeroBacking();
        harness.desiredBacking(_envWithBacking(_quoted(0)), CHAIN);
    }

    // when the backing is zero, written as a JSON number
    //   [X] it reverts naming the key
    function test_whenBackingIsZeroNumber_reverts() public {
        _expectRevertZeroBacking();
        harness.desiredBacking(_envWithBacking("0"), CHAIN);
    }

    // ========== SUCCESS ========== //

    // when the backing is written as a JSON string
    //   [X] it reads the backing
    function test_whenBackingIsJsonString() public view {
        assertEq(
            harness.desiredBacking(_envWithBacking(_quoted(BACKING)), CHAIN),
            BACKING,
            "backing"
        );
    }

    // when the backing is written as a JSON number
    //   [X] it reads the backing
    function test_whenBackingIsJsonNumber() public view {
        assertEq(harness.desiredBacking(_envWithBacking("1204"), CHAIN), 1204, "backing");
    }

    // when the backing is one
    //   [X] it reads the backing
    function test_whenBackingIsOne() public view {
        assertEq(harness.desiredBacking(_envWithBacking(_quoted(1)), CHAIN), 1, "backing");
    }

    // when the backing is the largest uint256
    //   [X] it reads the backing
    function test_whenBackingIsMaxUint256() public view {
        assertEq(
            harness.desiredBacking(_envWithBacking(_quoted(type(uint256).max)), CHAIN),
            type(uint256).max,
            "backing"
        );
    }

    // when the backing is any non-zero value
    //   [X] it reads the backing unchanged: the library applies no upper bound
    function test_whenBackingIsInValidInterval(uint256 backing_) public view {
        // The valid interval is [1, type(uint256).max]
        uint256 backing = bound(backing_, 1, type(uint256).max);

        assertEq(harness.desiredBacking(_envWithBacking(_quoted(backing)), CHAIN), backing, "backing");
    }

    // given the env.json of the repository
    //   when the chain is mainnet
    //     [X] it reads a non-zero backing
    function test_givenRepositoryEnv_whenChainIsMainnet() public view {
        string memory env = vm.readFile("./src/scripts/env.json");

        assertGt(harness.desiredBacking(env, "mainnet"), 0, "backing");
    }

    // ========== backingPath ========== //

    // when the chain is given
    //   [X] it returns the path of the backing key of that chain
    function test_backingPath() public view {
        assertEq(harness.backingPath(CHAIN), BACKING_PATH, "backingPath");
    }
}
