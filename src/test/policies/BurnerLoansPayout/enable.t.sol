// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansPayoutEnableTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-ENABLE-L01.
    function test_givenPaused_whenEnabled_thenExactTransition(
        address caller_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenPendingBuckets {
        vm.assume(caller_ != address(0));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _payout.disable("");
        _setState(_core, coreActive_, coreEnabled_);
        bytes32 state = _ledgerDigest();
        vm.warp(2);
        vm.expectEmit(address(_payout));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_payout));
        emit IEnablerV2.Transition(caller_, true, "", 2);
        vm.prank(caller_);
        _payout.enable("");
        assertTrue(_payout.isEnabled(), "Enabled");
        assertEq(_payout.lastTransitionAt(), 2, "Exact history");
        assertEq(_ledgerDigest(), state, "Activation preserves custody and obligations");
    }

    // Scenarios: BLCU-ENABLE-A01.
    function test_givenUnauthorized_whenEnabled_reverts(
        address caller_
    ) public givenPendingBuckets {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _payout.disable("");
        _expectEnableRejected(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE),
            caller_,
            ""
        );
    }

    // Scenarios: BLCU-ENABLE-L02.
    function test_givenInactiveDisabled_whenEnabled_reverts() public givenPendingBuckets {
        _setState(_payout, false, false);
        _expectEnableRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payout)
            ),
            address(this),
            ""
        );
    }

    // Scenarios: BLCU-ENABLE-L03, BLCU-ENABLE-L04.
    function test_givenAlreadyEnabled_whenEnabled_reverts(bool active_) public givenPendingBuckets {
        _setState(_payout, active_, true);
        _expectEnableRejected(
            abi.encodeWithSelector(IEnabler.NotDisabled.selector),
            address(this),
            ""
        );
    }

    // Scenarios: BLCU-ENABLE-I01.
    function test_whenNonemptyData_reverts(bytes memory data_) public givenPendingBuckets {
        vm.assume(data_.length > 0 && data_.length <= 256);
        _payout.disable("");
        _expectEnableRejected(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector),
            address(this),
            data_
        );
    }

    // Scenarios: BLCU-ENABLE-I01.
    function test_whenNonemptyDataAtBoundaries_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenNonemptyData_reverts(hex"00");
        _restore(checkpoint);
        test_whenNonemptyData_reverts(abi.encode(uint256(0)));
        _restore(checkpoint);
        test_whenNonemptyData_reverts(new bytes(256));
    }

    // Scenarios: BLCU-ENABLE-C02.
    function test_givenCoreBusy_whenEnabled_reverts() public givenPendingBuckets {
        _payout.disable("");
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.requireNotReentrant, ()),
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector)
        );
        _expectEnableRejected(
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector),
            address(this),
            ""
        );
    }

    function _expectEnableRejected(
        bytes memory reason_,
        address caller_,
        bytes memory data_
    ) internal {
        bytes32 state = _ledgerDigest();
        bool enabled = _payout.isEnabled();
        uint48 last = _payout.lastTransitionAt();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.enable(data_);
        assertEq(_payout.isEnabled(), enabled, "Failed enable preserves state");
        assertEq(_payout.lastTransitionAt(), last, "Failed enable preserves history");
        assertEq(_ledgerDigest(), state, "Failed enable preserves obligations and balances");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
