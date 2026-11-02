// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";
import {BurnerLoansConfigTimelock} from "src/policies/burnerloans/BurnerLoansConfigTimelock.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract BurnerLoansConfigTimelockDisableTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLCT-DISABLE-A01.
    function test_givenAdminOrEmergency_whenDisabled_thenExactTransition(
        address caller_,
        uint8 role_
    ) public {
        _pauseCaller(caller_, role_);
        _expectTransition(caller_, false, "");
        vm.prank(caller_);
        _timelock.disable("");
        assertFalse(_timelock.isEnabled(), "Disabled");
        assertEq(_timelock.lastTransitionAt(), vm.getBlockTimestamp(), "Pause timestamp");
    }

    // Scenarios: BLCT-DISABLE-A03.
    function test_givenUnauthorizedCaller_whenDisabled_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && !_roles.hasRole(caller_, EMERGENCY_ROLE));
        _transitionReverts(
            abi.encodeCall(_timelock.disable, (bytes(""))),
            caller_,
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: BLCT-DISABLE-L01.
    function test_givenDisabledActiveTrue_whenDisabledAgain_thenStateError(address caller_) public {
        _setState(_timelock, true, false);
        _transitionReverts(
            abi.encodeCall(_timelock.disable, (bytes(""))),
            caller_,
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCT-DISABLE-L02.
    function test_givenDisabledActiveFalse_whenDisabledAgain_thenStateError(
        address caller_
    ) public {
        _setState(_timelock, false, false);
        _transitionReverts(
            abi.encodeCall(_timelock.disable, (bytes(""))),
            caller_,
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCT-DISABLE-L03.
    function test_givenConfigInactive_whenDisabled_thenSuccess(address caller_) public {
        _admin(caller_);
        _setState(_config, false, true);
        _expectTransition(caller_, false, "");
        vm.prank(caller_);
        _timelock.disable("");
        assertFalse(_timelock.isEnabled(), "Inactive policy can pause");
    }

    // Scenarios: BLCT-DISABLE-L04.
    function test_givenOwnPolicyInactive_whenDisabled_thenSuccess(address caller_) public {
        _admin(caller_);
        _setState(_timelock, false, true);
        _expectTransition(caller_, false, "");
        vm.prank(caller_);
        _timelock.disable("");
        assertFalse(_timelock.isEnabled(), "Inactive policy can pause");
    }

    // Scenarios: BLCT-DISABLE-I01.
    function test_givenAuthorizedCaller_whenNonemptyPauseData_reverts(
        address caller_,
        uint8 role_,
        bytes memory data_
    ) public {
        _pauseCaller(caller_, role_);
        data_ = _nonempty(data_);
        _transitionReverts(
            abi.encodeCall(_timelock.disable, (data_)),
            caller_,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector)
        );
    }

    // Scenarios: BLCT-DISABLE-I03.
    function test_givenDisabled_whenNonemptyPauseData_thenStateError(
        address caller_,
        bytes memory data_
    ) public {
        _timelock.disable("");
        data_ = _nonempty(data_);
        _transitionReverts(
            abi.encodeCall(_timelock.disable, (data_)),
            caller_,
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCT-DISABLE-I04.
    function test_givenUnauthorizedCaller_whenNonemptyPauseData_thenAuthorizationFirst(
        address caller_,
        bytes memory data_
    ) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && !_roles.hasRole(caller_, EMERGENCY_ROLE));
        data_ = _nonempty(data_);
        _transitionReverts(
            abi.encodeCall(_timelock.disable, (data_)),
            caller_,
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: BLCT-DISABLE-L05.
    function test_givenUninitialized_whenDisabled_thenStateError(address caller_) public {
        _timelock = new BurnerLoansConfigTimelock(_kernel, _config);
        _transitionReverts(
            abi.encodeCall(_timelock.disable, (bytes(""))),
            caller_,
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCT-DISABLE-A01.
    function test_givenEachPauseRole_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenAdminOrEmergency_whenDisabled_thenExactTransition(address(0xabc1), 0);
        _restore(checkpoint);
        test_givenAdminOrEmergency_whenDisabled_thenExactTransition(address(0xabc1), 1);
        _restore(checkpoint);
        test_givenAdminOrEmergency_whenDisabled_thenExactTransition(address(0xabc1), 2);
        _restore(checkpoint);
    }

    // Scenarios: BLCT-DISABLE-I01.
    function test_givenDisableI01Payloads_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenAuthorizedCaller_whenNonemptyPauseData_reverts(
            address(0xabc1),
            uint8(1),
            hex"00"
        );
        _restore(checkpoint);
        test_givenAuthorizedCaller_whenNonemptyPauseData_reverts(
            address(0xabc1),
            uint8(1),
            hex"01"
        );
        _restore(checkpoint);
        test_givenAuthorizedCaller_whenNonemptyPauseData_reverts(
            address(0xabc1),
            uint8(1),
            abi.encode(uint256(0))
        );
        _restore(checkpoint);
        test_givenAuthorizedCaller_whenNonemptyPauseData_reverts(
            address(0xabc1),
            uint8(1),
            new bytes(256)
        );
        _restore(checkpoint);
    }

    // Scenarios: BLCT-DISABLE-I03.
    function test_givenDisableI03Payloads_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenDisabled_whenNonemptyPauseData_thenStateError(address(0xabc1), hex"00");
        _restore(checkpoint);
        test_givenDisabled_whenNonemptyPauseData_thenStateError(address(0xabc1), hex"01");
        _restore(checkpoint);
        test_givenDisabled_whenNonemptyPauseData_thenStateError(
            address(0xabc1),
            abi.encode(uint256(0))
        );
        _restore(checkpoint);
        test_givenDisabled_whenNonemptyPauseData_thenStateError(address(0xabc1), new bytes(256));
        _restore(checkpoint);
    }

    // Scenarios: BLCT-DISABLE-I04.
    function test_givenDisableI04Payloads_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenUnauthorizedCaller_whenNonemptyPauseData_thenAuthorizationFirst(
            address(0xabc1),
            hex"00"
        );
        _restore(checkpoint);
        test_givenUnauthorizedCaller_whenNonemptyPauseData_thenAuthorizationFirst(
            address(0xabc1),
            hex"01"
        );
        _restore(checkpoint);
        test_givenUnauthorizedCaller_whenNonemptyPauseData_thenAuthorizationFirst(
            address(0xabc1),
            abi.encode(uint256(0))
        );
        _restore(checkpoint);
        test_givenUnauthorizedCaller_whenNonemptyPauseData_thenAuthorizationFirst(
            address(0xabc1),
            new bytes(256)
        );
        _restore(checkpoint);
    }
}
