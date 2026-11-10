// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop)

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansInventory} from "src/policies/burnerloans/BurnerLoansInventory.sol";
import {BurnerLoansInventoryPrincipal} from "src/test/policies/BurnerLoansInventory/BurnerLoansInventoryPrincipal.sol";

contract BurnerLoansInventoryConstructorTest is BurnerLoansInventoryTest {
    // constructor
    function test_givenValidParameters_setsZeroState() public view {
        assertEq(inventory.ohm(), address(ohm), "OHM");
        assertEq(inventory.configOperator(), address(0), "configurator");
        assertEq(inventory.core(), address(facility), "immutable facility");
        assertFalse(inventory.isEnabled(), "enabled");
        assertEq(inventory.globalDebtCapOhm(), 0, "global cap");
        assertEq(inventory.activePrincipalOhm(), 0, "active principal");
        assertEq(inventory.suppliedIdleOhm(), 0, "supplied idle");
        assertEq(inventory.suppliedOhm(), 0, "supplied claim");
        (uint8 major, uint8 minor) = inventory.VERSION();
        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
    }

    // constructor
    function test_givenZeroOhm_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAddress.selector);
        new BurnerLoansInventory(kernel, IERC20(address(0)), address(facility));
    }

    // constructor
    function test_givenZeroFacility_reverts() public {
        vm.expectCall(
            address(0),
            abi.encodeCall(IERC165.supportsInterface, (type(IERC165).interfaceId)),
            uint64(0)
        );
        _expectInvalidCore(address(0));
        new BurnerLoansInventory(kernel, IERC20(address(ohm)), address(0));
    }

    // constructor
    function test_givenDifferentKernelFacility_reverts() public {
        BurnerLoansInventoryPrincipal foreignFacility = new BurnerLoansInventoryPrincipal(
            new Kernel(),
            address(0)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(foreignFacility),
                address(kernel),
                address(foreignFacility.kernel())
            )
        );
        new BurnerLoansInventory(kernel, IERC20(address(ohm)), address(foreignFacility));
    }

    // constructor
    function test_givenInactiveSameKernelFacility_succeeds() public {
        BurnerLoansInventoryPrincipal inactiveFacility = new BurnerLoansInventoryPrincipal(
            kernel,
            address(0)
        );

        BurnerLoansInventory deployed = new BurnerLoansInventory(
            kernel,
            IERC20(address(ohm)),
            address(inactiveFacility)
        );

        assertEq(deployed.core(), address(inactiveFacility), "immutable facility");
    }

    function _assertFresh(BurnerLoansInventory deployed_) internal view {
        assertEq(deployed_.ohm(), address(ohm), "Immutable OHM");
        assertEq(deployed_.core(), address(facility), "Immutable Core");
        assertEq(address(deployed_.kernel()), address(kernel), "Kernel");
        assertEq(deployed_.configOperator(), address(0), "No recovery controller");
        assertEq(deployed_.globalDebtCapOhm(), 0, "Zero cap");
        assertEq(deployed_.activePrincipalOhm(), 0, "Zero principal");
        assertEq(deployed_.suppliedOhm(), 0, "Zero claims");
        assertEq(deployed_.suppliedIdleOhm(), 0, "Zero idle");
        assertEq(deployed_.providerClaimOhm(provider), 0, "Zero provider claim");
        assertFalse(deployed_.isEnabled(), "Disabled initially");
        assertEq(deployed_.lastTransitionAt(), 0, "Never enabled");
        assertEq(deployed_.gracePeriod(), 7 days, "Default grace");
    }

    // Scenarios: BLINV-CONSTRUCTOR-L01, BLINV-CONSTRUCTOR-L02, BLINV-CONSTRUCTOR-L03, BLINV-CONSTRUCTOR-P02.
    function test_givenCoreLifecycle_whenAnyCallerDeploys(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setPolicyActive(address(facility), active_);
        _mockFacilityEnabled(enabled_);
        vm.prank(caller_);
        BurnerLoansInventory deployed = _newInventory();
        _assertFresh(deployed);
    }

    // Scenarios: BLINV-CONSTRUCTOR-I01.
    function test_whenZeroOhm_reverts(address caller_) public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAddress.selector);
        vm.prank(caller_);
        new BurnerLoansInventory(kernel, IERC20(address(0)), address(facility));
    }

    // Scenarios: BLINV-CONSTRUCTOR-I02.
    function test_whenZeroFacility_reverts(address caller_) public {
        vm.expectCall(
            address(0),
            abi.encodeCall(IERC165.supportsInterface, (type(IERC165).interfaceId)),
            uint64(0)
        );
        _expectInvalidCore(address(0));
        vm.prank(caller_);
        new BurnerLoansInventory(kernel, IERC20(address(ohm)), address(0));
    }

    // Scenarios: BLINV-CONSTRUCTOR-I03.
    function test_whenFacilityHasNoCode_reverts(address caller_, address eoa_) public {
        vm.assume(eoa_ != address(0) && eoa_.code.length == 0);
        _expectInvalidCore(eoa_);
        vm.prank(caller_);
        new BurnerLoansInventory(kernel, IERC20(address(ohm)), eoa_);
    }

    // Scenarios: BLINV-CONSTRUCTOR-D02.
    function test_givenMissingCoreInterface_whenDeployed_reverts(address caller_) public {
        vm.mockCall(
            address(facility),
            abi.encodeCall(IERC165.supportsInterface, (type(IBurnerLoansCore).interfaceId)),
            abi.encode(false)
        );
        vm.mockCallRevert(address(facility), abi.encodeWithSignature("kernel()"), hex"01");
        _expectInvalidCore(address(facility));
        vm.prank(caller_);
        _newInventory();
    }

    // Scenarios: BLINV-CONSTRUCTOR-D03.
    function test_givenRevertingCoreInterface_whenDeployed_reverts(address caller_) public {
        vm.mockCallRevert(
            address(facility),
            abi.encodeCall(IERC165.supportsInterface, (type(IBurnerLoansCore).interfaceId)),
            hex"deadbeef"
        );
        _expectInvalidCore(address(facility));
        vm.prank(caller_);
        _newInventory();
    }

    // Scenarios: BLINV-CONSTRUCTOR-D04.
    function test_givenMalformedCoreInterface_whenDeployed_reverts(address caller_) public {
        vm.mockCall(
            address(facility),
            abi.encodeCall(IERC165.supportsInterface, (type(IBurnerLoansCore).interfaceId)),
            hex"01"
        );
        _expectInvalidCore(address(facility));
        vm.prank(caller_);
        _newInventory();
    }

    // Scenarios: BLINV-CONSTRUCTOR-D05.
    function test_givenMissingERC165_whenDeployed_reverts(address caller_) public {
        vm.mockCall(
            address(facility),
            abi.encodeCall(IERC165.supportsInterface, (type(IERC165).interfaceId)),
            abi.encode(false)
        );
        _expectInvalidCore(address(facility));
        vm.prank(caller_);
        _newInventory();
    }

    error KernelReadFailed();

    // Scenarios: BLINV-CONSTRUCTOR-P01.
    function test_givenCoreKernelReadFails_whenDeployed_reverts(address caller_) public {
        _mockFacilityKernelRevert(abi.encodeWithSelector(KernelReadFailed.selector));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(facility)
            )
        );
        vm.prank(caller_);
        _newInventory();
    }

    // Scenarios: BLINV-CONSTRUCTOR-D01.
    function test_givenForeignKernel_whenDeployed_reverts(address caller_) public {
        _mockFacilityKernel(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(facility),
                address(kernel),
                outsider
            )
        );
        vm.prank(caller_);
        _newInventory();
    }

    // Scenarios: BLINV-CONSTRUCTOR-P01.
    function test_givenMalformedCoreMetadata_whenDeployed_reverts(
        address caller_,
        bytes memory data_
    ) public {
        vm.assume(data_.length != 32);
        vm.mockCall(address(facility), abi.encodeWithSignature("kernel()"), data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(facility)
            )
        );
        vm.prank(caller_);
        _newInventory();
    }

    // Scenarios: BLINV-CONSTRUCTOR-L01, BLINV-CONSTRUCTOR-L02, BLINV-CONSTRUCTOR-L03, BLINV-CONSTRUCTOR-P02.
    function test_whenConstructorLifecycleSeeds() public {
        for (uint8 flags; flags < 4; ++flags) {
            uint256 snapshot = vm.snapshotState();
            test_givenCoreLifecycle_whenAnyCallerDeploys(outsider, flags & 1 != 0, flags & 2 != 0);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore constructor fixture");
        }
    }

    // Scenarios: BLINV-CONSTRUCTOR-K03.
    function test_givenMalformedCoreKernel_whenDeployed_reverts(
        address caller_,
        bytes memory data_
    ) public {
        vm.assume(data_.length != 32);
        vm.mockCall(address(facility), abi.encodeWithSignature("kernel()"), data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(facility)
            )
        );
        vm.prank(caller_);
        _newInventory();
    }

    // Scenarios: BLINV-CONSTRUCTOR-K03.
    function test_givenMalformedCoreKernelBoundaries_whenDeployed_reverts(address caller_) public {
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
            vm.expectRevert(
                abi.encodeWithSelector(
                    PolicyDependency.PolicyDependency_InvalidDependency.selector,
                    address(facility)
                )
            );
            vm.prank(caller_);
            _newInventory();
        }
    }
}

// forge-lint: disable-end(calls-loop)
