// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansConfigTimelock} from "src/policies/burnerloans/BurnerLoansConfigTimelock.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract BurnerLoansConfigTimelockEnableTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLCT-ENABLE-D01.
    function test_givenConfigActiveFalse_givenConfigEnabledTrue_whenEnable_reverts(
        address caller_
    ) public {
        _admin(caller_);
        _timelock.disable("");
        _setState(_config, false, true);
        _transitionReverts(
            abi.encodeCall(_timelock.enable, (bytes(""))),
            caller_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_config)
            )
        );
    }

    // Scenarios: BLCT-ENABLE-D02.
    function test_givenConfigActiveTrue_givenConfigEnabledFalse_whenEnable_thenEnabled(
        address caller_
    ) public {
        _admin(caller_);
        _timelock.disable("");
        _setState(_config, true, false);
        vm.mockCallRevert(address(_config), abi.encodeWithSignature("isEnabled()"), hex"deadbeef");
        bytes32 funds = _economicDigest();
        _expectTransition(caller_, true, "");
        vm.prank(caller_);
        _timelock.enable("");
        assertTrue(_timelock.isEnabled(), "Paused target permits activation for repair");
        assertEq(_economicDigest(), funds, "Activation preserves accounting");
    }

    // Scenarios: BLCT-ENABLE-D03.
    function test_givenConfigActiveFalse_givenConfigEnabledFalse_whenEnable_reverts(
        address caller_
    ) public {
        _admin(caller_);
        _timelock.disable("");
        _setState(_config, false, false);
        _transitionReverts(
            abi.encodeCall(_timelock.enable, (bytes(""))),
            caller_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_config)
            )
        );
    }

    // Scenarios: BLCT-ENABLE-D04.
    function test_givenForeignConfigKernel_whenEnable_reverts(address caller_) public {
        _admin(caller_);
        _timelock.disable("");
        Kernel other = new Kernel();
        vm.mockCall(
            address(_config),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(other))
        );
        _transitionReverts(
            abi.encodeCall(_timelock.enable, (bytes(""))),
            caller_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_config),
                address(_kernel),
                address(other)
            )
        );
    }

    // Scenarios: BLCT-ENABLE-L02.
    function test_givenOwnPolicyInactive_whenEnable_reverts(address caller_) public {
        _admin(caller_);
        _setState(_timelock, false, false);
        _transitionReverts(
            abi.encodeCall(_timelock.enable, (bytes(""))),
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-ENABLE-D06.
    function test_givenRiskOperatorIndependent_whenEnable_thenEnabled(
        address caller_,
        bool zero_
    ) public {
        _admin(caller_);
        _timelock.disable("");
        _risk.setConfigOperator(zero_ ? address(0) : _recipient);
        _expectTransition(caller_, true, "");
        vm.prank(caller_);
        _timelock.enable("");
        assertTrue(_timelock.isEnabled(), "Risk controller does not constrain activation");
    }

    // Scenarios: BLCT-ENABLE-A01.
    function test_givenAdmin_whenEnabled_thenExactTransition(address caller_) public {
        _admin(caller_);
        _timelock.disable("");
        bytes32 funds = _economicDigest();
        _expectTransition(caller_, true, "");
        vm.prank(caller_);
        _timelock.enable("");
        assertTrue(_timelock.isEnabled(), "Enabled");
        assertEq(_timelock.lastTransitionAt(), vm.getBlockTimestamp(), "Transition time");
        assertEq(_economicDigest(), funds, "Activation preserves accounting");
    }

    // Scenarios: BLCT-ENABLE-A02.
    function test_givenNonAdmin_whenEnabled_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _timelock.disable("");
        _transitionReverts(
            abi.encodeCall(_timelock.enable, (bytes(""))),
            caller_,
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: BLCT-ENABLE-I01.
    function test_givenAdmin_whenNonemptyData_reverts(address caller_, bytes memory data_) public {
        _admin(caller_);
        data_ = _nonempty(data_);
        _timelock.disable("");
        _transitionReverts(
            abi.encodeCall(_timelock.enable, (data_)),
            caller_,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector)
        );
    }

    // Scenarios: BLCT-ENABLE-I02.
    function test_givenEnabled_whenNonemptyEnableData_thenStateError(
        address caller_,
        bytes memory data_
    ) public {
        data_ = _nonempty(data_);
        _transitionReverts(
            abi.encodeCall(_timelock.enable, (data_)),
            caller_,
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: BLCT-ENABLE-I03.
    function test_givenNonAdmin_whenNonemptyData_thenRoleError(
        address caller_,
        bytes memory data_
    ) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        data_ = _nonempty(data_);
        _timelock.disable("");
        _transitionReverts(
            abi.encodeCall(_timelock.enable, (data_)),
            caller_,
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: BLCT-ENABLE-L01.
    function test_givenAlreadyEnabled_whenEnableCalled_thenStateError(
        address caller_,
        bool active_
    ) public {
        _setState(_timelock, active_, true);
        _transitionReverts(
            abi.encodeCall(_timelock.enable, (bytes(""))),
            caller_,
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: BLCT-ENABLE-L03.
    function test_givenNeverActivated_whenEnabled_thenUnsetRolesCallReverts(
        address caller_
    ) public {
        _timelock = new BurnerLoansConfigTimelock(_kernel, _config);
        _transitionReverts(abi.encodeCall(_timelock.enable, (bytes(""))), caller_, bytes(""));
    }

    // Scenarios: BLCT-ENABLE-I01.
    function test_givenEnableI01Payloads_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenAdmin_whenNonemptyData_reverts(address(0xabc1), hex"00");
        _restore(checkpoint);
        test_givenAdmin_whenNonemptyData_reverts(address(0xabc1), hex"01");
        _restore(checkpoint);
        test_givenAdmin_whenNonemptyData_reverts(address(0xabc1), abi.encode(uint256(0)));
        _restore(checkpoint);
        test_givenAdmin_whenNonemptyData_reverts(address(0xabc1), new bytes(256));
        _restore(checkpoint);
    }

    // Scenarios: BLCT-ENABLE-I02.
    function test_givenEnableI02Payloads_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenEnabled_whenNonemptyEnableData_thenStateError(address(0xabc1), hex"00");
        _restore(checkpoint);
        test_givenEnabled_whenNonemptyEnableData_thenStateError(address(0xabc1), hex"01");
        _restore(checkpoint);
        test_givenEnabled_whenNonemptyEnableData_thenStateError(
            address(0xabc1),
            abi.encode(uint256(0))
        );
        _restore(checkpoint);
        test_givenEnabled_whenNonemptyEnableData_thenStateError(address(0xabc1), new bytes(256));
        _restore(checkpoint);
    }

    // Scenarios: BLCT-ENABLE-I03.
    function test_givenEnableI03Payloads_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenNonAdmin_whenNonemptyData_thenRoleError(address(0xabc1), hex"00");
        _restore(checkpoint);
        test_givenNonAdmin_whenNonemptyData_thenRoleError(address(0xabc1), hex"01");
        _restore(checkpoint);
        test_givenNonAdmin_whenNonemptyData_thenRoleError(address(0xabc1), abi.encode(uint256(0)));
        _restore(checkpoint);
        test_givenNonAdmin_whenNonemptyData_thenRoleError(address(0xabc1), new bytes(256));
        _restore(checkpoint);
    }

    // Scenarios: BLCT-ENABLE-D07.
    function test_givenMissingConsumedInterface_whenActivated_reverts(bool enabled_) public {
        _timelock.disable("");
        _setState(_config, true, enabled_);
        bytes4[3] memory ids = [
            type(IBurnerLoansConfig).interfaceId,
            type(IConfigOperator).interfaceId,
            type(IEnabler).interfaceId
        ];
        for (uint256 i; i < ids.length; ++i) {
            vm.mockCall(
                address(_config),
                abi.encodeCall(IERC165.supportsInterface, (ids[i])),
                abi.encode(false)
            );
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansConfigTimelock
                        .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                        .selector,
                    address(_config)
                )
            );
            _timelock.enable("");
            assertFalse(_timelock.isEnabled(), "Incompatible target cannot activate queue");
            vm.mockCall(
                address(_config),
                abi.encodeCall(IERC165.supportsInterface, (ids[i])),
                abi.encode(true)
            );
        }
    }
}
