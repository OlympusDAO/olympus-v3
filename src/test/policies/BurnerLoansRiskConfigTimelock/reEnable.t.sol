// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansRiskConfigTimelock} from "src/policies/burnerloans/BurnerLoansRiskConfigTimelock.sol";

contract BurnerLoansRiskConfigTimelockReEnableTest is BurnerLoansRiskConfigTimelockTest {
    // Scenarios: BLRCT-REENABLE-I01.
    function test_givenNeverEnabled_whenReEnabled_reverts(address caller_) public {
        BurnerLoansRiskConfigTimelock fresh = new BurnerLoansRiskConfigTimelock(_kernel, _risk);
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        fresh.reEnable();
    }

    // Scenarios: BLRCT-REENABLE-L02.
    function test_givenEnabled_whenReEnabled_reverts(address caller_) public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _timelock.reEnable();
    }

    // Scenarios: BLRCT-REENABLE-A01.
    function test_whenUnauthorized_reverts(address caller_) public {
        _outsider(caller_);
        _timelock.disable("");
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _timelock.reEnable();
    }

    // Scenarios: BLRCT-REENABLE-N01.
    function test_givenWithinGrace_whenReEnabled(
        address caller_,
        uint8 role_,
        uint32 elapsed_
    ) public {
        _proposer(caller_, role_);
        _timelock.disable("");
        vm.warp(vm.getBlockTimestamp() + bound(elapsed_, 0, _timelock.gracePeriod()));
        vm.prank(caller_);
        _timelock.reEnable();
        assertTrue(_timelock.isEnabled(), "authorized inclusive reenable");
        assertEq(_timelock.lastTransitionAt(), vm.getBlockTimestamp(), "reenable timestamp");
    }

    // Scenarios: BLRCT-REENABLE-N02.
    function test_givenAfterGrace_whenReEnabled_reverts(uint48 now_) public {
        _timelock.disable("");
        uint48 deadline = _timelock.lastTransitionAt() + _timelock.gracePeriod();
        vm.warp(bound(now_, uint256(deadline) + 1, type(uint48).max));
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        _timelock.reEnable();
    }

    // Scenarios: BLRCT-REENABLE-N03.
    function test_givenDeadlineOverflow_whenReEnabled_reverts() public {
        _timelock.setGracePeriod(type(uint32).max);
        vm.warp(type(uint48).max);
        _timelock.disable("");
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafeCastOverflowedUintDowncast(uint8,uint256)",
                uint8(48),
                uint256(type(uint48).max) + type(uint32).max
            )
        );
        _timelock.reEnable();
    }

    // Scenarios: BLRCT-REENABLE-N04.
    function test_givenMaximumDeadline_whenReEnabled() public {
        _timelock.setGracePeriod(1);
        vm.warp(uint256(type(uint48).max) - 1);
        _timelock.disable("");
        vm.warp(type(uint48).max);
        _timelock.reEnable();
        assertEq(_timelock.lastTransitionAt(), type(uint48).max, "maximum transition accepted");
    }

    // Scenarios: BLRCT-REENABLE-D01, BLRCT-REENABLE-D03.
    function test_givenRiskUnavailable_whenReEnabled_reverts(bool enabled_) public {
        _timelock.disable("");
        _setState(_risk, false, enabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_risk)
            )
        );
        _timelock.reEnable();
    }

    // Scenarios: BLRCT-REENABLE-L01.
    function test_givenInactive_whenReEnabled_reverts() public {
        _timelock.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
        _timelock.reEnable();
    }

    // Scenarios: BLRCT-REENABLE-D04.
    function test_givenWrongOperator_whenReEnabled_reverts(address operator_) public {
        vm.assume(operator_ != address(_timelock));
        _timelock.disable("");
        _risk.setConfigOperator(operator_);
        vm.expectRevert(
            IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_NotController.selector
        );
        _timelock.reEnable();
    }

    // Scenarios: BLRCT-REENABLE-D05.
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
        _timelock.reEnable();
        assertFalse(_timelock.isEnabled(), "failed transition unchanged");
    }

    // Scenarios: BLRCT-REENABLE-D06.
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
        _timelock.reEnable();
        assertFalse(_timelock.isEnabled(), "failed status preserves disabled state");
    }

    // Scenarios: BLRCT-REENABLE-D06.
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
        _timelock.reEnable();
        assertFalse(_timelock.isEnabled(), "malformed status preserves disabled state");
    }

    // Scenarios: BLRCT-REENABLE-D07.
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
        _timelock.reEnable();
    }

    // Scenarios: BLRCT-REENABLE-D07.
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
        _timelock.reEnable();
    }

    // Scenarios: BLRCT-REENABLE-P01.
    function test_givenUpstreamPaused_whenTransition() public {
        _timelock.disable("");
        _setState(_config, false, false);
        _setState(_core, false, false);
        vm.mockCallRevert(address(_config), abi.encodeWithSignature("facility()"), hex"deadbeef");
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("risk()"), hex"deadbeef");
        _timelock.reEnable();
        assertTrue(_timelock.isEnabled(), "upstream pointers do not gate Risk controller");
    }

    // Scenarios: BLRCT-REENABLE-D06.
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
        _timelock.reEnable();
    }

    // Scenarios: BLRCT-REENABLE-D07.
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
        _timelock.reEnable();
    }

    // Scenarios: BLRCT-REENABLE-D02.
    function test_givenPausedRisk_whenActivated() public {
        _timelock.disable("");
        _setState(_risk, true, false);
        vm.mockCallRevert(address(_risk), abi.encodeWithSignature("isEnabled()"), hex"deadbeef");
        _timelock.reEnable();
        assertTrue(_timelock.isEnabled(), "Paused Risk permits activation for repair");
    }

    // Scenarios: BLRCT-REENABLE-D08.
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
            _timelock.reEnable();
            assertFalse(_timelock.isEnabled(), "Incompatible target cannot activate queue");
            vm.mockCall(
                address(_risk),
                abi.encodeCall(IERC165.supportsInterface, (ids[i])),
                abi.encode(true)
            );
        }
    }
}
