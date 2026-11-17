// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Contracts
import {BackingOracleTest, IBackingOracle, IEnabler, ROLESv1} from "./fixtures/BackingOracleTest.sol";
import {Actions} from "src/Kernel.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract BackingOracleEnableTest is BackingOracleTest {
    // Scenarios: BO-ENABLE-10.
    function test_givenReactivated_whenEnable() public givenInactive {
        _kernel.executeAction(Actions.ActivatePolicy, address(_oracle));
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(uint256(1)));
        assertTrue(_oracle.isEnabled(), "reactivated enable");
    }

    // Scenarios: BO-ENABLE-01.
    function test_whenNonzero(uint256 value_) public {
        value_ = bound(value_, 1, type(uint256).max);
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(value_));
        assertEq(_oracle.backing(), value_, "initial backing");
        assertTrue(_oracle.isEnabled(), "enabled");
        assertEq(_oracle.lastTransitionAt(), vm.getBlockTimestamp(), "transition timestamp");
    }

    // Scenarios: BO-ENABLE-02.
    function test_whenOne() public {
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(uint256(1)));
        assertEq(_oracle.backing(), 1, "one raw unit");
    }

    // Scenarios: BO-ENABLE-03.
    function test_whenMaximum() public {
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(type(uint256).max));
        assertEq(_oracle.backing(), type(uint256).max, "maximum initializes");
    }

    // Scenarios: BO-ENABLE-04.
    function test_whenZero_reverts() public {
        vm.expectRevert(IBackingOracle.BackingOracle_ZeroBacking.selector);
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(uint256(0)));
    }

    // Scenarios: BO-ENABLE-05.
    function test_whenMalformed_reverts(bytes calldata data_) public {
        vm.assume(data_.length != 32);
        vm.expectRevert(IBackingOracle.BackingOracle_InvalidEnableDataLength.selector);
        vm.prank(_ADMIN);
        _oracle.enable(data_);
    }

    // Scenarios: BO-ENABLE-06.
    function test_whenUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != _ADMIN);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _oracle.enable(abi.encode(uint256(1)));
    }

    // Scenarios: BO-ENABLE-07.
    function test_givenEnabled_whenEnable_reverts() public givenEnabled {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(uint256(1)));
    }

    // Scenarios: BO-ENABLE-08.
    function test_givenInactive_whenEnable_reverts() public givenInactive {
        _expectInactive();
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(uint256(1)));
    }

    // Scenarios: BO-ENABLE-09.
    function test_givenPreviouslyEnabled_whenEnableResetsBacking() public givenEnabled {
        vm.prank(_ADMIN);
        _oracle.disable("");
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(uint256(1)));
        assertEq(_oracle.backing(), 1, "source permits administrative reset");
    }
}
