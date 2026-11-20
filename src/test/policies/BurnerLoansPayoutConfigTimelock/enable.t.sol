// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayoutConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansPayoutConfigTimelock.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutConfigTimelockTest} from "./BurnerLoansPayoutConfigTimelockTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansPayoutConfigTimelockEnableTest is BurnerLoansPayoutConfigTimelockTest {
    // Scenarios: BLCUCT-ENABLE-A01, BLCUCT-ENABLE-L03, BLCUCT-ENABLE-D06, BLCUCT-ENABLE-I01.
    function test_givenReadyBinding_whenActivated_thenExactTransition(
        address caller_,
        bool payoutEnabled_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenPendingRecovery {
        _grantProposer(caller_, false, false);
        _payoutTimelock.disable("");
        _setState(_core, coreActive_, coreEnabled_);
        _setState(_payout, true, payoutEnabled_);
        vm.mockCallRevert(address(_payout), abi.encodeWithSignature("isEnabled()"), hex"deadbeef");
        bytes32 beforeQueue = _queueDigest(_pendingId);
        bytes32 funds = _payoutDigest();
        vm.warp(2);
        vm.recordLogs();
        vm.expectEmit(address(_payoutTimelock));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_payoutTimelock));
        emit IEnablerV2.Transition(caller_, true, "", 2);
        vm.prank(caller_);
        _payoutTimelock.enable("");
        assertEq(_timelockLogCount(), 2, "Exactly one legacy and one transition event");
        assertTrue(_payoutTimelock.isEnabled(), "Enabled");
        assertEq(_payoutTimelock.lastTransitionAt(), 2, "Exact activation time");
        assertEq(_queueDigest(_pendingId), beforeQueue, "Queue preserved");
        assertEq(_payoutDigest(), funds, "Target preserved");
    }

    // Scenarios: BLCUCT-ENABLE-A02.
    function test_givenUnauthorizedCaller_whenActivated_reverts(
        address caller_
    ) public givenPendingRecovery {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _payoutTimelock.disable("");
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.enable, ("")),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE),
            caller_
        );
    }

    // Scenarios: BLCUCT-ENABLE-L01, BLCUCT-ENABLE-L02.
    function test_givenAlreadyEnabled_whenActivated_reverts(
        address caller_,
        bool active_
    ) public givenPendingRecovery {
        _setState(_payoutTimelock, active_, true);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.enable, ("")),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector),
            caller_
        );
    }

    // Scenarios: BLCUCT-ENABLE-L04.
    function test_givenInactivePolicy_whenActivated_reverts(
        address caller_
    ) public givenPendingRecovery {
        _grantProposer(caller_, false, false);
        _setState(_payoutTimelock, false, false);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.enable, ("")),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-ENABLE-D01.
    function test_givenWrongKernel_whenActivated_reverts(
        address caller_,
        address other_
    ) public givenPendingRecovery {
        _grantProposer(caller_, false, false);
        vm.assume(other_ != address(_kernel));
        _payoutTimelock.disable("");
        _mockPayoutKernel(other_);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.enable, ("")),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_payout),
                address(_kernel),
                other_
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-ENABLE-D02.
    function test_givenControllerChanged_whenActivated_reverts(
        address caller_
    ) public givenPendingRecovery {
        _grantProposer(caller_, false, false);
        _payoutTimelock.disable("");
        _payout.setConfigOperator(_recipient);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.enable, ("")),
            abi.encodeWithSelector(
                IBurnerLoansPayoutConfigTimelock.BurnerLoansPayoutTimelock_NotController.selector
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-ENABLE-D04.
    function test_givenKernelGetterReverts_whenActivated_reverts(
        address caller_
    ) public givenPendingRecovery {
        _grantProposer(caller_, false, false);
        _payoutTimelock.disable("");
        vm.mockCallRevert(address(_payout), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.enable, ("")),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_payout)
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-ENABLE-D05.
    function test_givenControllerGetterReverts_whenActivated_reverts(
        address caller_
    ) public givenPendingRecovery {
        _grantProposer(caller_, false, false);
        _payoutTimelock.disable("");
        vm.mockCallRevert(
            address(_payout),
            abi.encodeWithSignature("configOperator()"),
            hex"deadbeef"
        );
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.enable, ("")),
            abi.encodeWithSelector(
                IBurnerLoansPayoutConfigTimelock.BurnerLoansPayoutTimelock_InvalidPayout.selector,
                address(_payout)
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-ENABLE-I02.
    function test_whenNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenPendingRecovery {
        vm.assume(data_.length > 0 && data_.length <= 256);
        _grantProposer(caller_, false, false);
        _payoutTimelock.disable("");
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.enable, (data_)),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector),
            caller_
        );
    }

    // Scenarios: BLCUCT-ENABLE-I02.
    function test_whenPayloadBoundarySeeds_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenNonemptyPayload_reverts(address(0x111), new bytes(1));
        _restore(checkpoint);
        test_whenNonemptyPayload_reverts(address(0x112), abi.encode(uint256(0)));
        _restore(checkpoint);
        test_whenNonemptyPayload_reverts(address(0x113), new bytes(256));
        _restore(checkpoint);
    }

    // Scenarios: BLCUCT-ENABLE-D03.
    function test_givenInactivePayout_whenActivated_reverts(
        bool enabled_
    ) public givenPendingRecovery {
        _payoutTimelock.disable("");
        _setState(_payout, false, enabled_);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.enable, (bytes(""))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_payout)
            ),
            address(this)
        );
    }

    // Scenarios: BLCUCT-ENABLE-D07.
    function test_givenMissingConsumedInterface_whenActivated_reverts(bool enabled_) public {
        _payoutTimelock.disable("");
        _setState(_payout, true, enabled_);
        bytes4[3] memory ids = [
            type(IBurnerLoansPayout).interfaceId,
            type(IConfigOperator).interfaceId,
            type(IEnabler).interfaceId
        ];
        for (uint256 i; i < ids.length; ++i) {
            vm.mockCall(
                address(_payout),
                abi.encodeCall(IERC165.supportsInterface, (ids[i])),
                abi.encode(false)
            );
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansPayoutConfigTimelock
                        .BurnerLoansPayoutTimelock_InvalidPayout
                        .selector,
                    address(_payout)
                )
            );
            _payoutTimelock.enable("");
            assertFalse(_payoutTimelock.isEnabled(), "Incompatible target cannot activate queue");
            vm.mockCall(
                address(_payout),
                abi.encodeCall(IERC165.supportsInterface, (ids[i])),
                abi.encode(true)
            );
        }
    }
}
