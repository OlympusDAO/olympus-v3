// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast)

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventoryEnableTest is BurnerLoansInventoryTest {
    error CoreInterfaceReadFailed();

    // Scenarios: BLINV-ENABLE-A01.
    function test_givenNoConfigurator_succeeds() public {
        bytes32 beforeState = _accountingState();
        vm.expectEmit(address(inventory));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(inventory));
        emit IEnablerV2.Transition(admin, true, "", uint48(vm.getBlockTimestamp()));
        vm.prank(admin);
        inventory.enable("");
        assertTrue(inventory.isEnabled(), "Inventory enabled");
        assertEq(inventory.lastTransitionAt(), vm.getBlockTimestamp(), "Transition timestamp");
        assertEq(inventory.gracePeriod(), 7 days, "Grace unchanged");
        assertEq(_accountingState(), beforeState, "Accounting preserved");
    }

    // Scenarios: BLINV-ENABLE-D01, BLINV-ENABLE-D02, BLINV-ENABLE-D03.
    function test_givenFacilityLifecycle_whenEnabled(bool active_, bool enabled_) public {
        _setPolicyActive(address(facility), active_);
        // Core's enabled view is deliberately outside Inventory's dependency graph.
        _mockFacilityEnabled(enabled_);
        test_givenNoConfigurator_succeeds();
    }

    // Scenarios: BLINV-ENABLE-D04.
    function test_givenFacilityReportsDifferentKernel_whenEnabled_revertsThenRestored() public {
        _mockFacilityKernel(outsider);
        _expectCoreRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(facility),
                address(kernel),
                outsider
            )
        );
        vm.clearMockedCalls();
        test_givenNoConfigurator_succeeds();
    }

    // Scenarios: BLINV-ENABLE-D05.
    function test_givenUnreadableCoreMetadata_whenEnabled_revertsThenRestored(
        bytes memory data_
    ) public {
        _mockFacilityKernelRevert(data_);
        _expectCoreRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(facility)
            )
        );
        vm.clearMockedCalls();
        test_givenNoConfigurator_succeeds();
    }

    // Scenarios: BLINV-ENABLE-L02.
    function test_givenInactiveInventory_whenEnabled_reverts() public {
        _deactivateInventory();
        _expectInventoryNotActive();
        vm.prank(admin);
        inventory.enable("");
        assertFalse(inventory.isEnabled(), "Still disabled");
        assertEq(inventory.lastTransitionAt(), 0, "No transition");
        _reactivateInventory();
        test_givenNoConfigurator_succeeds();
    }

    // Scenarios: BLINV-ENABLE-A02, BLINV-ENABLE-I03.
    function test_whenCallerIsUnauthorized_reverts(address caller_, bytes memory data_) public {
        vm.assume(caller_ != admin);
        _expectAdminRole();
        vm.prank(caller_);
        inventory.enable(data_);
        assertFalse(inventory.isEnabled(), "Still disabled");
        assertEq(inventory.lastTransitionAt(), 0, "No transition");
    }

    // Scenarios: BLINV-ENABLE-I01.
    function test_whenPayloadIsNonempty_reverts(uint256 length_) public {
        bytes memory data = new bytes(bound(length_, 1, 256));
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(admin);
        inventory.enable(data);
        assertFalse(inventory.isEnabled(), "Still disabled");
        assertEq(inventory.lastTransitionAt(), 0, "No transition");
    }

    // Scenarios: BLINV-ENABLE-I01.
    function test_whenPayloadBoundarySeeds_revert() public {
        test_whenPayloadIsNonempty_reverts(1);
        test_whenPayloadIsNonempty_reverts(32);
        test_whenPayloadIsNonempty_reverts(256);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(admin);
        inventory.enable(hex"01");
    }

    // Scenarios: BLINV-ENABLE-I02, BLINV-ENABLE-L01.
    function test_givenAlreadyEnabled_whenEnabled_reverts(
        address caller_,
        bool active_,
        bytes memory data_
    ) public {
        _initializeAndEnable();
        if (!active_) _deactivateInventory();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        inventory.enable(data_);
        assertTrue(inventory.isEnabled(), "Still enabled");
    }

    // Scenarios: BLINV-ENABLE-L03.
    function test_givenUnconfiguredInventory_whenEnabled_reverts(address caller_) public {
        inventory = _newInventory();
        // A never-configured ROLES pointer returns no ABI boolean, hence exact empty revert.
        vm.expectRevert(bytes(""));
        vm.prank(caller_);
        inventory.enable("");
        assertFalse(inventory.isEnabled(), "Still disabled");
        assertEq(inventory.lastTransitionAt(), 0, "No transition");
    }

    // Scenarios: BLINV-ENABLE-D01, BLINV-ENABLE-D02, BLINV-ENABLE-D03.
    function test_whenCoreLifecycleSeeds() public {
        for (uint8 flags; flags < 4; ++flags) {
            uint256 snapshot = vm.snapshotState();
            test_givenFacilityLifecycle_whenEnabled(flags & 1 != 0, flags & 2 != 0);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore Core lifecycle seed");
        }
    }

    // Scenarios: BLINV-ENABLE-D06.
    function test_givenMissingCoreInterface_whenActivated_reverts() public {
        uint48 transition = inventory.lastTransitionAt();
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCall(address(facility), probe, abi.encode(false));
        vm.mockCallRevert(address(facility), abi.encodeWithSignature("kernel()"), hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidCore.selector,
                address(facility)
            )
        );
        vm.prank(admin);
        inventory.enable("");
        assertFalse(inventory.isEnabled(), "Core incompatibility preserves paused state");
        assertEq(inventory.lastTransitionAt(), transition, "Rejection preserves transition time");
        vm.clearMockedCalls();
        vm.prank(admin);
        inventory.enable("");
        assertTrue(inventory.isEnabled(), "Restored interface permits retry");
    }

    // Scenarios: BLINV-ENABLE-D07.
    function test_givenRevertingCoreInterface_whenActivated_reverts() public {
        uint48 transition = inventory.lastTransitionAt();
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCallRevert(
            address(facility),
            probe,
            abi.encodeWithSelector(CoreInterfaceReadFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidCore.selector,
                address(facility)
            )
        );
        vm.prank(admin);
        inventory.enable("");
        assertFalse(inventory.isEnabled(), "Core incompatibility preserves paused state");
        assertEq(inventory.lastTransitionAt(), transition, "Rejection preserves transition time");
        vm.clearMockedCalls();
        vm.prank(admin);
        inventory.enable("");
        assertTrue(inventory.isEnabled(), "Restored interface permits retry");
    }

    // Scenarios: BLINV-ENABLE-D08.
    function test_givenMalformedCoreInterface_whenActivated_reverts() public {
        uint48 transition = inventory.lastTransitionAt();
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCall(address(facility), probe, hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidCore.selector,
                address(facility)
            )
        );
        vm.prank(admin);
        inventory.enable("");
        assertFalse(inventory.isEnabled(), "Core incompatibility preserves paused state");
        assertEq(inventory.lastTransitionAt(), transition, "Rejection preserves transition time");
        vm.clearMockedCalls();
        vm.prank(admin);
        inventory.enable("");
        assertTrue(inventory.isEnabled(), "Restored interface permits retry");
    }

    function _expectCoreRejected(bytes memory reason_) private {
        bytes32 beforeState = _accountingState();
        uint48 transition = inventory.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(reason_);
        vm.prank(admin);
        inventory.enable("");
        assertFalse(inventory.isEnabled(), "Rejected activation preserves paused state");
        assertEq(inventory.lastTransitionAt(), transition, "Rejected activation preserves history");
        assertEq(_accountingState(), beforeState, "Rejected activation preserves accounting");
        assertEq(vm.getRecordedLogs().length, 0, "Rejected activation emits no events");
    }

    // Scenarios: BLINV-ENABLE-K03.
    function test_givenMalformedCoreKernel_whenActivated_revertsThenRestored(
        bytes memory data_
    ) public {
        vm.assume(data_.length != 32);
        vm.mockCall(address(facility), abi.encodeWithSignature("kernel()"), data_);
        _expectCoreRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(facility)
            )
        );
        vm.clearMockedCalls();
        test_givenNoConfigurator_succeeds();
    }

    // Scenarios: BLINV-ENABLE-K03.
    function test_givenMalformedCoreKernelBoundaries_whenActivated_revertsThenRestored() public {
        bytes[6] memory responses = [
            new bytes(0),
            new bytes(1),
            new bytes(31),
            new bytes(33),
            new bytes(64),
            abi.encode(type(uint256).max)
        ];
        // Every response must fail with the same owned error and preserve state.
        // forge-lint: disable-next-line(calls-loop)
        for (uint256 i; i < responses.length; ++i) {
            vm.mockCall(address(facility), abi.encodeWithSignature("kernel()"), responses[i]);
            _expectCoreRejected(
                abi.encodeWithSelector(
                    PolicyDependency.PolicyDependency_InvalidDependency.selector,
                    address(facility)
                )
            );
        }
        vm.clearMockedCalls();
        test_givenNoConfigurator_succeeds();
    }

    // Scenarios: BLINV-ENABLE-K04.
    function test_givenCoreMigrated_whenActivated_revertsThenRestored() public {
        _initializeAndEnable();
        Kernel next = new Kernel();
        vm.prank(address(kernel));
        facility.changeKernel(next);
        assertTrue(kernel.isPolicyActive(facility), "Old Kernel still records Core membership");
        _disableInventory();
        _expectCoreRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(facility),
                address(kernel),
                address(next)
            )
        );
        vm.prank(address(next));
        facility.changeKernel(kernel);
        test_givenNoConfigurator_succeeds();
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast)
