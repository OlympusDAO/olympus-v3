// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant)

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";
import {Kernel, Keycode, Permissions, toKeycode} from "src/Kernel.sol";

contract BurnerLoansInventoryRequestPermissionsTest is BurnerLoansInventoryTest {
    function test_requestsOnlyMintrPermissions() public view {
        Permissions[] memory permissions = inventory.requestPermissions();
        Keycode mintrKeycode = toKeycode("MINTR");
        assertEq(permissions.length, 4, "permissions length");
        for (uint256 i; i < permissions.length; ++i) {
            assertEq(
                Keycode.unwrap(permissions[i].keycode),
                Keycode.unwrap(mintrKeycode),
                "keycode"
            );
        }
        assertEq(permissions[0].funcSelector, mintr.mintOhm.selector, "mint selector");
        assertEq(permissions[1].funcSelector, mintr.burnOhm.selector, "burn selector");
        assertEq(
            permissions[2].funcSelector,
            mintr.increaseMintApproval.selector,
            "increase selector"
        );
        assertEq(
            permissions[3].funcSelector,
            mintr.decreaseMintApproval.selector,
            "decrease selector"
        );
    }

    // Scenarios: BLINV-PERMISSIONS-P01.
    function test_givenLifecycle_whenReadByAnyCaller(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _givenInitialLifecycle(active_, enabled_);
        bytes32 beforeState = _accountingState();
        vm.startPrank(caller_);
        test_requestsOnlyMintrPermissions();
        vm.stopPrank();
        assertEq(_accountingState(), beforeState, "Read preserves accounting");
        vm.prank(address(kernel));
        inventory.changeKernel(Kernel(address(0)));
        vm.startPrank(caller_);
        test_requestsOnlyMintrPermissions();
        vm.stopPrank();
    }

    // Scenarios: BLINV-PERMISSIONS-P01.
    function test_whenReadLifecycleSeeds() public {
        for (uint8 flags; flags < 4; ++flags) {
            uint256 snapshot = vm.snapshotState();
            test_givenLifecycle_whenReadByAnyCaller(outsider, flags & 1 != 0, flags & 2 != 0);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore read lifecycle seed");
        }
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant)
