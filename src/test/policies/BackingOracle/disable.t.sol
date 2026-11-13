// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Contracts
import {BackingOracleTest, IEnabler, IPolicyAdmin, IBackingOracle} from "./fixtures/BackingOracleTest.sol";

contract BackingOracleDisableTest is BackingOracleTest {
    // Scenarios: BO-DISABLE-01.
    function test_whenAdminDisables() public givenEnabled {
        vm.prank(_ADMIN);
        _oracle.disable("");
        assertFalse(_oracle.isEnabled(), "disabled");
        assertEq(_oracle.backing(), 100e18, "backing readable while paused");
    }

    // Scenarios: BO-DISABLE-02.
    function test_givenInactive_whenEmergencyDisables() public givenEnabled givenInactive {
        vm.prank(_EMERGENCY);
        _oracle.disable("");
        assertFalse(_oracle.isEnabled(), "inactive emergency pause");
    }

    // Scenarios: BO-DISABLE-03.
    function test_whenUnauthorized_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != _ADMIN && caller_ != _EMERGENCY);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _oracle.disable("");
    }

    // Scenarios: BO-DISABLE-04.
    function test_givenDisabled_whenDisable_reverts() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_ADMIN);
        _oracle.disable("");
    }

    // Scenarios: BO-DISABLE-05.
    function test_whenNonemptyData_reverts(bytes calldata data_) public givenEnabled {
        vm.assume(data_.length != 0);
        vm.expectRevert(IBackingOracle.BackingOracle_InvalidDisableDataLength.selector);
        vm.prank(_ADMIN);
        _oracle.disable(data_);
    }
}
