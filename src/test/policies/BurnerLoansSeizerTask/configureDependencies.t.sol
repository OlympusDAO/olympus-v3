// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";

contract BurnerLoansSeizerTaskConfigureDependenciesTest is BurnerLoansSeizerTaskTest {
    function test_givenSeizeInactive_whenKernelActivatesTask() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_liquidation));
        BurnerLoansSeizerTask fresh = new BurnerLoansSeizerTask(
            _kernel,
            _liquidation,
            _lens,
            10,
            5,
            _EXECUTION_GAS_LIMIT
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(fresh));
        assertTrue(
            _kernel.isPolicyActive(fresh),
            "Task activation resolves ROLES without Seize readiness"
        );
        assertFalse(fresh.isEnabled(), "Kernel activation does not enable the task");
    }
}
