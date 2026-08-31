// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";
import {ICCIPBridgeConfigTimelock} from "src/policies/interfaces/bridge/ICCIPBridgeConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {Kernel, Policy} from "src/Kernel.sol";
import {CCIPBridgeConfig} from "src/policies/bridge/CCIPBridgeConfig.sol";
import {CCIPBridgeConfigTimelock} from "src/policies/bridge/CCIPBridgeConfigTimelock.sol";
import {MockInterfaceSet} from "src/test/policies/bridge/mocks/MockInterfaceSet.sol";

import {CCIPBridgeConfigTimelockTest} from "./CCIPBridgeConfigTimelockTest.sol";

contract CCIPBridgeConfigTimelockTests_constructor is CCIPBridgeConfigTimelockTest {
    // when the grace period is zero
    //   [X] it reverts with GracePeriod_ZeroPeriod
    function test_whenGracePeriodIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector));
        new CCIPBridgeConfigTimelock(kernel, address(config), TIMELOCK_DELAY, 0);
    }

    // when the grace period is zero
    //   when the delay is below the minimum
    //     [X] it reverts with GracePeriod_ZeroPeriod
    // Pins the base constructor order: the grace check of ReEnablerGracePeriod runs before the
    // delay check of TimelockBatchQueue.
    function test_whenGracePeriodIsZero_whenDelayIsBelowMinimum_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector));
        new CCIPBridgeConfigTimelock(kernel, address(config), 1 days - 1, 0);
    }

    // when the delay is one second below the minimum
    //   [X] it reverts with ITimelockBatchQueue_TimelockDelayInvalid carrying the delay and
    //       both bounds
    // The lower comparison is strict, so 1 days - 1 is the failing side of the boundary
    function test_whenDelayIsBelowMinimum_reverts() public {
        _expectRevertTimelockDelayInvalid(1 days - 1);
        new CCIPBridgeConfigTimelock(kernel, address(config), 1 days - 1, GRACE_PERIOD);
    }

    // when the delay is one second above the maximum
    //   [X] it reverts with ITimelockBatchQueue_TimelockDelayInvalid carrying the delay and
    //       both bounds
    // The upper comparison is strict, so 30 days + 1 is the failing side of the boundary
    function test_whenDelayIsAboveMaximum_reverts() public {
        _expectRevertTimelockDelayInvalid(30 days + 1);
        new CCIPBridgeConfigTimelock(kernel, address(config), 30 days + 1, GRACE_PERIOD);
    }

    // when the delay is the uint48 maximum
    //   [X] it reverts with ITimelockBatchQueue_TimelockDelayInvalid
    // The maximum representable value case for the numeric input
    function test_whenDelayIsUint48Max_reverts() public {
        _expectRevertTimelockDelayInvalid(type(uint48).max);
        new CCIPBridgeConfigTimelock(kernel, address(config), type(uint48).max, GRACE_PERIOD);
    }

    // when the delay is below the minimum
    //   when the config is the zero address
    //     [X] it reverts with ITimelockBatchQueue_TimelockDelayInvalid
    // Pins that the base constructors run before the body checks: the delay check answers
    // before the config zero check.
    function test_whenDelayIsBelowMinimum_whenConfigIsZeroAddress_reverts() public {
        _expectRevertTimelockDelayInvalid(1 days - 1);
        new CCIPBridgeConfigTimelock(kernel, address(0), 1 days - 1, GRACE_PERIOD);
    }

    // when the config is the zero address
    //   [X] it reverts with CCIPBridgeConfigTimelock_InvalidAddress("config")
    // Pins the error identity: the dedicated zero check answers before the ERC165 probe, which
    // would also read the zero address as an invalid config.
    function test_whenConfigIsZeroAddress_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPBridgeConfigTimelock.CCIPBridgeConfigTimelock_InvalidAddress.selector,
                "config"
            )
        );
        new CCIPBridgeConfigTimelock(kernel, address(0), TIMELOCK_DELAY, GRACE_PERIOD);
    }

    // when the config candidate holds no code
    //   [X] it reverts with CCIPBridgeConfigTimelock_InvalidConfig
    // The ERC165 probe staticcall against an EOA returns no data and reads as false. Also pins
    // the load-bearing guard order: the probe answers before the kernel() call, which would
    // revert raw on a codeless candidate.
    function test_whenConfigHasNoCode_reverts() public {
        address candidate = makeAddr("eoaConfigCandidate");

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPBridgeConfigTimelock.CCIPBridgeConfigTimelock_InvalidConfig.selector,
                candidate
            )
        );
        new CCIPBridgeConfigTimelock(kernel, candidate, TIMELOCK_DELAY, GRACE_PERIOD);
    }

    // when the config candidate is a contract without supportsInterface
    //   [X] it reverts with CCIPBridgeConfigTimelock_InvalidConfig
    // The probe call reverts inside the candidate and reads as false; MockOhm is the candidate
    function test_whenConfigDoesNotImplementERC165_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPBridgeConfigTimelock.CCIPBridgeConfigTimelock_InvalidConfig.selector,
                address(ohm)
            )
        );
        new CCIPBridgeConfigTimelock(kernel, address(ohm), TIMELOCK_DELAY, GRACE_PERIOD);
    }

    // when the config candidate answers ERC165 but does not advertise ICCIPBridgeConfig
    //   [X] it reverts with CCIPBridgeConfigTimelock_InvalidConfig
    // Requires the MockInterfaceSet mock advertising only IConfigOperator and IEnabler
    function test_whenConfigDoesNotAdvertiseBridgeConfigInterface_reverts() public {
        bytes4[] memory advertised = new bytes4[](2);
        advertised[0] = type(IConfigOperator).interfaceId;
        advertised[1] = type(IEnabler).interfaceId;
        MockInterfaceSet candidate = new MockInterfaceSet(advertised);
        vm.label(address(candidate), "noBridgeConfigCandidate");

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPBridgeConfigTimelock.CCIPBridgeConfigTimelock_InvalidConfig.selector,
                address(candidate)
            )
        );
        new CCIPBridgeConfigTimelock(kernel, address(candidate), TIMELOCK_DELAY, GRACE_PERIOD);
    }

    // when the config candidate answers ERC165 but does not advertise IConfigOperator
    //   [X] it reverts with CCIPBridgeConfigTimelock_InvalidConfig
    // Requires the MockInterfaceSet mock advertising only ICCIPBridgeConfig and IEnabler
    function test_whenConfigDoesNotAdvertiseConfigOperatorInterface_reverts() public {
        bytes4[] memory advertised = new bytes4[](2);
        advertised[0] = type(ICCIPBridgeConfig).interfaceId;
        advertised[1] = type(IEnabler).interfaceId;
        MockInterfaceSet candidate = new MockInterfaceSet(advertised);
        vm.label(address(candidate), "noConfigOperatorCandidate");

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPBridgeConfigTimelock.CCIPBridgeConfigTimelock_InvalidConfig.selector,
                address(candidate)
            )
        );
        new CCIPBridgeConfigTimelock(kernel, address(candidate), TIMELOCK_DELAY, GRACE_PERIOD);
    }

    // when the config candidate answers ERC165 but does not advertise IEnabler
    //   [X] it reverts with CCIPBridgeConfigTimelock_InvalidConfig
    // Requires the MockInterfaceSet mock advertising only ICCIPBridgeConfig and IConfigOperator
    function test_whenConfigDoesNotAdvertiseEnablerInterface_reverts() public {
        bytes4[] memory advertised = new bytes4[](2);
        advertised[0] = type(ICCIPBridgeConfig).interfaceId;
        advertised[1] = type(IConfigOperator).interfaceId;
        MockInterfaceSet candidate = new MockInterfaceSet(advertised);
        vm.label(address(candidate), "noEnablerCandidate");

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPBridgeConfigTimelock.CCIPBridgeConfigTimelock_InvalidConfig.selector,
                address(candidate)
            )
        );
        new CCIPBridgeConfigTimelock(kernel, address(candidate), TIMELOCK_DELAY, GRACE_PERIOD);
    }

    // given the config candidate reports a kernel other than the constructor kernel
    //   [X] it reverts with CCIPBridgeConfigTimelock_KernelMismatch carrying the foreign kernel
    // Requires a real config deployed against a second kernel over the primary pool
    function test_givenConfigReportsDifferentKernel_reverts() public {
        (Kernel foreignKernel, CCIPBridgeConfig foreignConfig, ) = _deployStackOnForeignKernel();

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPBridgeConfigTimelock.CCIPBridgeConfigTimelock_KernelMismatch.selector,
                address(foreignKernel)
            )
        );
        new CCIPBridgeConfigTimelock(kernel, address(foreignConfig), TIMELOCK_DELAY, GRACE_PERIOD);
    }

    // when the parameters are valid
    //   [X] it emits GracePeriodSet with the constructor argument
    //   [X] it emits TimelockDelaySet with the constructor argument
    //   [X] it reports the config address through config()
    //   [X] it reports timelockDelay() as the constructor argument
    //   [X] it reports gracePeriod() as the constructor argument
    //   [X] it reports isEnabled() false
    //   [X] it reports lastTransitionAt() zero
    //   [X] it reports nextActionId() as one
    //   [X] it reports the kernel address through kernel()
    //   [X] it reports ROLES() as the zero address before activation
    //   [X] it reports isActive() false before activation
    //   [X] it reports MIN_TIMELOCK_DELAY as 1 days, MAX_TIMELOCK_DELAY as 30 days and
    //       EXECUTION_WINDOW as 3 days
    // The full initial-state assertion, covering the unset fields next to the set ones. Both
    // events come from base constructors, so they are captured with vm.recordLogs rather than
    // vm.expectEmit. The nextActionId() == 1 assertion pins the free-key sentinel: action id
    // zero must stay unreachable because pendingActionId reports zero for a free key.
    function test_whenParametersAreValid() public {
        vm.recordLogs();
        CCIPBridgeConfigTimelock freshTimelock = _newTimelock(
            address(config),
            TIMELOCK_DELAY,
            GRACE_PERIOD
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 gracePeriodSetCount;
        uint256 timelockDelaySetCount;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(freshTimelock)) continue;
            if (logs[i].topics[0] == IGracePeriod.GracePeriodSet.selector) {
                ++gracePeriodSetCount;
                assertEq(
                    abi.decode(logs[i].data, (uint32)),
                    GRACE_PERIOD,
                    "GracePeriodSet should carry the constructor argument"
                );
            } else if (logs[i].topics[0] == ITimelockBatchQueue.TimelockDelaySet.selector) {
                ++timelockDelaySetCount;
                assertEq(
                    abi.decode(logs[i].data, (uint48)),
                    TIMELOCK_DELAY,
                    "TimelockDelaySet should carry the constructor argument"
                );
            }
        }
        assertEq(gracePeriodSetCount, 1, "exactly one GracePeriodSet should be emitted");
        assertEq(timelockDelaySetCount, 1, "exactly one TimelockDelaySet should be emitted");

        assertEq(
            freshTimelock.config(),
            address(config),
            "config() should report the constructor config"
        );
        assertEq(
            freshTimelock.timelockDelay(),
            TIMELOCK_DELAY,
            "timelockDelay() should report the constructor argument"
        );
        assertEq(
            freshTimelock.gracePeriod(),
            GRACE_PERIOD,
            "gracePeriod() should report the constructor argument"
        );
        assertFalse(freshTimelock.isEnabled(), "the policy should start disabled");
        assertEq(freshTimelock.lastTransitionAt(), 0, "lastTransitionAt should start at zero");
        assertEq(
            freshTimelock.nextActionId(),
            1,
            "nextActionId should start at one, keeping id zero as the free-key sentinel"
        );
        assertEq(
            address(freshTimelock.kernel()),
            address(kernel),
            "kernel() should report the constructor kernel"
        );
        assertEq(
            address(freshTimelock.ROLES()),
            address(0),
            "ROLES should be unset before activation"
        );
        assertFalse(freshTimelock.isActive(), "the policy should not be active before activation");
        assertEq(freshTimelock.MIN_TIMELOCK_DELAY(), 1 days, "MIN_TIMELOCK_DELAY should be 1 day");
        assertEq(
            freshTimelock.MAX_TIMELOCK_DELAY(),
            30 days,
            "MAX_TIMELOCK_DELAY should be 30 days"
        );
        assertEq(freshTimelock.EXECUTION_WINDOW(), 3 days, "EXECUTION_WINDOW should be 3 days");
    }

    // when the delay equals the minimum
    //   [X] it constructs and reports timelockDelay() as 1 days
    // The lower comparison is strict, so the bound itself is accepted
    function test_whenDelayIsMinimum() public {
        CCIPBridgeConfigTimelock freshTimelock = _newTimelock(
            address(config),
            1 days,
            GRACE_PERIOD
        );
        assertEq(freshTimelock.timelockDelay(), 1 days, "timelockDelay() should be the minimum");
    }

    // when the delay equals the maximum
    //   [X] it constructs and reports timelockDelay() as 30 days
    // The upper comparison is strict, so the bound itself is accepted
    function test_whenDelayIsMaximum() public {
        CCIPBridgeConfigTimelock freshTimelock = _newTimelock(
            address(config),
            30 days,
            GRACE_PERIOD
        );
        assertEq(freshTimelock.timelockDelay(), 30 days, "timelockDelay() should be the maximum");
    }

    // when the delay is any value within the bounds
    //   [X] it constructs and reports timelockDelay() equal to the argument
    // Fuzzed over the valid interval [1 days, 30 days]
    function test_whenDelayIsWithinBounds(uint48 delay_) public {
        uint48 boundedDelay = uint48(bound(delay_, 1 days, 30 days));
        // boundedDelay is in the valid interval [1 days, 30 days]

        CCIPBridgeConfigTimelock freshTimelock = _newTimelock(
            address(config),
            boundedDelay,
            GRACE_PERIOD
        );
        assertEq(
            freshTimelock.timelockDelay(),
            boundedDelay,
            "timelockDelay() should equal the constructor argument"
        );
    }

    // when the grace period is one second
    //   [X] it constructs and reports gracePeriod() as one
    // The zero check is an equality, so one is the smallest accepted window
    function test_whenGracePeriodIsOne() public {
        CCIPBridgeConfigTimelock freshTimelock = _newTimelock(address(config), TIMELOCK_DELAY, 1);
        assertEq(freshTimelock.gracePeriod(), 1, "gracePeriod() should be one");
    }

    // when the grace period is the uint32 maximum
    //   [X] it constructs and reports gracePeriod() as type(uint32).max
    function test_whenGracePeriodIsMax() public {
        CCIPBridgeConfigTimelock freshTimelock = _newTimelock(
            address(config),
            TIMELOCK_DELAY,
            type(uint32).max
        );
        assertEq(
            freshTimelock.gracePeriod(),
            type(uint32).max,
            "gracePeriod() should be the uint32 maximum"
        );
    }

    // given the config candidate is not an active policy of the kernel and is disabled
    //   [X] it constructs successfully
    // Construction validates interfaces and kernel only; activity is checked at enable
    // (ConfigNotActive) and enablement at queue time. Pins the lifecycle deferral.
    function test_givenConfigIsInactiveAndDisabled() public {
        // The stack helper constructs the timelock over the fresh config while that config is
        // unactivated and disabled, so the deploy itself is the lifecycle-deferral pin
        (
            CCIPBridgeConfig freshConfig,
            CCIPBridgeConfigTimelock freshTimelock
        ) = _deployStackOnKernel(kernel);

        assertFalse(
            kernel.isPolicyActive(Policy(address(freshConfig))),
            "the fresh config should not be an active kernel policy"
        );
        assertFalse(freshConfig.isEnabled(), "the fresh config should be disabled");
        assertEq(
            freshTimelock.config(),
            address(freshConfig),
            "the timelock should bind the inactive, disabled config"
        );
    }

    // when the kernel is the zero address
    //   given the config candidate also reports the zero kernel
    //     [X] it constructs successfully
    // The kernel check is an equality with no zero or code check; requires a config instance
    // deployed against Kernel(address(0)). Pins the absent guard as documented behavior.
    function test_whenKernelIsZeroAddress_givenConfigKernelIsZero() public {
        CCIPBridgeConfig zeroKernelConfig = new CCIPBridgeConfig(
            Kernel(address(0)),
            address(pool),
            GRACE_PERIOD
        );
        vm.label(address(zeroKernelConfig), "zeroKernelConfig");

        CCIPBridgeConfigTimelock zeroKernelTimelock = new CCIPBridgeConfigTimelock(
            Kernel(address(0)),
            address(zeroKernelConfig),
            TIMELOCK_DELAY,
            GRACE_PERIOD
        );
        vm.label(address(zeroKernelTimelock), "zeroKernelTimelock");

        assertEq(
            address(zeroKernelTimelock.kernel()),
            address(0),
            "kernel() should report the zero kernel"
        );
        assertEq(
            zeroKernelTimelock.config(),
            address(zeroKernelConfig),
            "config() should report the zero-kernel config"
        );
    }

    // given a timelock already exists for the config
    //   [X] it constructs a second timelock over the same config successfully
    // Construction claims nothing on the config; the single-step operator seat decides later
    // which timelock is live
    function test_givenTimelockAlreadyExistsForConfig() public {
        // The primary timelock from setUp already exists over the config and holds the seat
        CCIPBridgeConfigTimelock secondTimelock = _newTimelock(
            address(config),
            TIMELOCK_DELAY,
            GRACE_PERIOD
        );

        assertEq(
            secondTimelock.config(),
            address(config),
            "the second timelock should bind the same config"
        );
        assertEq(
            config.configOperator(),
            address(timelock),
            "the operator seat should still name the primary timelock"
        );
    }
}
