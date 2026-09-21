// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {Test} from "forge-std/Test.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";

import {MockBurnerLoansSeizerTarget} from "./MockBurnerLoansSeizerTarget.sol";

contract BurnerLoansSeizerConfigureDependenciesTest is Test {
    function test_givenBurnerLoansInactive_activationSucceeds() public {
        Kernel kernel = new Kernel();
        OlympusRoles roles = new OlympusRoles(kernel);
        MockBurnerLoansSeizerTarget target = new MockBurnerLoansSeizerTarget(kernel);
        BurnerLoansSeizer seizer = new BurnerLoansSeizer(
            kernel,
            address(target),
            10,
            5,
            10_000_000
        );
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(seizer));

        assertTrue(kernel.isPolicyActive(seizer), "seizer active");
    }
}
