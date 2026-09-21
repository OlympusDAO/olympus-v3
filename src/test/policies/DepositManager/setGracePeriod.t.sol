// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

import {DepositManagerTest} from "./DepositManagerTest.sol";

contract DepositManagerSetGracePeriodTest is DepositManagerTest {
    function test_givenContractIsDisabled_reverts() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(ADMIN);
        depositManager.setGracePeriod(1 days);
    }

    function test_givenCallerIsNotAdmin_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN);

        _expectRevertNotAdmin();
        vm.prank(caller_);
        depositManager.setGracePeriod(1 days);
    }

    function test_whenGracePeriodIsZero_reverts() public givenIsEnabled {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(ADMIN);
        depositManager.setGracePeriod(0);
    }

    function test_givenAdmin_setsGracePeriod(uint32 gracePeriod_) public givenIsEnabled {
        // bound constrains the value to the complete uint32 range before the conversion.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 gracePeriod = uint32(bound(gracePeriod_, 1, type(uint32).max));

        vm.prank(ADMIN);
        depositManager.setGracePeriod(gracePeriod);

        assertEq(depositManager.gracePeriod(), gracePeriod, "grace period mismatch");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
