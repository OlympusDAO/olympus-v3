// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant)

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {Kernel} from "src/Kernel.sol";

contract BurnerLoansInventorySupportsInterfaceTest is BurnerLoansInventoryTest {
    function test_reportsSupportedInterfaces() public view {
        assertTrue(
            inventory.supportsInterface(type(IBurnerLoansInventory).interfaceId),
            "inventory"
        );
        assertTrue(inventory.supportsInterface(type(IVersioned).interfaceId), "versioned");
        assertTrue(
            inventory.supportsInterface(type(IConfigOperator).interfaceId),
            "config operator"
        );
        assertTrue(inventory.supportsInterface(type(IEnabler).interfaceId), "enabler");
        assertTrue(inventory.supportsInterface(type(IReEnabler).interfaceId), "re-enabler");
        assertTrue(inventory.supportsInterface(type(IGracePeriod).interfaceId), "grace period");
        assertTrue(inventory.supportsInterface(type(IEnablerV2).interfaceId), "Enabler V2");
        assertTrue(inventory.supportsInterface(type(IERC165).interfaceId), "ERC165");
        assertFalse(inventory.supportsInterface(0), "Zero identifier");
        assertFalse(inventory.supportsInterface(0xffffffff), "unknown interface");
    }

    // Scenarios: BLINV-ERC165-P01, BLINV-ERC165-P02, BLINV-ERC165-P03, BLINV-ERC165-P04, BLINV-ERC165-P05, BLINV-ERC165-P06, BLINV-ERC165-P07, BLINV-ERC165-P08, BLINV-ERC165-P09, BLINV-ERC165-P11.
    function test_givenLifecycle_whenReadByAnyCaller(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _givenInitialLifecycle(active_, enabled_);
        bytes32 beforeState = _accountingState();
        vm.startPrank(caller_);
        test_reportsSupportedInterfaces();
        vm.stopPrank();
        assertEq(_accountingState(), beforeState, "Read preserves accounting");
        vm.prank(address(kernel));
        inventory.changeKernel(Kernel(address(0)));
        vm.startPrank(caller_);
        test_reportsSupportedInterfaces();
        vm.stopPrank();
    }

    // Scenarios: BLINV-ERC165-P10.
    function test_whenUnknownInterfaceQueried(address caller_, bytes4 id_) public {
        vm.assume(
            id_ != type(IConfigOperator).interfaceId &&
                id_ != type(IBurnerLoansInventory).interfaceId &&
                id_ != type(IVersioned).interfaceId &&
                id_ != type(IEnabler).interfaceId &&
                id_ != type(IEnablerV2).interfaceId &&
                id_ != type(IReEnabler).interfaceId &&
                id_ != type(IGracePeriod).interfaceId &&
                id_ != type(IERC165).interfaceId &&
                id_ != 0 &&
                id_ != 0xffffffff
        );
        vm.prank(caller_);
        assertFalse(inventory.supportsInterface(id_), "Unsupported interface rejected");
    }

    // Scenarios: BLINV-ERC165-P01, BLINV-ERC165-P02, BLINV-ERC165-P03, BLINV-ERC165-P04, BLINV-ERC165-P05, BLINV-ERC165-P06, BLINV-ERC165-P07, BLINV-ERC165-P08, BLINV-ERC165-P09, BLINV-ERC165-P11.
    function test_whenReadLifecycleSeeds() public {
        for (uint8 flags; flags < 4; ++flags) {
            uint256 snapshot = vm.snapshotState();
            test_givenLifecycle_whenReadByAnyCaller(outsider, flags & 1 != 0, flags & 2 != 0);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore read lifecycle seed");
        }
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant)
