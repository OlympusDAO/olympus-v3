// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Libraries
import {stdError} from "@forge-std-1.16.2/StdError.sol";

// Contracts
import {BackingOracleTest, IBackingOracle, IEnabler, ROLESv1, IPolicyAdmin} from "./fixtures/BackingOracleTest.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract BackingOracleSetBackingTest is BackingOracleTest {
    // Scenarios: BO-SETBACKING-19.
    function test_givenLargeBacking_whenWithinBounds(uint256 value_, bool asAdmin_) public {
        value_ = bound(value_, 9e75, 11e75);
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(uint256(1e76)));
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(_CONFIG_OPERATOR);
        // B (18 decimals) * 9,000..11,000 / 10,000 (basis points) remains 18 decimals.
        _oracle.validateSetBacking(value_);
        vm.prank(asAdmin_ ? _ADMIN : _CONFIG_OPERATOR);
        _oracle.setBacking(value_);
        assertEq(_oracle.backing(), value_, "full-precision bounds accept the exact valid update");
    }

    // Scenarios: BO-SETBACKING-20.
    function test_givenLargeBacking_whenBoundarySeeds() public {
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(uint256(1e76)));
        // floor(1e76 * 9,000 / 10,000) = 9e75, all backing values have 18 decimals.
        _oracle.validateSetBacking(9e75);
        vm.prank(_ADMIN);
        _oracle.setBacking(9e75);
        assertEq(_oracle.backing(), 9e75, "large lower endpoint is inclusive");
        // floor(9e75 * 11,000 / 10,000) = 99e74, with no fractional remainder.
        _oracle.validateSetBacking(99e74);
        vm.prank(_ADMIN);
        _oracle.setBacking(99e74);
        assertEq(_oracle.backing(), 99e74, "large upper endpoint is inclusive");
    }

    // Scenarios: BO-SETBACKING-13.
    function test_givenRecovered_whenSet() public givenRecovered {
        _oracle.validateSetBacking(100e18);
        vm.prank(_ADMIN);
        _oracle.setBacking(100e18);
        assertEq(_oracle.backing(), 100e18, "same value accepted after recovery");
    }

    // Scenarios: BO-SETBACKING-14.
    function test_givenInactiveAndDisabled_whenSet_reverts() public givenInactive {
        _expectInactive();
        _oracle.validateSetBacking(0);
        _expectInactive();
        vm.prank(_ADMIN);
        _oracle.setBacking(0);
    }

    // Scenarios: BO-SETBACKING-15.
    function test_givenOneBacking_whenSameValue() public {
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(uint256(1)));
        _oracle.validateSetBacking(1);
        vm.prank(_ADMIN);
        _oracle.setBacking(1);
        assertEq(_oracle.backing(), 1, "one raw unit remains valid");
    }

    // Scenarios: BO-SETBACKING-01.
    function test_whenWithinBounds(
        uint256 value_,
        bool asAdmin_,
        address previewCaller_
    ) public givenEnabled {
        value_ = bound(value_, 90e18, 110e18);
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(_CONFIG_OPERATOR);
        address caller = asAdmin_ ? _ADMIN : _CONFIG_OPERATOR;
        vm.prank(previewCaller_);
        _oracle.validateSetBacking(value_);
        assertEq(_oracle.backing(), 100e18, "permissionless validation is read only");
        vm.expectEmit(address(_oracle));
        emit IBackingOracle.BackingSet(value_);
        vm.prank(caller);
        _oracle.setBacking(value_);
        assertEq(_oracle.backing(), value_, "exact backing");
    }

    // Scenarios: BO-SETBACKING-02.
    function test_whenBoundarySeeds() public givenEnabled {
        _oracle.validateSetBacking(90e18);
        _oracle.validateSetBacking(110e18);
        assertEq(_oracle.backing(), 100e18, "boundary preflights are read only");
        vm.prank(_ADMIN);
        _oracle.setBacking(90e18);
        vm.prank(_ADMIN);
        _oracle.disable("");
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(100e18));
        _oracle.validateSetBacking(110e18);
        vm.prank(_ADMIN);
        _oracle.setBacking(110e18);
        assertEq(_oracle.backing(), 110e18, "inclusive upper bound");
    }

    // Scenarios: BO-SETBACKING-03.
    function test_whenBelowMinimum_reverts() public givenEnabled {
        _expectChange(90e18 - 1);
        _oracle.validateSetBacking(90e18 - 1);
        _expectChange(90e18 - 1);
        vm.prank(_ADMIN);
        _oracle.setBacking(90e18 - 1);
        assertEq(_oracle.backing(), 100e18, "rollback");
    }

    // Scenarios: BO-SETBACKING-04.
    function test_whenAboveMaximum_reverts(uint256 value_) public givenEnabled {
        value_ = bound(value_, 110e18 + 1, type(uint256).max);
        _expectChange(value_);
        _oracle.validateSetBacking(value_);
        _expectChange(value_);
        vm.prank(_ADMIN);
        _oracle.setBacking(value_);
    }

    // Scenarios: BO-SETBACKING-04.
    function test_whenAdjacentUpper_reverts() public givenEnabled {
        _expectChange(110e18 + 1);
        _oracle.validateSetBacking(110e18 + 1);
        _expectChange(110e18 + 1);
        vm.prank(_ADMIN);
        _oracle.setBacking(110e18 + 1);
        assertEq(_oracle.backing(), 100e18, "adjacent upper failures preserve backing");
    }

    // Scenarios: BO-SETBACKING-05.
    function test_whenTypeMaximum_reverts() public givenEnabled {
        _expectChange(type(uint256).max);
        _oracle.validateSetBacking(type(uint256).max);
        _expectChange(type(uint256).max);
        vm.prank(_ADMIN);
        _oracle.setBacking(type(uint256).max);
    }

    // Scenarios: BO-SETBACKING-06.
    function test_whenZero_reverts() public givenEnabled {
        vm.expectRevert(IBackingOracle.BackingOracle_ZeroBacking.selector);
        _oracle.validateSetBacking(0);
        vm.expectRevert(IBackingOracle.BackingOracle_ZeroBacking.selector);
        vm.prank(_ADMIN);
        _oracle.setBacking(0);
    }

    // Scenarios: BO-SETBACKING-07.
    function test_whenOne_reverts() public givenEnabled {
        _expectChange(1);
        _oracle.validateSetBacking(1);
        _expectChange(1);
        vm.prank(_ADMIN);
        _oracle.setBacking(1);
    }

    // Scenarios: BO-SETBACKING-08.
    function test_whenUnauthorized_reverts(address caller_) public givenEnabled {
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(_PROPOSER);
        vm.assume(caller_ != _ADMIN && caller_ != _PROPOSER);
        vm.prank(caller_);
        _oracle.validateSetBacking(100e18);
        assertEq(_oracle.backing(), 100e18, "unauthorized writer can preflight without writes");
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _oracle.setBacking(100e18);
    }

    // Scenarios: BO-SETBACKING-09.
    function test_givenDisabled_whenSet_reverts() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        _oracle.validateSetBacking(100e18);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_ADMIN);
        _oracle.setBacking(100e18);
    }

    // Scenarios: BO-SETBACKING-10.
    function test_givenInactive_whenSet_reverts() public givenEnabled givenInactive {
        _expectInactive();
        _oracle.validateSetBacking(100e18);
        _expectInactive();
        vm.prank(_ADMIN);
        _oracle.setBacking(100e18);
    }

    // Scenarios: BO-SETBACKING-11.
    function test_givenTinyBacking_whenLowerBoundRoundsDown() public {
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(uint256(19)));
        // floor(19 * 9,000 / 10,000) = 17 raw units: 17.1 rounds down.
        _oracle.validateSetBacking(17);
        vm.prank(_ADMIN);
        _oracle.setBacking(17);
        assertEq(_oracle.backing(), 17, "source floor rounding retained");
    }

    // Scenarios: BO-SETBACKING-12.
    function test_givenMaximumBacking_whenSet_panics() public {
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(type(uint256).max));
        vm.expectRevert(stdError.arithmeticError);
        _oracle.validateSetBacking(type(uint256).max);
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(_ADMIN);
        _oracle.setBacking(type(uint256).max);
        assertEq(_oracle.backing(), type(uint256).max, "unrepresentable upper bound rolls back");
    }

    // Scenarios: BO-SETBACKING-18.
    function test_givenProposerRoleOnly_whenSet_reverts() public givenEnabled {
        _oracle.validateSetBacking(100e18);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(_PROPOSER);
        _oracle.setBacking(100e18);
    }

    // Scenarios: BO-SETBACKING-17.
    function test_givenFormerOperator_whenSet_reverts() public givenEnabled {
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(_PROPOSER);
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(_EMERGENCY);
        _oracle.validateSetBacking(100e18);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(_PROPOSER);
        _oracle.setBacking(100e18);
    }

    // Scenarios: BO-SETBACKING-16.
    function test_givenRevokedOperator_whenSet_reverts() public givenEnabled {
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(_PROPOSER);
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(address(0));
        _oracle.validateSetBacking(100e18);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(_PROPOSER);
        _oracle.setBacking(100e18);
    }

    // Scenarios: BO-SETBACKING-N01.
    function test_givenTinyBacking_whenUpperBoundRoundsDown() public {
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(uint256(19)));
        // Backing has 18 decimals: floor(19 * 11,000 / 10,000) = floor(20.9) = 20 raw units.
        _oracle.validateSetBacking(20);
        assertEq(_oracle.backing(), 19, "preflight preserves fractional-bound source");
        vm.prank(_ADMIN);
        _oracle.setBacking(20);
        assertEq(_oracle.backing(), 20, "floor-rounded upper endpoint is inclusive");
    }

    // Scenarios: BO-SETBACKING-N02.
    function test_givenTinyBacking_whenBelowRoundedMinimum_reverts() public {
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(uint256(19)));
        // floor(19 * 9,000 / 10,000) = floor(17.1) = 17; 16 is one raw unit below.
        bytes memory errorData = abi.encodeWithSelector(
            IBackingOracle.BackingOracle_BackingChangeTooLarge.selector,
            19,
            16,
            17,
            20
        );
        vm.expectRevert(errorData);
        _oracle.validateSetBacking(16);
        vm.expectRevert(errorData);
        vm.prank(_ADMIN);
        _oracle.setBacking(16);
        assertEq(_oracle.backing(), 19, "both failures preserve backing");
    }

    // Scenarios: BO-SETBACKING-N03.
    function test_givenTinyBacking_whenAboveRoundedMaximum_reverts() public {
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(uint256(19)));
        // floor(19 * 11,000 / 10,000) = floor(20.9) = 20; 21 is one raw unit above.
        bytes memory errorData = abi.encodeWithSelector(
            IBackingOracle.BackingOracle_BackingChangeTooLarge.selector,
            19,
            21,
            17,
            20
        );
        vm.expectRevert(errorData);
        _oracle.validateSetBacking(21);
        vm.expectRevert(errorData);
        vm.prank(_ADMIN);
        _oracle.setBacking(21);
        assertEq(_oracle.backing(), 19, "both failures preserve backing");
    }
}
