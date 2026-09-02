// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Vm} from "forge-std/Vm.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";

import {BurnerLoansYieldRoutingTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansYieldRoutingTestBase.sol";

contract BurnerLoansConfigSetYieldRecipientTest is BurnerLoansYieldRoutingTestBase {
    event YieldRecipientSet(address indexed recipient);

    function test_setYieldRecipient_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(configTimelock));

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                caller_
            )
        );
        burnerLoansConfig.setYieldRecipient(address(yieldRecipient));
    }

    function test_setYieldRecipient_givenBurnerLoansAdminCallsDirectly_reverts() public {
        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                burnerLoansAdmin
            )
        );
        burnerLoansConfig.setYieldRecipient(address(yieldRecipient));
    }

    function test_setYieldRecipient_givenConfigDisabled_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoansConfig.setYieldRecipient(address(yieldRecipient));
    }

    function test_setYieldRecipient_givenAdmin_forwardsWithoutDuplicateStateOrEvent() public {
        vm.recordLogs();
        vm.prank(admin);
        burnerLoansConfig.setYieldRecipient(address(yieldRecipient));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1, "configuration event count");
        assertEq(entries[0].emitter, address(burnerLoans), "configuration event emitter");
        assertEq(burnerLoans.getYieldRecipient(), address(yieldRecipient), "yield recipient");
    }

    function test_setYieldRecipient_givenConfigOperator_forwards() public {
        _setDefaultConfigOperator();

        vm.prank(address(configTimelock));
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit YieldRecipientSet(address(yieldRecipient));
        burnerLoansConfig.setYieldRecipient(address(yieldRecipient));

        assertEq(burnerLoans.getYieldRecipient(), address(yieldRecipient), "yield recipient");
    }
}
