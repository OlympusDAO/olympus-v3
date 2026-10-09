// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";

// Libraries
import {Vm} from "forge-std/Vm.sol";

// Contracts
import {BurnerLoansYieldRoutingTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansYieldRoutingTestBase.sol";

contract BurnerLoansConfigSetYieldRepurchaseRecipientTest is BurnerLoansYieldRoutingTestBase {
    modifier givenDefaultConfigOperator() {
        _setDefaultConfigOperator();
        _;
    }

    // Retained to express the test precondition with the suite's given* structure.
    // forge-lint: disable-next-line(modifier-used-only-once)
    modifier givenDisabled() {
        vm.prank(admin);
        burnerLoansConfig.disable("");
        _;
    }

    // Retained to express the test precondition with the suite's given* structure.
    // forge-lint: disable-next-line(modifier-used-only-once)
    modifier givenReEnabled() {
        vm.startPrank(admin);
        burnerLoansConfig.disable("");
        burnerLoansConfig.reEnable();
        vm.stopPrank();
        _;
    }

    // Retained to express the test precondition with the suite's given* structure.
    // forge-lint: disable-next-line(modifier-used-only-once)
    modifier givenFacilityRejectsRecipient() {
        yieldRecipient.setEnabled(false);
        _;
    }

    function test_givenUnauthorizedCaller_reverts(
        address caller_
    ) public givenDefaultConfigOperator {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(configTimelock));

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                caller_
            )
        );
        burnerLoansConfig.setYieldRepurchaseRecipient(address(yieldRecipient));
    }

    function test_givenDisabled_reverts() public givenDisabled {
        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoansConfig.setYieldRepurchaseRecipient(address(yieldRecipient));
    }

    function test_givenReEnabled_givenAdmin_forwardsWithoutDuplicateStateOrEvent()
        public
        givenReEnabled
    {
        vm.recordLogs();
        vm.prank(admin);
        burnerLoansConfig.setYieldRepurchaseRecipient(address(yieldRecipient));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1, "configuration event count");
        assertEq(entries[0].emitter, address(burnerLoans), "configuration event emitter");
        assertEq(
            burnerLoans.getYieldRepurchaseRecipient(),
            address(yieldRecipient),
            "yield repurchase recipient"
        );
    }

    function test_givenConfigOperator_forwards() public givenDefaultConfigOperator {
        vm.prank(address(configTimelock));
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit IBurnerLoans.YieldRepurchaseRecipientSet(address(yieldRecipient));
        burnerLoansConfig.setYieldRepurchaseRecipient(address(yieldRecipient));

        assertEq(
            burnerLoans.getYieldRepurchaseRecipient(),
            address(yieldRecipient),
            "yield repurchase recipient"
        );
    }

    function test_givenFacilityRejectsRecipient_propagatesCustomError()
        public
        givenFacilityRejectsRecipient
    {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotEnabled.selector,
                address(yieldRecipient)
            )
        );
        burnerLoansConfig.setYieldRepurchaseRecipient(address(yieldRecipient));
    }
}
