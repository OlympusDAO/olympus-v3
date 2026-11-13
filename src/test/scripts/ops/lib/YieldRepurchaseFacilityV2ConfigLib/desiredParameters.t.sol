// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Config} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Config.sol";

import {Kernel} from "src/Kernel.sol";
import {YieldRepurchaseFacilityV2Config} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Config.sol";
import {YieldRepurchaseFacilityV2ConfigTimelock} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2ConfigTimelock.sol";
import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";
import {YieldRepurchaseFacilityV2ConfigLibTest} from "src/test/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib/YieldRepurchaseFacilityV2ConfigLibTest.sol";

contract YieldRepurchaseFacilityV2ConfigLibTests_desiredParameters is
    YieldRepurchaseFacilityV2ConfigLibTest
{
    // ========== HELPERS ========== //

    function _read(
        string memory config_
    ) internal view returns (YieldRepurchaseFacilityV2ConfigLib.DesiredParameters memory) {
        return harness.desiredParameters(_envWithConfig(config_), CHAIN);
    }

    function _withGracePeriod(uint256 value_) internal pure returns (string memory members) {
        return
            _parameterMembers(
                value_,
                STEP_GAS_LIMIT,
                TIMELOCK_DELAY,
                INITIAL_DISCOUNT,
                MAX_PRICE_PREMIUM
            );
    }

    function _withStepGasLimit(uint256 value_) internal pure returns (string memory members) {
        return
            _parameterMembers(
                GRACE_PERIOD,
                value_,
                TIMELOCK_DELAY,
                INITIAL_DISCOUNT,
                MAX_PRICE_PREMIUM
            );
    }

    function _withTimelockDelay(uint256 value_) internal pure returns (string memory members) {
        return
            _parameterMembers(
                GRACE_PERIOD,
                STEP_GAS_LIMIT,
                value_,
                INITIAL_DISCOUNT,
                MAX_PRICE_PREMIUM
            );
    }

    function _withInitialDiscount(uint256 value_) internal pure returns (string memory members) {
        return
            _parameterMembers(
                GRACE_PERIOD,
                STEP_GAS_LIMIT,
                TIMELOCK_DELAY,
                value_,
                MAX_PRICE_PREMIUM
            );
    }

    function _withMaxPricePremium(uint256 value_) internal pure returns (string memory members) {
        return
            _parameterMembers(
                GRACE_PERIOD,
                STEP_GAS_LIMIT,
                TIMELOCK_DELAY,
                INITIAL_DISCOUNT,
                value_
            );
    }

    /// @notice The five scalar members without the one named `omitted_`.
    function _withoutMember(string memory omitted_) internal pure returns (string memory members) {
        string[5] memory names = [
            "gracePeriod",
            "stepGasLimit",
            "timelockDelay",
            "initialDiscount",
            "maxPricePremium"
        ];
        uint256[5] memory values = [
            GRACE_PERIOD,
            STEP_GAS_LIMIT,
            TIMELOCK_DELAY,
            INITIAL_DISCOUNT,
            MAX_PRICE_PREMIUM
        ];
        for (uint256 i = 0; i < names.length; ++i) {
            if (keccak256(bytes(names[i])) == keccak256(bytes(omitted_))) continue;
            members = _join(members, _member(names[i], _quoted(values[i])));
        }
    }

    function _expectRevertGracePeriod(uint256 value_) internal {
        _expectRevertOutOfBound(
            string.concat(CONFIG_PATH, ".gracePeriod"),
            value_,
            string.concat(
                "a grace period is non-zero and below ",
                vm.toString(MAX_GRACE_PERIOD),
                " seconds"
            )
        );
    }

    function _expectRevertStepGasLimit(uint256 value_) internal {
        _expectRevertOutOfBound(
            string.concat(CONFIG_PATH, ".stepGasLimit"),
            value_,
            string.concat(
                "the step gas limit lies within [",
                vm.toString(MIN_STEP_GAS_LIMIT),
                ", ",
                vm.toString(MAX_STEP_GAS_LIMIT),
                "]"
            )
        );
    }

    function _expectRevertTimelockDelay(uint256 value_) internal {
        _expectRevertOutOfBound(
            string.concat(CONFIG_PATH, ".timelockDelay"),
            value_,
            string.concat(
                "the timelock delay lies within [",
                vm.toString(MIN_TIMELOCK_DELAY),
                ", ",
                vm.toString(MAX_TIMELOCK_DELAY),
                "] seconds"
            )
        );
    }

    function _expectRevertInitialDiscount(uint256 value_) internal {
        _expectRevertOutOfBound(
            string.concat(CONFIG_PATH, ".initialDiscount"),
            value_,
            string.concat(
                "the initial discount is below ",
                vm.toString(ONE_HUNDRED_PERCENT),
                " (100%)"
            )
        );
    }

    function _expectRevertMaxPricePremium(uint256 value_) internal {
        _expectRevertOutOfBound(
            string.concat(CONFIG_PATH, ".maxPricePremium"),
            value_,
            string.concat(
                "the max price premium is at most ",
                vm.toString(MAX_PRICE_PREMIUM_LIMIT),
                " (1,000%)"
            )
        );
    }

    // ========== MISSING KEYS ========== //

    // when the config object is empty
    //   [X] it reverts naming the first key
    function test_whenConfigIsEmpty_reverts() public {
        _expectRevertMissingKey(string.concat(CONFIG_PATH, ".gracePeriod"));
        _read("");
    }

    // when the grace period is missing
    //   [X] it reverts naming the key
    function test_whenGracePeriodIsMissing_reverts() public {
        _expectRevertMissingKey(string.concat(CONFIG_PATH, ".gracePeriod"));
        _read(_withoutMember("gracePeriod"));
    }

    // when the step gas limit is missing
    //   [X] it reverts naming the key
    function test_whenStepGasLimitIsMissing_reverts() public {
        _expectRevertMissingKey(string.concat(CONFIG_PATH, ".stepGasLimit"));
        _read(_withoutMember("stepGasLimit"));
    }

    // when the timelock delay is missing
    //   [X] it reverts naming the key
    function test_whenTimelockDelayIsMissing_reverts() public {
        _expectRevertMissingKey(string.concat(CONFIG_PATH, ".timelockDelay"));
        _read(_withoutMember("timelockDelay"));
    }

    // when the initial discount is missing
    //   [X] it reverts naming the key
    function test_whenInitialDiscountIsMissing_reverts() public {
        _expectRevertMissingKey(string.concat(CONFIG_PATH, ".initialDiscount"));
        _read(_withoutMember("initialDiscount"));
    }

    // when the max price premium is missing
    //   [X] it reverts naming the key
    function test_whenMaxPricePremiumIsMissing_reverts() public {
        _expectRevertMissingKey(string.concat(CONFIG_PATH, ".maxPricePremium"));
        _read(_withoutMember("maxPricePremium"));
    }

    // ========== GRACE PERIOD ========== //

    // when the grace period is zero
    //   [X] it reverts naming the key and the bound
    //   [X] the configuration policy rejects the same value
    function test_whenGracePeriodIsZero_reverts() public {
        Kernel kernel = new Kernel();
        vm.label(address(kernel), "Kernel");

        vm.expectRevert(abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector));
        new YieldRepurchaseFacilityV2Config(kernel, 0);

        _expectRevertGracePeriod(0);
        _read(_withGracePeriod(0));
    }

    // when the grace period is the exclusive maximum
    //   [X] it reverts naming the key and the bound
    //   [X] the configuration policy rejects the same value
    function test_whenGracePeriodIsMaximum_reverts() public {
        Kernel kernel = new Kernel();
        vm.label(address(kernel), "Kernel");

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Config
                    .IYieldRepurchaseFacilityV2Config_GracePeriodTooLong
                    .selector
            )
        );
        // casting to 'uint32' is safe because MAX_GRACE_PERIOD is a uint32 constant
        // forge-lint: disable-next-line(unsafe-typecast)
        new YieldRepurchaseFacilityV2Config(kernel, uint32(MAX_GRACE_PERIOD));

        _expectRevertGracePeriod(MAX_GRACE_PERIOD);
        _read(_withGracePeriod(MAX_GRACE_PERIOD));
    }

    // when the grace period is anywhere at or above the exclusive maximum
    //   [X] it reverts naming the key and the bound
    function test_whenGracePeriodIsInInvalidInterval_reverts(uint256 gracePeriod_) public {
        // The invalid interval above zero is [MAX_GRACE_PERIOD, type(uint256).max]: a value
        // that does not fit the uint32 of the contracts is rejected by the bound as well
        uint256 gracePeriod = bound(gracePeriod_, MAX_GRACE_PERIOD, type(uint256).max);

        _expectRevertGracePeriod(gracePeriod);
        _read(_withGracePeriod(gracePeriod));
    }

    // when the grace period is the largest uint256
    //   [X] it reverts naming the key and the bound
    function test_whenGracePeriodIsMaxUint256_reverts() public {
        _expectRevertGracePeriod(type(uint256).max);
        _read(_withGracePeriod(type(uint256).max));
    }

    // when the grace period is one second
    //   [X] it reads the grace period
    //   [X] the configuration policy accepts the same value
    function test_whenGracePeriodIsOne() public {
        Kernel kernel = new Kernel();
        vm.label(address(kernel), "Kernel");
        YieldRepurchaseFacilityV2Config config = new YieldRepurchaseFacilityV2Config(kernel, 1);
        vm.label(address(config), "YieldRepurchaseFacilityV2Config");
        assertEq(config.gracePeriod(), 1, "the configuration policy accepts one second");

        assertEq(_read(_withGracePeriod(1)).gracePeriod, 1, "gracePeriod");
    }

    // when the grace period is one below the exclusive maximum
    //   [X] it reads the grace period
    //   [X] the configuration policy accepts the same value
    function test_whenGracePeriodIsBelowMaximum() public {
        // casting to 'uint32' is safe because MAX_GRACE_PERIOD is a uint32 constant
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 gracePeriod = uint32(MAX_GRACE_PERIOD - 1);
        Kernel kernel = new Kernel();
        vm.label(address(kernel), "Kernel");
        YieldRepurchaseFacilityV2Config config = new YieldRepurchaseFacilityV2Config(
            kernel,
            gracePeriod
        );
        vm.label(address(config), "YieldRepurchaseFacilityV2Config");
        assertEq(
            config.gracePeriod(),
            gracePeriod,
            "the configuration policy accepts the value below the maximum"
        );

        assertEq(_read(_withGracePeriod(gracePeriod)).gracePeriod, gracePeriod, "gracePeriod");
    }

    // when the grace period is anywhere inside the bound
    //   [X] it reads the grace period
    function test_whenGracePeriodIsInValidInterval(uint256 gracePeriod_) public view {
        // The valid interval is [1, MAX_GRACE_PERIOD - 1]
        uint256 gracePeriod = bound(gracePeriod_, 1, MAX_GRACE_PERIOD - 1);

        assertEq(_read(_withGracePeriod(gracePeriod)).gracePeriod, gracePeriod, "gracePeriod");
    }

    // ========== STEP GAS LIMIT ========== //

    // when the step gas limit is zero
    //   [X] it reverts naming the key and the bound
    function test_whenStepGasLimitIsZero_reverts() public {
        _expectRevertStepGasLimit(0);
        _read(_withStepGasLimit(0));
    }

    // when the step gas limit is one below the minimum
    //   [X] it reverts naming the key and the bound
    function test_whenStepGasLimitIsBelowMinimum_reverts() public {
        _expectRevertStepGasLimit(MIN_STEP_GAS_LIMIT - 1);
        _read(_withStepGasLimit(MIN_STEP_GAS_LIMIT - 1));
    }

    // when the step gas limit is anywhere below the minimum
    //   [X] it reverts naming the key and the bound
    function test_whenStepGasLimitIsInLowerInvalidInterval_reverts(uint256 stepGasLimit_) public {
        // The lower invalid interval is [0, MIN_STEP_GAS_LIMIT - 1]
        uint256 stepGasLimit = bound(stepGasLimit_, 0, MIN_STEP_GAS_LIMIT - 1);

        _expectRevertStepGasLimit(stepGasLimit);
        _read(_withStepGasLimit(stepGasLimit));
    }

    // when the step gas limit is one above the maximum
    //   [X] it reverts naming the key and the bound
    function test_whenStepGasLimitIsAboveMaximum_reverts() public {
        _expectRevertStepGasLimit(MAX_STEP_GAS_LIMIT + 1);
        _read(_withStepGasLimit(MAX_STEP_GAS_LIMIT + 1));
    }

    // when the step gas limit is anywhere above the maximum
    //   [X] it reverts naming the key and the bound
    function test_whenStepGasLimitIsInUpperInvalidInterval_reverts(uint256 stepGasLimit_) public {
        // The upper invalid interval is [MAX_STEP_GAS_LIMIT + 1, type(uint256).max]: a value
        // that does not fit the uint32 of the facility is rejected by the bound as well
        uint256 stepGasLimit = bound(stepGasLimit_, MAX_STEP_GAS_LIMIT + 1, type(uint256).max);

        _expectRevertStepGasLimit(stepGasLimit);
        _read(_withStepGasLimit(stepGasLimit));
    }

    // when the step gas limit is the largest uint256
    //   [X] it reverts naming the key and the bound
    function test_whenStepGasLimitIsMaxUint256_reverts() public {
        _expectRevertStepGasLimit(type(uint256).max);
        _read(_withStepGasLimit(type(uint256).max));
    }

    // when the step gas limit is the minimum
    //   [X] it reads the step gas limit
    function test_whenStepGasLimitIsMinimum() public view {
        assertEq(
            _read(_withStepGasLimit(MIN_STEP_GAS_LIMIT)).stepGasLimit,
            MIN_STEP_GAS_LIMIT,
            "stepGasLimit"
        );
    }

    // when the step gas limit is the maximum
    //   [X] it reads the step gas limit
    function test_whenStepGasLimitIsMaximum() public view {
        assertEq(
            _read(_withStepGasLimit(MAX_STEP_GAS_LIMIT)).stepGasLimit,
            MAX_STEP_GAS_LIMIT,
            "stepGasLimit"
        );
    }

    // when the step gas limit is anywhere inside the bound
    //   [X] it reads the step gas limit
    function test_whenStepGasLimitIsInValidInterval(uint256 stepGasLimit_) public view {
        // The valid interval is [MIN_STEP_GAS_LIMIT, MAX_STEP_GAS_LIMIT]
        uint256 stepGasLimit = bound(stepGasLimit_, MIN_STEP_GAS_LIMIT, MAX_STEP_GAS_LIMIT);

        assertEq(
            _read(_withStepGasLimit(stepGasLimit)).stepGasLimit,
            stepGasLimit,
            "stepGasLimit"
        );
    }

    // ========== TIMELOCK DELAY ========== //

    // given a deployed config timelock
    //   [X] its delay bound equals the bound the library declares
    function test_givenConfigTimelock() public {
        Kernel kernel = new Kernel();
        vm.label(address(kernel), "Kernel");
        // casting to 'uint32' is safe because GRACE_PERIOD is 432000
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 gracePeriod = uint32(GRACE_PERIOD);
        YieldRepurchaseFacilityV2Config config = new YieldRepurchaseFacilityV2Config(
            kernel,
            gracePeriod
        );
        vm.label(address(config), "YieldRepurchaseFacilityV2Config");
        YieldRepurchaseFacilityV2ConfigTimelock timelock = new YieldRepurchaseFacilityV2ConfigTimelock(
                kernel,
                address(config),
                1 days,
                gracePeriod
            );
        vm.label(address(timelock), "YieldRepurchaseFacilityV2ConfigTimelock");

        assertEq(timelock.MIN_TIMELOCK_DELAY(), MIN_TIMELOCK_DELAY, "MIN_TIMELOCK_DELAY");
        assertEq(timelock.MAX_TIMELOCK_DELAY(), MAX_TIMELOCK_DELAY, "MAX_TIMELOCK_DELAY");
    }

    // when the timelock delay is zero
    //   [X] it reverts naming the key and the bound
    function test_whenTimelockDelayIsZero_reverts() public {
        _expectRevertTimelockDelay(0);
        _read(_withTimelockDelay(0));
    }

    // when the timelock delay is one below the minimum
    //   [X] it reverts naming the key and the bound
    function test_whenTimelockDelayIsBelowMinimum_reverts() public {
        _expectRevertTimelockDelay(MIN_TIMELOCK_DELAY - 1);
        _read(_withTimelockDelay(MIN_TIMELOCK_DELAY - 1));
    }

    // when the timelock delay is anywhere below the minimum
    //   [X] it reverts naming the key and the bound
    function test_whenTimelockDelayIsInLowerInvalidInterval_reverts(
        uint256 timelockDelay_
    ) public {
        // The lower invalid interval is [0, MIN_TIMELOCK_DELAY - 1]
        uint256 timelockDelay = bound(timelockDelay_, 0, MIN_TIMELOCK_DELAY - 1);

        _expectRevertTimelockDelay(timelockDelay);
        _read(_withTimelockDelay(timelockDelay));
    }

    // when the timelock delay is one above the maximum
    //   [X] it reverts naming the key and the bound
    function test_whenTimelockDelayIsAboveMaximum_reverts() public {
        _expectRevertTimelockDelay(MAX_TIMELOCK_DELAY + 1);
        _read(_withTimelockDelay(MAX_TIMELOCK_DELAY + 1));
    }

    // when the timelock delay is anywhere above the maximum
    //   [X] it reverts naming the key and the bound
    function test_whenTimelockDelayIsInUpperInvalidInterval_reverts(
        uint256 timelockDelay_
    ) public {
        // The upper invalid interval is [MAX_TIMELOCK_DELAY + 1, type(uint256).max]: a value
        // that does not fit the uint48 of the timelock is rejected by the bound as well
        uint256 timelockDelay = bound(timelockDelay_, MAX_TIMELOCK_DELAY + 1, type(uint256).max);

        _expectRevertTimelockDelay(timelockDelay);
        _read(_withTimelockDelay(timelockDelay));
    }

    // when the timelock delay is the largest uint256
    //   [X] it reverts naming the key and the bound
    function test_whenTimelockDelayIsMaxUint256_reverts() public {
        _expectRevertTimelockDelay(type(uint256).max);
        _read(_withTimelockDelay(type(uint256).max));
    }

    // when the timelock delay is the minimum
    //   [X] it reads the timelock delay
    function test_whenTimelockDelayIsMinimum() public view {
        assertEq(
            _read(_withTimelockDelay(MIN_TIMELOCK_DELAY)).timelockDelay,
            MIN_TIMELOCK_DELAY,
            "timelockDelay"
        );
    }

    // when the timelock delay is the maximum
    //   [X] it reads the timelock delay
    function test_whenTimelockDelayIsMaximum() public view {
        assertEq(
            _read(_withTimelockDelay(MAX_TIMELOCK_DELAY)).timelockDelay,
            MAX_TIMELOCK_DELAY,
            "timelockDelay"
        );
    }

    // when the timelock delay is anywhere inside the bound
    //   [X] it reads the timelock delay
    function test_whenTimelockDelayIsInValidInterval(uint256 timelockDelay_) public view {
        // The valid interval is [MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]
        uint256 timelockDelay = bound(timelockDelay_, MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY);

        assertEq(
            _read(_withTimelockDelay(timelockDelay)).timelockDelay,
            timelockDelay,
            "timelockDelay"
        );
    }

    // ========== INITIAL DISCOUNT ========== //

    // when the initial discount is 100%
    //   [X] it reverts naming the key and the bound
    //   [X] the facility rule rejects the same value
    function test_whenInitialDiscountIsOneHundredPercent_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_InitialDiscountTooHigh
                    .selector
            )
        );
        validation.requireValidInitialDiscount(ONE_HUNDRED_PERCENT);

        _expectRevertInitialDiscount(ONE_HUNDRED_PERCENT);
        _read(_withInitialDiscount(ONE_HUNDRED_PERCENT));
    }

    // when the initial discount is anywhere at or above 100%
    //   [X] it reverts naming the key and the bound
    //   [X] the facility rule rejects the same value
    function test_whenInitialDiscountIsInInvalidInterval_reverts(uint256 initialDiscount_) public {
        // The invalid interval is [ONE_HUNDRED_PERCENT, type(uint256).max]
        uint256 initialDiscount = bound(initialDiscount_, ONE_HUNDRED_PERCENT, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_InitialDiscountTooHigh
                    .selector
            )
        );
        validation.requireValidInitialDiscount(initialDiscount);

        _expectRevertInitialDiscount(initialDiscount);
        _read(_withInitialDiscount(initialDiscount));
    }

    // when the initial discount is the largest uint256
    //   [X] it reverts naming the key and the bound
    function test_whenInitialDiscountIsMaxUint256_reverts() public {
        _expectRevertInitialDiscount(type(uint256).max);
        _read(_withInitialDiscount(type(uint256).max));
    }

    // when the initial discount is zero
    //   [X] it reads the initial discount
    function test_whenInitialDiscountIsZero() public view {
        assertEq(_read(_withInitialDiscount(0)).initialDiscount, 0, "initialDiscount");
    }

    // when the initial discount is one below 100%
    //   [X] it reads the initial discount
    //   [X] the facility rule accepts the same value
    function test_whenInitialDiscountIsBelowOneHundredPercent() public view {
        validation.requireValidInitialDiscount(ONE_HUNDRED_PERCENT - 1);

        assertEq(
            _read(_withInitialDiscount(ONE_HUNDRED_PERCENT - 1)).initialDiscount,
            ONE_HUNDRED_PERCENT - 1,
            "initialDiscount"
        );
    }

    // when the initial discount is anywhere below 100%
    //   [X] it reads the initial discount
    //   [X] the facility rule accepts the same value
    function test_whenInitialDiscountIsInValidInterval(uint256 initialDiscount_) public view {
        // The valid interval is [0, ONE_HUNDRED_PERCENT - 1]
        uint256 initialDiscount = bound(initialDiscount_, 0, ONE_HUNDRED_PERCENT - 1);

        validation.requireValidInitialDiscount(initialDiscount);

        assertEq(
            _read(_withInitialDiscount(initialDiscount)).initialDiscount,
            initialDiscount,
            "initialDiscount"
        );
    }

    // ========== MAX PRICE PREMIUM ========== //

    // when the max price premium is one above the limit
    //   [X] it reverts naming the key and the bound
    //   [X] the facility rule rejects the same value
    function test_whenMaxPricePremiumIsAboveLimit_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh
                    .selector
            )
        );
        validation.requireValidMaxPricePremium(MAX_PRICE_PREMIUM_LIMIT + 1);

        _expectRevertMaxPricePremium(MAX_PRICE_PREMIUM_LIMIT + 1);
        _read(_withMaxPricePremium(MAX_PRICE_PREMIUM_LIMIT + 1));
    }

    // when the max price premium is anywhere above the limit
    //   [X] it reverts naming the key and the bound
    //   [X] the facility rule rejects the same value
    function test_whenMaxPricePremiumIsInInvalidInterval_reverts(uint256 maxPricePremium_) public {
        // The invalid interval is [MAX_PRICE_PREMIUM_LIMIT + 1, type(uint256).max]
        uint256 maxPricePremium = bound(
            maxPricePremium_,
            MAX_PRICE_PREMIUM_LIMIT + 1,
            type(uint256).max
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh
                    .selector
            )
        );
        validation.requireValidMaxPricePremium(maxPricePremium);

        _expectRevertMaxPricePremium(maxPricePremium);
        _read(_withMaxPricePremium(maxPricePremium));
    }

    // when the max price premium is the largest uint256
    //   [X] it reverts naming the key and the bound
    function test_whenMaxPricePremiumIsMaxUint256_reverts() public {
        _expectRevertMaxPricePremium(type(uint256).max);
        _read(_withMaxPricePremium(type(uint256).max));
    }

    // when the max price premium is zero
    //   [X] it reads the max price premium
    function test_whenMaxPricePremiumIsZero() public view {
        assertEq(_read(_withMaxPricePremium(0)).maxPricePremium, 0, "maxPricePremium");
    }

    // when the max price premium is the limit
    //   [X] it reads the max price premium
    //   [X] the facility rule accepts the same value
    function test_whenMaxPricePremiumIsLimit() public view {
        validation.requireValidMaxPricePremium(MAX_PRICE_PREMIUM_LIMIT);

        assertEq(
            _read(_withMaxPricePremium(MAX_PRICE_PREMIUM_LIMIT)).maxPricePremium,
            MAX_PRICE_PREMIUM_LIMIT,
            "maxPricePremium"
        );
    }

    // when the max price premium is anywhere up to the limit
    //   [X] it reads the max price premium
    //   [X] the facility rule accepts the same value
    function test_whenMaxPricePremiumIsInValidInterval(uint256 maxPricePremium_) public view {
        // The valid interval is [0, MAX_PRICE_PREMIUM_LIMIT]
        uint256 maxPricePremium = bound(maxPricePremium_, 0, MAX_PRICE_PREMIUM_LIMIT);

        validation.requireValidMaxPricePremium(maxPricePremium);

        assertEq(
            _read(_withMaxPricePremium(maxPricePremium)).maxPricePremium,
            maxPricePremium,
            "maxPricePremium"
        );
    }

    // ========== ALL PARAMETERS ========== //

    // when every parameter is valid and written as a JSON string
    //   [X] it reads every parameter
    function test_whenValuesAreJsonStrings() public view {
        YieldRepurchaseFacilityV2ConfigLib.DesiredParameters memory parameters = _read(
            _validParameterMembers()
        );

        assertEq(parameters.gracePeriod, GRACE_PERIOD, "gracePeriod");
        assertEq(parameters.stepGasLimit, STEP_GAS_LIMIT, "stepGasLimit");
        assertEq(parameters.timelockDelay, TIMELOCK_DELAY, "timelockDelay");
        assertEq(parameters.initialDiscount, INITIAL_DISCOUNT, "initialDiscount");
        assertEq(parameters.maxPricePremium, MAX_PRICE_PREMIUM, "maxPricePremium");
    }

    // when the periods and the gas limit are written as JSON numbers
    //   [X] it reads every parameter
    function test_whenValuesAreJsonNumbers() public view {
        string memory members = _member("gracePeriod", vm.toString(GRACE_PERIOD));
        members = _join(members, _member("stepGasLimit", vm.toString(STEP_GAS_LIMIT)));
        members = _join(members, _member("timelockDelay", vm.toString(TIMELOCK_DELAY)));
        members = _join(members, _member("initialDiscount", _quoted(INITIAL_DISCOUNT)));
        members = _join(members, _member("maxPricePremium", _quoted(MAX_PRICE_PREMIUM)));

        YieldRepurchaseFacilityV2ConfigLib.DesiredParameters memory parameters = _read(members);

        assertEq(parameters.gracePeriod, GRACE_PERIOD, "gracePeriod");
        assertEq(parameters.stepGasLimit, STEP_GAS_LIMIT, "stepGasLimit");
        assertEq(parameters.timelockDelay, TIMELOCK_DELAY, "timelockDelay");
        assertEq(parameters.initialDiscount, INITIAL_DISCOUNT, "initialDiscount");
        assertEq(parameters.maxPricePremium, MAX_PRICE_PREMIUM, "maxPricePremium");
    }
}
