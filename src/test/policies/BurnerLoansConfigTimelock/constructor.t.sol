// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansConfigTimelock.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansConfigTimelock} from "src/policies/burnerloans/BurnerLoansConfigTimelock.sol";

contract BurnerLoansConfigTimelockConstructorTest is BurnerLoansConfigTimelockTest {
    error CoreDependencyReadFailed();
    bytes internal constant _MALFORMED_CORE_RESPONSE = hex"01";

    // Scenarios: BLCT-CONSTRUCTOR-D01.
    function test_givenMissingIBurnerLoansConfig_whenConstructed_reverts(address deployer_) public {
        vm.mockCall(
            address(_config),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansConfig).interfaceId
            ),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(_config)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-D02.
    function test_givenMissingIEnabler_whenConstructed_reverts(address deployer_) public {
        vm.mockCall(
            address(_config),
            abi.encodeWithSignature("supportsInterface(bytes4)", type(IEnabler).interfaceId),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(_config)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-I03.
    function test_givenMissingIConfigOperator_whenConstructed_reverts(address deployer_) public {
        vm.mockCall(
            address(_config),
            abi.encodeWithSignature("supportsInterface(bytes4)", type(IConfigOperator).interfaceId),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(_config)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-I01.
    function test_givenZeroConfig_whenConstructed_reverts(address deployer_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(0)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, IBurnerLoansConfig(address(0)));
    }

    // Scenarios: BLCT-CONSTRUCTOR-I02.
    function test_givenEoaConfig_whenConstructed_reverts(
        address deployer_,
        address candidate_
    ) public {
        vm.assume(candidate_.code.length == 0 && candidate_ != address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                candidate_
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, IBurnerLoansConfig(candidate_));
    }

    // Scenarios: BLCT-CONSTRUCTOR-I04.
    function test_givenInterfaceProbeReverts_whenConstructed_reverts(address deployer_) public {
        vm.mockCallRevert(
            address(_config),
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            hex"deadbeef"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(_config)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, IBurnerLoansConfig(address(_config)));
    }

    // Scenarios: BLCT-CONSTRUCTOR-I05.
    function test_givenMalformedInterfaceProbe_whenConstructed_reverts(address deployer_) public {
        vm.mockCall(
            address(_config),
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            hex"01"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(_config)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, IBurnerLoansConfig(address(_config)));
    }

    // Scenarios: BLCT-CONSTRUCTOR-D03.
    function test_givenForeignConfigKernel_whenConstructed_reverts(address deployer_) public {
        Kernel other = new Kernel();
        vm.mockCall(
            address(_config),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(other))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_config),
                address(_kernel),
                address(other)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-P01.
    function test_givenKernelGetterReverts_whenConstructed_reverts(address deployer_) public {
        vm.mockCallRevert(address(_config), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_config)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-P02.
    function test_givenConfigActiveTrue_givenConfigEnabledTrue_whenConstructed_thenDisabledDefaults(
        address deployer_
    ) public {
        _setState(_config, true, true);
        vm.prank(deployer_);
        BurnerLoansConfigTimelock fresh = new BurnerLoansConfigTimelock(_kernel, _config);
        assertEq(address(fresh.kernel()), address(_kernel), "Immutable Kernel");
        assertEq(address(fresh.burnerLoans()), address(_config), "Immutable Config");
        assertFalse(fresh.isEnabled(), "Starts disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Never enabled");
        assertEq(fresh.gracePeriod(), 7 days, "Default grace");
        assertEq(fresh.timelockDelay(), 1 days, "Default delay");
        assertEq(fresh.EXECUTION_WINDOW(), 3 days, "Window");
        assertEq(fresh.nextActionId(), 1, "First ID");
    }

    // Scenarios: BLCT-CONSTRUCTOR-P03.
    function test_givenConfigActiveTrue_givenConfigEnabledFalse_whenConstructed_thenDisabledDefaults(
        address deployer_
    ) public {
        _setState(_config, true, false);
        vm.prank(deployer_);
        BurnerLoansConfigTimelock fresh = new BurnerLoansConfigTimelock(_kernel, _config);
        assertEq(address(fresh.kernel()), address(_kernel), "Immutable Kernel");
        assertEq(address(fresh.burnerLoans()), address(_config), "Immutable Config");
        assertFalse(fresh.isEnabled(), "Starts disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Never enabled");
        assertEq(fresh.gracePeriod(), 7 days, "Default grace");
        assertEq(fresh.timelockDelay(), 1 days, "Default delay");
        assertEq(fresh.EXECUTION_WINDOW(), 3 days, "Window");
        assertEq(fresh.nextActionId(), 1, "First ID");
    }

    // Scenarios: BLCT-CONSTRUCTOR-P04.
    function test_givenConfigActiveFalse_givenConfigEnabledTrue_whenConstructed_thenDisabledDefaults(
        address deployer_
    ) public {
        _setState(_config, false, true);
        vm.prank(deployer_);
        BurnerLoansConfigTimelock fresh = new BurnerLoansConfigTimelock(_kernel, _config);
        assertEq(address(fresh.kernel()), address(_kernel), "Immutable Kernel");
        assertEq(address(fresh.burnerLoans()), address(_config), "Immutable Config");
        assertFalse(fresh.isEnabled(), "Starts disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Never enabled");
        assertEq(fresh.gracePeriod(), 7 days, "Default grace");
        assertEq(fresh.timelockDelay(), 1 days, "Default delay");
        assertEq(fresh.EXECUTION_WINDOW(), 3 days, "Window");
        assertEq(fresh.nextActionId(), 1, "First ID");
    }

    // Scenarios: BLCT-CONSTRUCTOR-P05.
    function test_givenConfigActiveFalse_givenConfigEnabledFalse_whenConstructed_thenDisabledDefaults(
        address deployer_
    ) public {
        _setState(_config, false, false);
        vm.prank(deployer_);
        BurnerLoansConfigTimelock fresh = new BurnerLoansConfigTimelock(_kernel, _config);
        assertEq(address(fresh.kernel()), address(_kernel), "Immutable Kernel");
        assertEq(address(fresh.burnerLoans()), address(_config), "Immutable Config");
        assertFalse(fresh.isEnabled(), "Starts disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Never enabled");
        assertEq(fresh.gracePeriod(), 7 days, "Default grace");
        assertEq(fresh.timelockDelay(), 1 days, "Default delay");
        assertEq(fresh.EXECUTION_WINDOW(), 3 days, "Window");
        assertEq(fresh.nextActionId(), 1, "First ID");
    }

    // Scenarios: BLCT-CONSTRUCTOR-P06.
    function test_givenRuntimeReadinessGettersRevert_whenConstructed(address deployer_) public {
        vm.mockCallRevert(address(_config), abi.encodeWithSignature("isEnabled()"), hex"ff");
        vm.mockCallRevert(address(_config), abi.encodeWithSignature("configOperator()"), hex"ff");
        vm.mockCallRevert(
            address(_kernel),
            abi.encodeWithSignature("isPolicyActive(address)", address(_config)),
            hex"ff"
        );
        vm.prank(deployer_);
        BurnerLoansConfigTimelock fresh = new BurnerLoansConfigTimelock(_kernel, _config);
        assertEq(
            address(fresh.burnerLoans()),
            address(_config),
            "Compatible target bound without readiness reads"
        );
        assertFalse(fresh.isEnabled(), "Construction leaves queue disabled");
    }

    function _expectInvalidCore(address core_) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_InvalidCore.selector,
                core_
            )
        );
    }

    function _expectInvalidConfig() private {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(_config)
            )
        );
    }

    // Scenarios: BLCT-CONSTRUCTOR-D04.
    function test_givenZeroCore_whenConstructed_reverts(address caller_) public {
        vm.mockCall(
            address(_config),
            abi.encodeCall(IBurnerLoansConfig.facility, ()),
            abi.encode(address(0))
        );
        _expectInvalidCore(address(0));
        vm.prank(caller_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-D05.
    function test_givenEoaCore_whenConstructed_reverts(address caller_, address core_) public {
        vm.assume(core_ != address(0) && core_.code.length == 0);
        vm.mockCall(
            address(_config),
            abi.encodeCall(IBurnerLoansConfig.facility, ()),
            abi.encode(core_)
        );
        _expectInvalidCore(core_);
        vm.prank(caller_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-D06.
    function test_givenMissingCoreInterface_whenConstructed_reverts(address caller_) public {
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCall(address(_core), probe, abi.encode(false));
        _expectInvalidCore(address(_core));
        vm.prank(caller_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-D07.
    function test_givenRevertingCoreInterface_whenConstructed_reverts(address caller_) public {
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCallRevert(
            address(_core),
            probe,
            abi.encodeWithSelector(CoreDependencyReadFailed.selector)
        );
        _expectInvalidCore(address(_core));
        vm.prank(caller_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-D08.
    function test_givenMalformedCoreInterface_whenConstructed_reverts(address caller_) public {
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCall(address(_core), probe, _MALFORMED_CORE_RESPONSE);
        _expectInvalidCore(address(_core));
        vm.prank(caller_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-D09.
    function test_givenRevertingCoreBinding_whenConstructed_reverts(address caller_) public {
        vm.mockCallRevert(
            address(_config),
            abi.encodeCall(IBurnerLoansConfig.facility, ()),
            abi.encodeWithSelector(CoreDependencyReadFailed.selector)
        );
        _expectInvalidConfig();
        vm.prank(caller_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-D10.
    function test_givenMalformedCoreBinding_whenConstructed_reverts(
        address caller_,
        bytes memory data_
    ) public {
        vm.assume(data_.length != 32);
        vm.mockCall(address(_config), abi.encodeCall(IBurnerLoansConfig.facility, ()), data_);
        _expectInvalidConfig();
        vm.prank(caller_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-D10.
    function test_givenNoncanonicalCoreBinding_whenConstructed_reverts(address caller_) public {
        vm.mockCall(
            address(_config),
            abi.encodeCall(IBurnerLoansConfig.facility, ()),
            abi.encode(type(uint256).max)
        );
        _expectInvalidConfig();
        vm.prank(caller_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-P07.
    function test_givenCoreLifecycle_whenConstructed(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setState(_core, active_, enabled_);
        vm.prank(caller_);
        BurnerLoansConfigTimelock fresh = new BurnerLoansConfigTimelock(_kernel, _config);
        assertEq(address(fresh.burnerLoans()), address(_config), "Config binding preserved");
        assertFalse(fresh.isEnabled(), "Starts disabled");
        assertEq(fresh.lastTransitionAt(), 0, "No transition history");
        assertEq(fresh.nextActionId(), 1, "No queued actions");
    }

    // Scenarios: BLCT-CONSTRUCTOR-P07.
    function test_whenCoreLifecycleStatesSeeded_thenAccepted() public {
        uint256 snapshot = vm.snapshotState();
        test_givenCoreLifecycle_whenConstructed(address(this), false, false);
        assertTrue(vm.revertToState(snapshot), "Restore disabled inactive Core");
        test_givenCoreLifecycle_whenConstructed(address(this), false, true);
        assertTrue(vm.revertToState(snapshot), "Restore enabled inactive Core");
        test_givenCoreLifecycle_whenConstructed(address(this), true, false);
        assertTrue(vm.revertToState(snapshot), "Restore disabled active Core");
        test_givenCoreLifecycle_whenConstructed(address(this), true, true);
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore enabled active Core");
    }

    // Scenarios: BLCT-CONSTRUCTOR-P08.
    function test_givenUnreadableCoreLifecycle_whenConstructed(address caller_) public {
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSelector(CoreDependencyReadFailed.selector)
        );
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSelector(CoreDependencyReadFailed.selector)
        );
        vm.expectCall(address(_core), abi.encodeWithSignature("kernel()"), uint64(0));
        vm.expectCall(address(_core), abi.encodeWithSignature("isEnabled()"), uint64(0));
        vm.expectCall(
            address(_kernel),
            abi.encodeWithSignature("isPolicyActive(address)", address(_core)),
            uint64(0)
        );
        vm.prank(caller_);
        BurnerLoansConfigTimelock fresh = new BurnerLoansConfigTimelock(_kernel, _config);
        assertFalse(fresh.isEnabled(), "Starts disabled without Core lifecycle reads");
        assertEq(address(fresh.burnerLoans()), address(_config), "Config binding preserved");
    }
}
