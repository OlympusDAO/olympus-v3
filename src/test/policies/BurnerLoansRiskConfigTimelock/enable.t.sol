// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansRiskConfigTimelockEnableTest is BurnerLoansRiskConfigTimelockTest {
    // Scenarios: BLRCT-ENABLE-A01.
    function test_whenNonAdmin_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _timelock.disable("");
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _timelock.enable("");
        assertFalse(_timelock.isEnabled(), "unauthorized enable unchanged");
    }

    // Scenarios: BLRCT-ENABLE-L02.
    function test_givenEnabled_whenEnabledAgain_reverts(address caller_, bool active_) public {
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _timelock.enable(hex"01");
    }

    // Scenarios: BLRCT-ENABLE-I01.
    function test_whenNonemptyPayload_reverts(bytes memory data_) public {
        vm.assume(data_.length > 0);
        _timelock.disable("");
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        _timelock.enable(data_);
    }

    // Scenarios: BLRCT-ENABLE-P01, BLRCT-ENABLE-P02.
    function test_givenReady_whenEnabled() public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        bytes32 queued = _queueDigest(id);
        _timelock.disable("");
        vm.warp(vm.getBlockTimestamp() + 8 days);
        vm.expectEmit(address(_timelock));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_timelock));
        emit IEnablerV2.Transition(address(this), true, "", uint48(vm.getBlockTimestamp()));
        _timelock.enable("");
        assertTrue(_timelock.isEnabled(), "full admin enable");
        assertEq(_timelock.lastTransitionAt(), vm.getBlockTimestamp(), "transition timestamp");
        assertEq(_queueDigest(id), queued, "pending action preserved");
    }

    // Scenarios: BLRCT-ENABLE-L01.
    function test_givenInactive_whenEnabled_reverts() public {
        _timelock.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
        _timelock.enable("");
    }

    // Scenarios: BLRCT-ENABLE-D01, BLRCT-ENABLE-D03.
    function test_givenRiskUnavailable_whenEnabled_reverts(bool enabled_) public {
        _timelock.disable("");
        _setState(_risk, false, enabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_risk)
            )
        );
        _timelock.enable("");
    }

    // Scenarios: BLRCT-ENABLE-D04.
    function test_givenWrongOperator_whenEnabled_reverts(address operator_) public {
        vm.assume(operator_ != address(_timelock));
        _timelock.disable("");
        _risk.setConfigOperator(operator_);
        vm.expectRevert(
            IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_NotController.selector
        );
        _timelock.enable("");
    }

    // Scenarios: BLRCT-ENABLE-D05.
    function test_givenForeignKernel_whenTransition_reverts() public {
        _timelock.disable("");
        _setState(_risk, false, false);
        vm.mockCall(address(_risk), abi.encodeWithSignature("kernel()"), abi.encode(address(0xF0)));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_risk),
                address(_kernel),
                address(0xF0)
            )
        );
        _timelock.enable("");
        assertFalse(_timelock.isEnabled(), "failed transition unchanged");
    }

    // Scenarios: BLRCT-ENABLE-D06.
    function test_givenFailedKernelRead_whenTransition_reverts() public {
        _timelock.disable("");
        bytes memory callData = abi.encodeWithSignature("kernel()");
        vm.mockCallRevert(address(_risk), callData, hex"deadbeef");
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
        _timelock.enable("");
        assertFalse(_timelock.isEnabled(), "failed status preserves disabled state");
    }

    // Scenarios: BLRCT-ENABLE-D06.
    function test_givenMalformedKernelRead_whenTransition_reverts(bytes memory data_) public {
        vm.assume(data_.length != 32);
        _timelock.disable("");
        bytes memory callData = abi.encodeWithSignature("kernel()");
        vm.mockCall(address(_risk), callData, data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
        _timelock.enable("");
        assertFalse(_timelock.isEnabled(), "malformed status preserves disabled state");
    }

    // Scenarios: BLRCT-ENABLE-D07.
    function test_givenFailedOperatorRead_whenTransition_reverts() public {
        _timelock.disable("");
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSignature("configOperator()"),
            hex"deadbeef"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        _timelock.enable("");
    }

    // Scenarios: BLRCT-ENABLE-D07.
    function test_givenDirtyOperatorRead_whenTransition_reverts() public {
        _timelock.disable("");
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature("configOperator()"),
            abi.encode(type(uint256).max)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        _timelock.enable("");
    }

    // Scenarios: BLRCT-ENABLE-P01.
    function test_givenUpstreamPaused_whenTransition() public {
        _timelock.disable("");
        _setState(_config, false, false);
        _setState(_core, false, false);
        vm.mockCallRevert(address(_config), abi.encodeWithSignature("facility()"), hex"deadbeef");
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("risk()"), hex"deadbeef");
        _timelock.enable("");
        assertTrue(_timelock.isEnabled(), "upstream pointers do not gate Risk controller");
    }

    // Scenarios: BLRCT-ENABLE-D06.
    function test_givenDirtyKernelWords_whenTransition_reverts() public {
        _timelock.disable("");
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature("kernel()"),
            abi.encode(type(uint256).max)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
        _timelock.enable("");
    }

    // Scenarios: BLRCT-ENABLE-D07.
    function test_givenInvalidOperatorMetadata_whenTransition_reverts(
        bool reverts_,
        bytes memory data_
    ) public {
        vm.assume(data_.length != 32);
        _timelock.disable("");
        if (reverts_)
            vm.mockCallRevert(address(_risk), abi.encodeWithSignature("configOperator()"), data_);
        else vm.mockCall(address(_risk), abi.encodeWithSignature("configOperator()"), data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        _timelock.enable("");
    }

    // Scenarios: BLRCT-ENABLE-D02.
    function test_givenPausedRisk_whenActivated() public {
        _timelock.disable("");
        _setState(_risk, true, false);
        vm.mockCallRevert(address(_risk), abi.encodeWithSignature("isEnabled()"), hex"deadbeef");
        _timelock.enable("");
        assertTrue(_timelock.isEnabled(), "Paused Risk permits activation for repair");
    }

    // Scenarios: BLRCT-ENABLE-D08.
    function test_givenMissingConsumedInterface_whenActivated_reverts(bool enabled_) public {
        _timelock.disable("");
        _setState(_risk, true, enabled_);
        bytes4[3] memory ids = [
            type(IBurnerLoansRisk).interfaceId,
            type(IConfigOperator).interfaceId,
            type(IEnabler).interfaceId
        ];
        for (uint256 i; i < ids.length; ++i) {
            vm.mockCall(
                address(_risk),
                abi.encodeCall(IERC165.supportsInterface, (ids[i])),
                abi.encode(false)
            );
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                    address(_risk)
                )
            );
            _timelock.enable("");
            assertFalse(_timelock.isEnabled(), "Incompatible target cannot activate queue");
            vm.mockCall(
                address(_risk),
                abi.encodeCall(IERC165.supportsInterface, (ids[i])),
                abi.encode(true)
            );
        }
    }
}
