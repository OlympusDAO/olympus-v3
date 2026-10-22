// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {SafeCast} from "src/libraries/SafeCast.sol";
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";
import {CCIPConfigLibTest} from "src/test/scripts/ops/lib/CCIPConfigLib/CCIPConfigLibTest.sol";

contract CCIPConfigLibTests_desiredConfig is CCIPConfigLibTest {
    // ========== HELPERS ========== //

    function _read(
        string memory env_
    ) internal view returns (CCIPConfigLib.DesiredConfig memory config) {
        return harness.desiredConfig(env_, LOCAL_CHAIN);
    }

    function _expectRevertDelayOutOfBound(uint256 delay_) internal {
        _expectRevertMessage(
            string.concat(
                "CCIPConfigLib: the value of ",
                CONFIG_PATH,
                ".timelockDelay is ",
                vm.toString(delay_),
                " seconds, outside the bound of the timelock [",
                vm.toString(uint256(MIN_TIMELOCK_DELAY)),
                ", ",
                vm.toString(uint256(MAX_TIMELOCK_DELAY)),
                "]"
            )
        );
    }

    // ========== MISSING KEYS ========== //

    // given the config block is missing
    //   [X] it reverts naming the first key
    function test_givenConfigBlockMissing_reverts() public {
        _expectRevertMissingKey(string.concat(CONFIG_PATH, ".gracePeriod"));
        _read(_envWithRoutes(""));
    }

    // given the config block lacks the timelock delay
    //   [X] it reverts naming the key
    function test_givenTimelockDelayMissing_reverts() public {
        string memory env = _env(
            string.concat(
                '"CCIPTokenPoolConfig":{"gracePeriod":',
                vm.toString(uint256(GRACE_PERIOD)),
                ',"rebalancer":"',
                vm.toString(rebalancer),
                '","rateLimitAdmin":"',
                vm.toString(rateLimitAdmin),
                '"}'
            )
        );

        _expectRevertMissingKey(string.concat(CONFIG_PATH, ".timelockDelay"));
        _read(env);
    }

    // ========== GRACE PERIOD ========== //

    // when the grace period is zero
    //   [X] it reverts
    function test_whenGracePeriodIsZero_reverts() public {
        _expectRevertMessage("CCIPConfigLib: gracePeriod is zero");
        _read(_envWithConfig(0, TIMELOCK_DELAY));
    }

    // ========== TIMELOCK DELAY ========== //

    // when the timelock delay is zero
    //   [X] it reverts naming the key and the bound
    function test_whenTimelockDelayIsZero_reverts() public {
        _expectRevertDelayOutOfBound(0);
        _read(_envWithConfig(GRACE_PERIOD, 0));
    }

    // when the timelock delay is one below the minimum
    //   [X] it reverts naming the key and the bound
    function test_whenTimelockDelayIsBelowMinimum_reverts() public {
        _expectRevertDelayOutOfBound(MIN_TIMELOCK_DELAY - 1);
        _read(_envWithConfig(GRACE_PERIOD, MIN_TIMELOCK_DELAY - 1));
    }

    // when the timelock delay is anywhere below the minimum
    //   [X] it reverts
    function test_whenTimelockDelayIsInLowerInvalidInterval_reverts(uint48 delay_) public {
        // The invalid interval is [0, MIN_TIMELOCK_DELAY - 1]
        uint256 boundedDelay = bound(delay_, 0, MIN_TIMELOCK_DELAY - 1);

        _expectRevertDelayOutOfBound(boundedDelay);
        _read(_envWithConfig(GRACE_PERIOD, boundedDelay));
    }

    // when the timelock delay is one above the maximum
    //   [X] it reverts naming the key and the bound
    function test_whenTimelockDelayIsAboveMaximum_reverts() public {
        _expectRevertDelayOutOfBound(MAX_TIMELOCK_DELAY + 1);
        _read(_envWithConfig(GRACE_PERIOD, MAX_TIMELOCK_DELAY + 1));
    }

    // when the timelock delay is anywhere above the maximum within uint48
    //   [X] it reverts
    function test_whenTimelockDelayIsInUpperInvalidInterval_reverts(uint48 delay_) public {
        // The invalid interval is [MAX_TIMELOCK_DELAY + 1, type(uint48).max]
        uint256 boundedDelay = bound(delay_, MAX_TIMELOCK_DELAY + 1, type(uint48).max);

        _expectRevertDelayOutOfBound(boundedDelay);
        _read(_envWithConfig(GRACE_PERIOD, boundedDelay));
    }

    // when the timelock delay does not fit a uint48
    //   [X] it reverts with the cast overflow
    function test_whenTimelockDelayExceedsUint48_reverts() public {
        uint256 delay = uint256(type(uint48).max) + 1;

        vm.expectRevert(abi.encodeWithSelector(SafeCast.Overflow.selector, delay));
        _read(_envWithConfig(GRACE_PERIOD, delay));
    }

    // when the timelock delay is the minimum
    //   [X] it reads the delay
    function test_whenTimelockDelayIsMinimum() public view {
        CCIPConfigLib.DesiredConfig memory config = _read(
            _envWithConfig(GRACE_PERIOD, MIN_TIMELOCK_DELAY)
        );

        assertEq(config.timelockDelay, MIN_TIMELOCK_DELAY, "timelockDelay");
    }

    // when the timelock delay is the maximum
    //   [X] it reads the delay
    function test_whenTimelockDelayIsMaximum() public view {
        CCIPConfigLib.DesiredConfig memory config = _read(
            _envWithConfig(GRACE_PERIOD, MAX_TIMELOCK_DELAY)
        );

        assertEq(config.timelockDelay, MAX_TIMELOCK_DELAY, "timelockDelay");
    }

    // when the timelock delay is anywhere within the bound
    //   [X] it reads the delay
    function test_whenTimelockDelayIsInValidInterval(uint48 delay_) public view {
        // The valid interval is [MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]
        uint256 boundedDelay = bound(delay_, MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY);

        CCIPConfigLib.DesiredConfig memory config = _read(
            _envWithConfig(GRACE_PERIOD, boundedDelay)
        );

        assertEq(config.timelockDelay, boundedDelay, "timelockDelay");
    }

    // ========== HAPPY PATH ========== //

    // given a complete config block
    //   [X] it reads the four fields
    function test_givenCompleteConfigBlock() public view {
        CCIPConfigLib.DesiredConfig memory config = _read(
            _envWithConfig(GRACE_PERIOD, TIMELOCK_DELAY)
        );

        assertEq(config.gracePeriod, GRACE_PERIOD, "gracePeriod");
        assertEq(config.timelockDelay, TIMELOCK_DELAY, "timelockDelay");
        assertEq(config.rebalancer, rebalancer, "rebalancer");
        assertEq(config.rateLimitAdmin, rateLimitAdmin, "rateLimitAdmin");
    }
}
