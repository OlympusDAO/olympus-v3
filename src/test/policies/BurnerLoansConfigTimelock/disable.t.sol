// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockDisableTest is BurnerLoansConfigTimelockTest {
    uint48 internal constant _TRANSITION_TIMESTAMP = 2_345;

    event Disabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at);

    // disable
    // given caller lacks both admin and emergency
    //  when disable is called
    //   then it reverts
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != emergency);

        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        configTimelock.disable("");
    }

    // disable
    // given caller has the emergency role
    //  when disable is called
    //   then it disables the policy and records the transition
    function test_givenEmergencyCaller_disablesPolicyAndRecordsTransition() public {
        vm.warp(_TRANSITION_TIMESTAMP);

        vm.prank(emergency);
        vm.expectEmit(address(configTimelock));
        emit Disabled();
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit Transition(emergency, false, "", _TRANSITION_TIMESTAMP);
        configTimelock.disable("");

        assertFalse(configTimelock.isEnabled(), "disabled");
        assertEq(configTimelock.lastTransitionAt(), _TRANSITION_TIMESTAMP, "last transition");
    }

    // disable
    // given caller has the admin role
    //  when disable is called
    //   then it disables the policy
    function test_givenAdminCaller_disablesPolicy() public {
        vm.prank(admin);
        configTimelock.disable("");

        assertFalse(configTimelock.isEnabled(), "disabled");
    }

    // disable
    // given the timelock is already disabled
    //  when emergency calls disable
    //   then it reverts
    function test_givenAlreadyDisabled_reverts() public {
        vm.prank(emergency);
        configTimelock.disable("");

        vm.prank(emergency);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.disable("");
    }
}
